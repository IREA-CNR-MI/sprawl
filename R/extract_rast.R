#' @title extract raster values on features of a vector
#' @description Function used to extract values of a single- or multi- band raster for pixels
#' corresponding to the features of a vector (Polygon, Point or Line)
#' @param in_rast input raster. Can be wither:
#' 1. A file name corresponding to a valid single- or multi- band raster (e.g. /my_folder/myfile.tif)
#' All `gdal` raster formats are supported
#' 2. An `raster`, `rasterStack` or `rasterBrick` object
#' @param in_vect input vector object containing zones from which data has to be extracted.
#'  Can be either:
#' 1. A `file name` corresponding to a valid ESRI shapefile (e.g. /my_folder/myshape.shp)
#' 2. An `R` `+sp` or `sf` object
#' @param selbands `2-element numeric array` defining starting and ending raster bands to be processed
#' (e.g., c(1, 10). Default: NULL, meaining that all bands will be processed
#' @param rastres `numeric`, if not null, the input raster is resampled to rastres prior to
#' data extraction using nearest neighbour resampling. This is useful in case the polygons are small
#' with respect to `in_rast` resolution, Default: NULL (meaning no resampling is done)
#' @param id_field `character` (optional) field of the vector file to be used to identify the
#' zones from which data is to be extracted, If NULL (or invalid) zonal statistics are extracted on each row of the
#' shapefile, and a new column named `id_feat` is used on the output to distinguish the zones, Default: NULL
#' @param summ_data `logical` If TRUE, summary statistics of values belonging to each vector zone
#' are returned in `out$stats`. Default statistics are average, median, standard deviation and variation
#' coefficient. Quantiles of the distribution can be also returned if `comp_quant == TRUE`,  Default: TRUE
#' @param full_data `logical` If TRUE, values of all pixels belonging to each vector zone are returned
#' in `out$alldata' (Setting this to FALSE can be a good idea for large datasets....), Default: TRUE
#' @param comp_quant `logical` if TRUE, also quantiles of the distributions of values are computed for each zone
#' and returned in  `out$ts_summ`, Default: FALSE
#' @param long `logical` if TRUE, extraction **on points** provides data in long form
#' @param FUN `character` or function name, Default: NULL
#' @param small `logical` if TRUE, values are returned also for small polygons not including any
#' pixel centroids. Values are taken from all cells "touched" by the small polygon, Default: TRUE
#' @param na.rm `logical` If TRUE, NA values are removed while computing statistics, Default: TRUE
#' @param maxchunk Maximum chunk size (provisional), Default: 5e+06
#' @param addfeat `logical` If TRUE, columns of the attribute table of the `in_vect` layer are
#' joined to results of the computation, Default: TRUE
#' @param addgeom `logical`, If TRUE, the output sent out as an `sf` object, preserving the geometry
#' of `in_vect`. Note that this leads to duplication of geometries, and may be very slow for
#' large datasets. Default: FALSE
#' @param keep_null `logical` If TRUE, the output preserves features of `in_vect` falling outside
#' the extent of `in_rast`. Values for these features are set to NA, Default: FALSE
#' @param verbose `logical` If TRUE, messages concerning the processing status are shown in the
#' console, Default: TRUE
#' @param ncores `numeric` maximum number of cores to be used in the processin. If NULL, defaults to
#'  available cores - 2, but up to a maximum of 8. If user-provided is greater than available cores - 2
#'  or greater than 8, ncores is re-set to the minimum between those two.
#' @return out_list `list` containing two tibbles: `out_list$summ_data` contains summary statitstics,
#' while `out_list$alldata` contains the data of all pixels extracted (see examples).
#' @export
#' @examples
#' \dontrun{
#' library(sprawl)
#' library(sprawl.data)
#' library(raster)
#' library(tibble)
#' in_polys <- read_vect(system.file("extdata","lc_polys.shp", package = "sprawl.data"),
#'                        stringsAsFactors = T)
#' in_rast  <- raster::stack(system.file("extdata", "sprawl_EVItest.tif", package = "sprawl.data"))
#' in_rast  <- raster::setZ(in_rast, doytodate(seq(1,366, by = 8), year = 2013))
#' out      <- extract_rast(in_rast, in_polys, verbose = FALSE)
#' as_tibble(out$stats)
#' as_tibble(out$alldata)
#'}
#' @importFrom sf st_crs st_transform st_geometry st_as_sf
#' @importFrom sp proj4string
#' @importFrom dplyr mutate_if
#' @importFrom tibble as_tibble
#' @importFrom raster getZ
#' @importFrom magrittr %>%
#' @rdname extract_rast
#' @author Lorenzo Busetto, phD (2017) \email{lbusett@gmail.com}
#'
extract_rast <- function(in_rast,
                       in_vect,
                       selbands     = NULL,
                       rastres      = NULL,
                       id_field     = NULL,
                       summ_data    = TRUE,
                       full_data    = TRUE,
                       comp_quant   = FALSE,
                       long         = FALSE,
                       FUN          = NULL,
                       small        = TRUE,
                       na.rm        = TRUE,
                       maxchunk     = 50E6,
                       addfeat      = TRUE,
                       addgeom      = TRUE,
                       keep_null    = FALSE,
                       verbose      = TRUE,
                       ncores       = NULL
)
{
  # create a list containing processing parameters (used to facilitate passing options to
  # accessory funcrtions)
  er_opts <- list(selbands = selbands,       rastres     = rastres,
                  id_field     = id_field,   summ_data   = summ_data, full_data = full_data,
                  comp_quant   = comp_quant, FUN         = FUN,       small       = small, na.rm     = na.rm,
                  maxchunk     = maxchunk,   addfeat   = addfeat,
                  addgeom      = addgeom,    keep_null   = keep_null, verbose   = verbose,
                  ncores       = ncores)

  #   ______________________________________________________________________________________________
  #   Check input types - send errors/warnings if not compliant + open the in_vect if      ####
  #   or raster file if filenames were passed instead than a *sp/*sf object or *raster object  ####

  call <- as.list(match.call())
  message("extract_rast --> Extracting: ", as.character(call[[2]]), "data on zones of : ",
          as.character(call[[3]]))

  in_rast   <- cast_rast(in_rast, "rastobject")
  rast_proj <- get_projstring(in_rast, abort = TRUE)

  in_vect  <- cast_vect(in_vect, "sfobject") %>%
      dplyr::mutate_if(is.character,as.factor) %>%
      tibble::as_tibble() %>%
      sf::st_as_sf()
  vect_proj <- get_projstring(in_vect, abort = TRUE)
  # if (!ras_type %in% "rastobject") {
  #   stop("Input in_rast is not a RasterStack or RasterBrick object")
  # }
  #
  # if (zone_type == "none") {
  #   stop("Input in_vect is not a valid vector/raster file or object !")
  # }
  # if (zone_type == "vectfile") {
  #   in_vect <- read_vect(in_vect, stringsAsFactors = TRUE)
  #   zone_type   <- "sfobject"
  # }
  #
  # if (zone_type == "rastfile") {
  #   in_vect <- raster(in_vect)
  #   zone_type   <- "rastobject"
  # }
  #
  # # convert to an *sf objet if input is a *sp object
  # if (zone_type == "spobject") {
  #   in_vect <- as(in_vect, "sf") %>%
  #     dplyr::mutate_if(is.character,as.factor) %>%
  #     tibble::as_tibble() %>%
  #     sf::st_as_sf()
  #   zone_type   <- "sfobject"
  # }
  #
  # if (zone_type == "sfobject") {
  #   in_vect <- in_vect %>%
  #     dplyr::mutate_if(is.character,as.factor) %>%
  #     tibble::as_tibble() %>%
  #     sf::st_as_sf()
  # }

  #   ____________________________________________________________________________
  ### check input arguments                                                   ####

  # if (!small_method %in% c("centroids", "full")) {
  #   warning("Unknown 'small_method' value - defaulting to 'centroids'")
  # }

  #   ____________________________________________________________________________
  #   Identify the bands/dates to be processed                                ####

  selbands    <- er_getbands(in_rast, selbands, er_opts$verbose)
  date_check  <- ifelse(attributes(selbands)$date_check, TRUE, FALSE )
  n_selbands  <- length(selbands)
  if (date_check) {
    dates <- raster::getZ(in_rast)
  } else {
    dates <- names(in_rast)
  }
  seldates <- dates[selbands]
  in_vect$mdxtnq = seq(1:dim(in_vect)[1])

  #   ____________________________________________________________________________
  #   Start cycling on dates/bands                                            ####

  if (n_selbands > 0) {

    #   ____________________________________________________________________________
    #   start processing for the case in which the in_vect is a vector      ####

    # if (zone_type == "sfobject") {

      # check if the id_field was passed and is correct. If not passed or not correct,
      # the record number is used as identifier in the output.
      #

      if (!is.null(id_field)) {
        if (!id_field %in% names(in_vect)) {
          warning("Invalid 'id_field' value. Values of the `id_feat` column will be set to the
                  record number of the shapefile feature")
          id_field <- NULL
          er_opts$id_field <- NULL
        } else {
          if (length(unique(as.data.frame(in_vect[,eval(id_field)])[,1])) != dim(in_vect)[1]) {
            # warning("selected ID field is not univoc ! Names of output columns (or values of 'feature' field if
            #       `long` = TRUE) will be set to the record number of the shapefile feature")
            # id_field <- NULL
          }
        }
      }

      # check if the projection of the in_vect and raster are the same - otherwise
      # reproject the in_vect on raster CRS
      if (vect_proj != rast_proj) {
        if (verbose) message("extract_rast --> Reprojecting in_vect to the projection of in_rast")
        in_vect <- in_vect %>%
          sf::st_transform(rast_proj)
      }

      #   ____________________________________________________________________________
      #   Extract values if the zone pbject is a point shapefile                  ####
      #   TODO: extraction on LINES ! )

      if (inherits(sf::st_geometry(in_vect), "sfc_POINT")) {
        # Convert the zone object to *Spatial to allow use of "raster::extract"
        out_list <- er_points(in_vect,
                              in_rast,
                              n_selbands,
                              selbands,
                              seldates,
                              id_field,
                              long,
                              date_check,
                              verbose,
                              addfeat,
                              addgeom,
                              keep_null)

        # end processing on points

        # TODO Implement processing for lines !!!!

      } else {
        #   __________________________________________________________________________________
        #   Extract values if the zone object is a polygon shapefile or already a raster  ####

        out_list <- er_polygons(in_vect,
                                in_rast,
                                seldates,
                                selbands,
                                n_selbands,
                                date_check,
                                er_opts)

      }
    # }
    return(out_list)
  } else {
    warning("Selected time range does not overlap with the one of the rasterstack input dataset !")
  }
}




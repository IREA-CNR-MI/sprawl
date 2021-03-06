% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/get_boundaries.R
\name{get_boundaries}
\alias{get_boundaries}
\title{download vecor of administrative boundaries}
\usage{
get_boundaries(iso, level = 1, path = NULL, makefold = TRUE)
}
\arguments{
\item{iso}{\code{character} iso name or 2/3 digits code of the country}

\item{level}{\code{numeric} level of administrative units returned, default: 0 (Country Level)}

\item{path}{\code{character}}

\item{makefold}{\code{character}}
}
\value{
SpatialPolygonsDataFrame containing the desired data
}
\description{
function to download administrative boundaries data from the gadm archive, starting
from a country name or ISO code, and the level of desired administrative units
}
\details{
the function is a simple wrapper to the raster::getData function, with a-priori checks
on country name or ISO code
}
\examples{
\dontrun{
 library(sprawl)
 library(sp)
 ita_boundaries <- get_boundaries("Italy", 0)
 ita_region_boundaries <- get_boundaries("ITA", 1)
 plot(ita_region_boundaries)
 }
}
\seealso{
\code{\link[raster]{getData}}
}

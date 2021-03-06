% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/import.R
\name{import_MSstats}
\alias{import_MSstats}
\title{Import data outputed by an MSstats import routine}
\usage{
import_MSstats(data)
}
\arguments{
\item{data}{Advanced: Rather than specifying \code{files}, you can enter a \link{data.frame} preloaded with
\link[data.table]{fread} default parameters.}

\item{files}{One of more \code{_with_dscore} files to import and merge.}

\item{m_score.cutoff}{Include only features with PyProphet m_score >= than this?}
}
\value{
A \link{data.frame} for input into \link{bayesprot}.
}
\description{
Reads in a set of \code{_with_dscore} datasets processed by OpenSWATH and PyProphet for processing with \link{bayesprot}.
}

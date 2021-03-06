% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/dea.R
\name{dea_metafor_pairwise}
\alias{dea_metafor_pairwise}
\title{Pair-wise mixed-effects univariate differential expression analysis with 'metafor'}
\usage{
dea_metafor_pairwise(fit, data.design = design(fit), mods = ~Condition,
  random = ~1 | Sample, ...)
}
\description{
The model is performed pair-wise across the levels of the 'Condition' in 'data.design'. Default is a standard Student's t-test model.
}

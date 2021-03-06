% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/dea.R
\name{dea_MCMCglmm}
\alias{dea_MCMCglmm}
\title{Mixed-effects univariate differential expression analysis with 'MCMCglmm'}
\usage{
dea_MCMCglmm(fit, data.design = design(fit), fixed = ~Condition,
  prior = list(R = list(V = 1, nu = 0.02)), ...)
}
\description{
Default is to a one-way ANOVA on the column 'Condition' in 'data.design'.
}

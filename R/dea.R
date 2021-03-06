#' Mixed-effects univariate differential expression analysis with 'metafor'
#'
#' Default is to a one-way ANOVA on the column 'Condition' in 'data.design'.
#'
#' @import data.table
#' @import foreach
#' @export
dea_metafor <- function(fit, data.design = design(fit), mods = ~ Condition, random = ~ 1 | Sample, ...) {
  arguments <- eval(substitute(alist(...)))
  if (any(names(arguments) == "")) stop("all arguments in ... to be passed to 'metafor::rma.mv' must be named")
  if ("yi" %in% names(arguments)) stop("do not pass a 'yi' argument to metafor")
  if ("V" %in% names(arguments)) stop("do not pass a 'V' argument to metafor")
  if ("data" %in% names(arguments)) stop("do not pass a 'data' argument to metafor")
  if ("test" %in% names(arguments)) stop("do not pass a 'test' argument to metafor")
  if (!("control" %in% names(arguments))) control = list()
  if (is.null(data.design$AssayID)) data.design <- merge(data.design, design(fit, as.data.table = T)[, .(Assay, AssayID)], by = "Assay")

  # work out real n for each level and each protein
  DT.n <- fst::read.fst(file.path(fit, "input", "input.fst"), as.data.table = T)
  DT.n <- DT.n[complete.cases(DT.n)]
  DT.n <- merge(DT.n, data.design, by = "AssayID")
  DT.n <- DT.n[, .(N = length(unique(Sample))), by = ProteinID]

  # prepare quants
  DTs <- protein_quants(fit, as.data.table = T)
  DTs <- merge(DTs, data.design, by = "AssayID")
  cts <- combn(levels(DTs$Condition), 2)
  DTs <- droplevels(DTs[complete.cases(DTs[, .(est, SE)])])
  DTs[, SE := ifelse(SE < 0.001, 0.001, SE)] # won't work if SE is 0
  DTs[, BatchID := ProteinID]
  DTs[, ProteinID := as.character(ProteinID)]
  levels(DTs$BatchID) <- substr(levels(DTs$BatchID), 1, nchar(levels(DTs$BatchID)) - 1)
  DTs <- split(DTs, by = "BatchID", keep.by = F)

  # start cluster and reproducible seed
  cl <- parallel::makeCluster(control(fit)$nthread)
  doSNOW::registerDoSNOW(cl)
  pb <- txtProgressBar(max = length(DTs), style = 3)
  output.all <- foreach(DTs.chunk = iterators::iter(DTs), .inorder = F, .packages = "data.table", .options.snow = list(progress = function(n) setTxtProgressBar(pb, n))) %dopar% {
    lapply(split(DTs.chunk, by = "ProteinID"), function(DT) {
      # input
      output <- list(input = as.data.frame(DT))

      # test
      output$fits <- vector("list", 1)
      for (i in 0:9) {
        control$sigma2.init = 0.025 + 0.1 * i
        output$log <- paste0(output$log, "[", Sys.time(), "]  attempt ", i + 1, "\n")
        try({
          output$log <- paste0(output$log, capture.output({
            output$fits[[1]] <- metafor::rma.mv(yi = est, V = SE^2, data = DT, control = control, test = "t", mods = mods, random = random, ...)
          }, type = "message"))
          output$log <- paste0(output$log, "[", Sys.time(), "]   succeeded\n")
          break
        }, silent = T)
      }

      # output
      if (!is.null(output$fits[[1]]$b) && length(output$fits[[1]]$b) > 0) {
        n.real = DT.n[ProteinID == DT$ProteinID[1], N]
        if (length(n.real) == 0) n.real <- 0
        n.test <- length(unique(DT$Sample))

        output$output <- data.table(
          Effect = rownames(output$fits[[1]]$b),
          n.test = n.test,
          n.real = n.real,
          log2FC.lower = output$fits[[1]]$ci.lb,
          log2FC = output$fits[[1]]$b[, 1],
          log2FC.upper = output$fits[[1]]$ci.ub,
          t.value = output$fits[[1]]$zval,
          p.value = output$fits[[1]]$pval
        )
      } else {
        output$output <- NULL
      }

      output
    })
  }
  setTxtProgressBar(pb, length(DTs))
  close(pb)
  parallel::stopCluster(cl)

  output.all <- unlist(output.all, recursive = F)
  class(output.all) <- "bayesprot_de_metafor"
  attr(output.all, "bayesprot_fit") <- fit
  return(output.all)
}


#' Pair-wise mixed-effects univariate differential expression analysis with 'metafor'
#'
#' The model is performed pair-wise across the levels of the 'Condition' in 'data.design'. Default is a standard Student's t-test model.
#'
#' @import data.table
#' @import foreach
#' @export
dea_metafor_pairwise <- function(fit, data.design = design(fit), mods = ~ Condition, random = ~ 1 | Sample, ...) {
  arguments <- eval(substitute(alist(...)))
  if (any(names(arguments) == "")) stop("all arguments in ... to be passed to 'metafor::rma.mv' must be named")
  if ("yi" %in% names(arguments)) stop("do not pass a 'yi' argument to metafor")
  if ("V" %in% names(arguments)) stop("do not pass a 'V' argument to metafor")
  if ("data" %in% names(arguments)) stop("do not pass a 'data' argument to metafor")
  if ("test" %in% names(arguments)) stop("do not pass a 'test' argument to metafor")
  if (!("control" %in% names(arguments))) control = list()
  if (is.null(data.design$AssayID)) data.design <- merge(data.design, design(fit, as.data.table = T)[, .(Assay, AssayID)], by = "Assay")

  # work out real n for each level and each protein
  DT.n <- fst::read.fst(file.path(fit, "input", "input.fst"), as.data.table = T)
  DT.n <- DT.n[complete.cases(DT.n)]
  DT.n <- merge(DT.n, data.design, by = "AssayID")
  DT.n <- DT.n[, .(N = length(unique(Sample))), by = .(ProteinID, Condition)]

  # prepare quants
  DTs <- protein_quants(fit, as.data.table = T)
  DTs <- merge(DTs, data.design, by = "AssayID")
  cts <- combn(levels(DTs$Condition), 2)
  DTs <- droplevels(DTs[complete.cases(DTs[, .(est, SE)])])
  DTs[, SE := ifelse(SE < 0.001, 0.001, SE)] # won't work if SE is 0
  DTs[, BatchID := ProteinID]
  DTs[, ProteinID := as.character(ProteinID)]
  levels(DTs$BatchID) <- substr(levels(DTs$BatchID), 1, nchar(levels(DTs$BatchID)) - 1)
  DTs <- split(DTs, by = "BatchID", keep.by = F)

  # start cluster and reproducible seed
  cl <- parallel::makeCluster(control(fit)$nthread)
  doSNOW::registerDoSNOW(cl)
  pb <- txtProgressBar(max = length(DTs), style = 3)
  output.all <- foreach(DTs.chunk = iterators::iter(DTs), .inorder = F, .packages = "data.table", .options.snow = list(progress = function(n) setTxtProgressBar(pb, n))) %dopar% {
    lapply(split(DTs.chunk, by = "ProteinID"), function(DT) {
      # input
      output <- list(input = as.data.frame(DT))

      # test
      output$fits <- vector("list", ncol(cts))
      for (j in 1:length(output$fit))
      {
        DT.contrast <- DT
        DT.contrast[, Condition := as.character(Condition)]
        DT.contrast[, Condition := factor(ifelse(Condition %in% cts[, j], Condition, NA), levels = cts[, j])]

        for (i in 0:9) {
          control$sigma2.init = 0.025 + 0.1 * i
          output$log <- paste0(output$log, "[", Sys.time(), "]  ", paste(cts[,j], collapse = "v"), " attempt ", i + 1, "\n")
          try({
            output$log <- paste0(output$log, capture.output({
              output$fits[[j]] <- metafor::rma.mv(yi = est, V = SE^2, data = DT.contrast, control = control, test = "t", mods = mods, random = random, ...)
            }, type = "message"))
            output$log <- paste0(output$log, "[", Sys.time(), "]   succeeded\n")
            break
          }, silent = T)
        }
      }
      names(output$fits) <- sapply(1:ncol(cts), function(j) paste(cts[,j], collapse = "v"))

      # output
      n1.real = DT.n[ProteinID == DT$ProteinID[1] & Condition == cts[1, j], N]
      if (length(n1.real) == 0) n1.real <- 0
      n2.real = DT.n[ProteinID == DT$ProteinID[1] & Condition == cts[2, j], N]
      if (length(n2.real) == 0) n2.real <- 0
      n1.test <- length(unique(DT[Condition == cts[1, j], SampleID]))
      n2.test <- length(unique(DT[Condition == cts[2, j], SampleID]))

      output$output <- rbindlist(lapply(output$fits, function(fit) {
        if (!is.null(fit$b) && length(fit$b) > 0) {
          data.table(
            Effect = paste0(paste(cts[,j], collapse = "v"), "_", rownames(fit$b)),
            n1.test = n1.test,
            n2.test = n2.test,
            n1.real = n1.real,
            n2.real = n2.real,
            log2FC.lower = fit$ci.lb,
            log2FC = fit$b[, 1],
            log2FC.upper = fit$ci.ub,
            t.value = fit$zval,
            p.value = fit$pval
          )
        } else {
          NULL
        }
      }))

      output
    })
  }
  setTxtProgressBar(pb, length(DTs))
  close(pb)
  parallel::stopCluster(cl)

  output.all <- unlist(output.all, recursive = F)
  class(output.all) <- "bayesprot_de_metafor"
  attr(output.all, "bayesprot_fit") <- fit
  return(output.all)
}


#' Mixed-effects univariate differential expression analysis with 'MCMCglmm'
#'
#' Default is to a one-way ANOVA on the column 'Condition' in 'data.design'.
#'
#' @import data.table
#' @import foreach
#' @export
dea_MCMCglmm <- function(fit, data.design = design(fit), fixed = ~ Condition, prior = list(R = list(V = 1, nu = 0.02)), ...) {
  arguments <- eval(substitute(alist(...)))
  if (any(names(arguments) == "")) stop("all arguments in ... to be passed to 'metafor::rma.mv' must be named")
  if ("mev" %in% names(arguments)) stop("do not pass a 'mev' argument to metafor")
  if ("data" %in% names(arguments)) stop("do not pass a 'data' argument to metafor")
  if ("verbose" %in% names(arguments)) stop("do not pass a 'verbose' argument to metafor")
  if (is.null(data.design$AssayID)) data.design <- merge(data.design, design(fit, as.data.table = T)[, .(Assay, AssayID)], by = "Assay")

  control = control(fit)
  fixed <- as.formula(sub("^.*~", "est ~", deparse(fixed)))

  # work out real n for each level and each protein
  DT.n <- fst::read.fst(file.path(fit, "input", "input.fst"), as.data.table = T)
  DT.n <- DT.n[complete.cases(DT.n)]
  DT.n <- merge(DT.n, data.design, by = "AssayID")
  DT.n <- DT.n[, .(N = length(unique(Sample))), by = ProteinID]

  # prepare quants
  DTs <- protein_quants(fit, as.data.table = T)
  DTs <- merge(DTs, data.design, by = "AssayID")
  cts <- combn(levels(DTs$Condition), 2)
  DTs <- droplevels(DTs[complete.cases(DTs[, .(est, SE)])])
  DTs[, SE := ifelse(SE < 0.001, 0.001, SE)] # won't work if SE is 0
  DTs[, BatchID := ProteinID]
  DTs[, ProteinID := as.character(ProteinID)]
  levels(DTs$BatchID) <- substr(levels(DTs$BatchID), 1, nchar(levels(DTs$BatchID)) - 1)
  DTs <- split(DTs, by = "BatchID", keep.by = F)

  # start cluster and reproducible seed
  cl <- parallel::makeCluster(control(fit)$nthread)
  doSNOW::registerDoSNOW(cl)
  RNGkind("L'Ecuyer-CMRG")
  parallel::clusterSetRNGStream(cl, control$model.seed)

  pb <- txtProgressBar(max = length(DTs), style = 3)
  output.all <- foreach(DTs.chunk = iterators::iter(DTs), .inorder = F, .packages = "data.table", .options.snow = list(progress = function(n) setTxtProgressBar(pb, n))) %dopar% {
    lapply(split(DTs.chunk, by = "ProteinID"), function(DT) {
      # input
      output <- list(input = as.data.frame(DT))

      # test
      output$fits <- vector("list", 1)
      output$log <- capture.output({
        output$fits[[1]] <- MCMCglmm::MCMCglmm(fixed = fixed, mev = DT$SE^2, data = DT, prior = prior, verbose = F, ...)
      }, type = "message")

      # output
      n.real = DT.n[ProteinID == DT$ProteinID[1], N]
      if (length(n.real) == 0) n.real <- 0
      n.test <- length(unique(DT$Sample))

      output$output <- rbindlist(lapply(output$fits, function(fit) {
        sum <- summary(fit)
        if (nrow(sum$solutions) > 0) {
          data.table(
            Effect = rownames(sum$solutions),
            n.test = n.test,
            n.real = n.real,
            log2FC.lower = sum$solutions[, "l-95% CI"],
            log2FC = sum$solutions[, "post.mean"],
            log2FC.upper = sum$solutions[, "u-95% CI"],
            pMCMC = sum$solutions[, "pMCMC"]
          )
        } else {
          NULL
        }
      }))

      output
    })
  }
  setTxtProgressBar(pb, length(DTs))
  close(pb)
  parallel::stopCluster(cl)

  output.all <- unlist(output.all, recursive = F)
  class(output.all) <- "bayesprot_de_MCMCglmm"
  attr(output.all, "bayesprot_fit") <- fit
  return(output.all)
}


#' Pair-wise mixed-effects univariate differential expression analysis with 'MCMCglmm'
#'
#' The model is performed pair-wise across the levels of the 'Condition' in 'data.design'. Default is a standard Student's t-test model.
#'
#' @import data.table
#' @import foreach
#' @export
dea_MCMCglmm_pairwise <- function(fit, data.design = design(fit), fixed = ~ Condition, prior = list(R = list(V = 1, nu = 0.02)), ...) {
  arguments <- eval(substitute(alist(...)))
  if (any(names(arguments) == "")) stop("all arguments in ... to be passed to 'metafor::rma.mv' must be named")
  if ("mev" %in% names(arguments)) stop("do not pass a 'mev' argument to metafor")
  if ("data" %in% names(arguments)) stop("do not pass a 'data' argument to metafor")
  if ("verbose" %in% names(arguments)) stop("do not pass a 'verbose' argument to metafor")
  if (is.null(data.design$AssayID)) data.design <- merge(data.design, design(fit, as.data.table = T)[, .(Assay, AssayID)], by = "Assay")

  control = control(fit)
  fixed <- as.formula(sub("^.*~", "est ~", deparse(fixed)))

  # work out real n for each level and each protein
  DT.n <- fst::read.fst(file.path(fit, "input", "input.fst"), as.data.table = T)
  DT.n <- DT.n[complete.cases(DT.n)]
  DT.n <- merge(DT.n, data.design, by = "AssayID")
  DT.n <- DT.n[, .(N = length(unique(Sample))), by = .(ProteinID, Condition)]

  # prepare quants
  DTs <- protein_quants(fit, as.data.table = T)
  DTs <- merge(DTs, data.design, by = "AssayID")
  cts <- combn(levels(DTs$Condition), 2)
  DTs <- droplevels(DTs[complete.cases(DTs[, .(est, SE)])])
  DTs[, SE := ifelse(SE < 0.001, 0.001, SE)] # won't work if SE is 0
  DTs[, BatchID := ProteinID]
  DTs[, ProteinID := as.character(ProteinID)]
  levels(DTs$BatchID) <- substr(levels(DTs$BatchID), 1, nchar(levels(DTs$BatchID)) - 1)
  DTs <- split(DTs, by = "BatchID", keep.by = F)

  # start cluster and reproducible seed
  cl <- parallel::makeCluster(control(fit)$nthread)
  doSNOW::registerDoSNOW(cl)
  RNGkind("L'Ecuyer-CMRG")
  parallel::clusterSetRNGStream(cl, control$model.seed)

  pb <- txtProgressBar(max = length(DTs), style = 3)
  output.all <- foreach(DTs.chunk = iterators::iter(DTs), .inorder = F, .packages = "data.table", .options.snow = list(progress = function(n) setTxtProgressBar(pb, n))) %dopar% {
    lapply(split(DTs.chunk, by = "ProteinID"), function(DT) {
      # input
      output <- list(input = as.data.frame(DT))

      # test
      output$fits <- vector("list", ncol(cts))
      for (j in 1:length(output$fit)) {
        DT.contrast <- DT
        DT.contrast[, Condition := as.character(Condition)]
        DT.contrast[, Condition := factor(ifelse(Condition %in% cts[, j], Condition, NA), levels = cts[, j])]

        output$log <- capture.output({
          output$fits[[j]] <- MCMCglmm::MCMCglmm(fixed = fixed, mev = DT.contrast$SE^2, data = DT.contrast, prior = prior, verbose = F, ...)
        }, type = "message")
       }
      names(output$fits) <- sapply(1:ncol(cts), function(j) paste(cts[,j], collapse = "v"))

      # output
      n1.real = DT.n[ProteinID == DT$ProteinID[1] & Condition == cts[1, j], N]
      if (length(n1.real) == 0) n1.real <- 0
      n2.real = DT.n[ProteinID == DT$ProteinID[1] & Condition == cts[2, j], N]
      if (length(n2.real) == 0) n2.real <- 0
      n1.test <- length(unique(DT[Condition == cts[1, j], SampleID]))
      n2.test <- length(unique(DT[Condition == cts[2, j], SampleID]))

      output$output <- rbindlist(lapply(output$fits, function(fit) {
        sol <- summary(fit)$solutions
        if (nrow(sol) > 0) {
          data.table(
            Effect = paste0(paste(cts[,j], collapse = "v"), "_", rownames(sol)),
            n1.test = n1.test,
            n2.test = n2.test,
            n1.real = n1.real,
            n2.real = n2.real,
            log2FC.lower = sol[, "l-95% CI"],
            log2FC = sol[, "post.mean"],
            log2FC.upper = sol[, "u-95% CI"],
            pMCMC = sol[, "pMCMC"]
          )
        } else {
          NULL
        }
      }))

      output
    })
  }
  setTxtProgressBar(pb, length(DTs))
  close(pb)
  parallel::stopCluster(cl)

  output.all <- unlist(output.all, recursive = F)
  class(output.all) <- "bayesprot_de_MCMCglmm"
  attr(output.all, "bayesprot_fit") <- fit
  return(output.all)
}


#' Return differential expression as a list of FDR-controlled data tables
#'
#' @import data.table
#' @import metafor
#' @export
protein_de <- function(fit, key = 1, as.data.table = F) {
  if (class(fit) == "bayesprot_de_metafor") {
    DTs.de <- rbindlist(lapply(1:length(fit), function(i) data.table(ProteinID = factor(names(fit[i])), fit[[i]]$output)))
    DTs.de <- split(DTs.de, by = "Effect", keep.by = F)
    for (DT in DTs.de) {
      setorder(DT, p.value, na.last = T)
      DT[, FDR := p.adjust(p.value, method = "BH")]
      if (!as.data.table) setDF(DT)
    }
  } else if (class(fit) == "bayesprot_de_MCMCglmm") {
    DTs.de <- rbindlist(lapply(1:length(fit), function(i) data.table(ProteinID = factor(names(fit[i])), fit[[i]]$output)))
    DTs.de <- split(DTs.de, by = "Effect", keep.by = F)
    for (DT in DTs.de) {
      DT[, log2FC.delta := log2FC.upper - log2FC.lower]
      setorder(DT, pMCMC, log2FC.delta, na.last = T)
      DT[, log2FC.delta := NULL]
      DT[, FDR := cumsum(pMCMC) / .I]
      if (!as.data.table) setDF(DT)
    }
  }
  else {
    dea.func <- control(fit)$dea.func
    if (is.character(key)) key = match(key, names(dea.func))
    deID <- formatC(key, width = ceiling(log10(length(dea.func) + 1)) + 1, format = "d", flag = "0")
    DTs.de <- fst::read.fst(file.path(fit, "model2", "de", paste0(deID, ".fst")), as.data.table = T)
    DTs.de <- split(DTs.de, by = "Effect", keep.by = F)
  }

  return(DTs.de)
}


#' Mixed-effects univariate differential expression analysis with 'metafor' (test version)
#'
#' @import data.table
#' @import foreach
#' @export
# dea_metafor2 <- function(fit, data.design = design(fit), ...) {
#   arguments <- eval(substitute(alist(...)))
#   if (any(names(arguments) == "")) stop("all arguments in ... to be passed to 'metafor::rma.mv' must be named")
#   if ("yi" %in% names(arguments)) stop("do not pass a 'yi' argument to metafor")
#   if ("V" %in% names(arguments)) stop("do not pass a 'V' argument to metafor")
#   if ("data" %in% names(arguments)) stop("do not pass a 'data' argument to metafor")
#   if ("test" %in% names(arguments)) stop("do not pass a 'test' argument to metafor")
#   if (!("control" %in% names(arguments))) control = list()
#
#   DT.design <- as.data.table(data.design)
#   DT.assays <- design(fit, as.data.table = T)[, .(AssayID, Assay)]
#   DTs <- protein_quants(fit, summary = F, as.data.table = T)
#   DTs <- droplevels(DTs[complete.cases(DTs)])
#   DTs <- split(DTs, by = "ProteinID")
#
#   # start cluster and reproducible seed
#   cl <- parallel::makeCluster(control(fit)$nthread)
#   doSNOW::registerDoSNOW(cl)
#   pb <- txtProgressBar(max = length(DTs), style = 3)
#   fits.out <- foreach(DT = iterators::iter(DTs), .packages = "data.table", .multicombine = T, .options.snow = list(progress = function(n) setTxtProgressBar(pb, n))) %dopar% {
#     mat.cov <- dcast(DT, chainID + mcmcID ~ AssayID)
#     mat.cov[, chainID := NULL]
#     mat.cov[, mcmcID := NULL]
#     mat.cov <- cov(mat.cov)
#
#     #DT.in <- DT[, .(est = median(value), var = mad(value)^2), by = .(AssayID)]
#     DT.in <- DT[, .(est = median(value), var = var(value)), by = .(AssayID)]
#     DT.in <- merge(DT.in, DT.assays, by = "AssayID", sort = F)
#     DT.in <- merge(DT.in, DT.design, by = "Assay", sort = F)
#
#     fit.out <- NULL
#     for (i in 0:9) {
#       control$sigma2.init = 0.025 + 0.1 * i
#       try( {
#         fit.out <- metafor::rma.mv(yi = est, V = var, data = DT.in, control = control, test = "t", ...)
#         break
#       })
#     }
#     fit.out
#   }
#   setTxtProgressBar(pb, length(DTs))
#   close(pb)
#   parallel::stopCluster(cl)
#
#   names(fits.out) <- names(DTs)
#   class(fits.out) <- "bayesprot_de_metafor"
#   return(fits.out)
# }






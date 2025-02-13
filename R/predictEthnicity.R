#' @title Predicts ethnicity using placental DNA methylation microarray data
#' 
#' @description Uses 1860 CpGs to predict self-reported ethnicity on placental
#' microarray data.
#'
#' @details Predicts self-reported ethnicity from 3 classes: Africans, Asians,
#' and Caucasians, using placental DNA methylation data measured on the Infinium
#' 450k/EPIC methylation array. Will return membership probabilities that often
#' reflect genetic ancestry composition.
#'
#' The input data should contain all 1860 predictors (cpgs) of the final GLMNET
#' model.
#'
#' It's recommended to use the same normalization methods used on the training
#' data: NOOB and BMIQ.
#'
#' @param betas n x m dataframe of methylation values on the beta scale (0, 1),
#' where the variables are arranged in rows, and samples in columns. Should
#' contain all 1860 predictors and be normalized with NOOB and BMIQ.
#' @param threshold A probability threshold ranging from (0, 1) to call samples
#' 'ambiguous'. Defaults to 0.75.
#' @param force run even if missing predictors. Default is `FALSE`.
#'
#' @return a [tibble][tibble::tibble-package]
#' @examples
#' ## To predict ethnicity on 450k/850k samples
#'
#' # Load placenta DNAm data
#' data(plBetas)
#' predictEthnicity(plBetas)
#' 
#' @export predictEthnicity 
predictEthnicity <- function(betas, threshold = 0.75, force = FALSE) {
  data(ethnicityCpGs, envir=environment())
  pf <- intersect(ethnicityCpGs, rownames(betas)) 
  
  if (!force) {
    
    if (any(is.na(betas[pf,]))) {
      stop(
        paste(
          "NAs present in predictor data."
        )
      )
    } 
    
    if (!all(ethnicityCpGs %in% rownames(betas))) {
      stop(paste(
        "Missing", length(setdiff(ethnicityCpGs, rownames(betas))), 
        "out of", length(ethnicityCpGs), "predictors."
      ))
    }
  }
  message(paste(length(pf), "of 1860 predictors present."))
  
  # subset down to 1860 final features
  betas <- t(betas[pf, ])
  
  # This code is modified from glmnet v3.0.2, GPL-2 license
  # modifications include reducing the number of features from the original 
  # training set, to only where coefficients != 0 (1860 features)
  # These modifications were made to significantly reduce memory size of the
  # internal object `nbeta` 
  # see https://glmnet.stanford.edu/ for original glmnet package
  
  npred <- nrow(betas) # number of samples
  dn <- list(names(nbeta), "1", dimnames(betas)[[1]])
  dp <- array(0, c(nclass, nlambda, npred), dimnames = dn) # set up results
  
  # cross product with coeeficients
  for (i in seq(nclass)) {
    fitk <- methods::cbind2(1, betas) %*%
      matrix(nbeta[[i]][c("(Intercept)", colnames(betas)), ])
    dp[i, , ] <- dp[i, , ] + t(as.matrix(fitk))
  }
  
  # probabilities
  pp <- exp(dp)
  psum <- apply(pp, c(2, 3), sum)
  probs <- data.frame(aperm(
    pp / rep(psum, rep(nclass, nlambda * npred)),
    c(3, 1, 2)
  ))
  colnames(probs) <- paste0("Prob_", dn[[1]])
  
  # classification
  link <- aperm(dp, c(3, 1, 2))
  dpp <- aperm(dp, c(3, 1, 2))
  preds <- data.frame(apply(dpp, 3, glmnet_softmax))
  colnames(preds) <- "Predicted_ethnicity_nothresh"
  
  # combine and apply thresholding
  p <- cbind(preds, probs)
  p$Highest_Prob <- apply(p[, 2:4], 1, max)
  p$Predicted_ethnicity <- ifelse(
    p$Highest_Prob < threshold, "Ambiguous",
    as.character(p$Predicted_ethnicity_nothresh)
  )
  p$Sample_ID <- rownames(p)
  p <- p[, c(7, 1, 6, 2:5)]
  
  return(tibble::as_tibble(p))
}

# This code is copied directly from glmnet v3.0.2, GPL-2 license
# see https://glmnet.stanford.edu/ for original glmnet package
# The authors and copy right holders include:
# Jerome Friedman [aut], Trevor Hastie [aut, cre], Rob Tibshirani [aut], 
# Balasubramanian Narasimhan [aut], Kenneth Tay [aut], Noah Simon [aut], 
# Junyang Qian [ctb]
glmnet_softmax <- function(x, ignore_labels = FALSE) {
  d <- dim(x)
  dd <- dimnames(x)[[2]]
  if (is.null(dd) || !length(dd)) {
    ignore_labels <- TRUE
  }
  
  nas <- apply(is.na(x), 1, any)
  if (any(nas)) {
    pclass <- rep(NA, d[1])
    if (sum(nas) < d[1]) {
      pclass2 <- glmnet_softmax(x[!nas, ], ignore_labels)
      pclass[!nas] <- pclass2
      if (is.factor(pclass2)) {
        pclass <- factor(
          pclass,
          levels = seq(d[2]),
          labels = levels(pclass2)
        )
      }
    }
  } else {
    maxdist <- x[, 1]
    pclass <- rep(1, d[1])
    for (i in seq(2, d[2])) {
      l <- x[, i] > maxdist
      pclass[l] <- i
      maxdist[l] <- x[l, i]
    }
    dd <- dimnames(x)[[2]]
    if (!ignore_labels) {
      pclass <- factor(pclass, levels = seq(d[2]), labels = dd)
    }
  }
  pclass
}

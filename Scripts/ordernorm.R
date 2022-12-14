#' Calculate and perform Ordered Quantile normalizing transformation
#'
#' @name orderNorm
#' @aliases predict.orderNorm
#'
#' @description The Ordered Quantile (ORQ) normalization transformation,
#'   \code{orderNorm()}, is a rank-based procedure by which the values of a
#'   vector are mapped to their percentile, which is then mapped to the same
#'   percentile of the normal distribution. Without the presence of ties, this
#'   essentially guarantees that the transformation leads to a uniform
#'   distribution.
#'
#'   The transformation is: \deqn{g(x) = \Phi ^ {-1} ((rank(x) - .5) /
#'   (length(x)))}
#'
#'   Where \eqn{\Phi} refers to the standard normal cdf, rank(x) refers to each
#'   observation's rank, and length(x) refers to the number of observations.
#'
#'   By itself, this method is certainly not new; the earliest mention of it
#'   that I could find is in a 1947 paper by Bartlett (see references). This
#'   formula was outlined explicitly in Van der Waerden, and expounded upon in
#'   Beasley (2009). However there is a key difference to this version of it, as
#'   explained below.
#'
#'   Using linear interpolation between these percentiles, the ORQ normalization
#'   becomes a 1-1 transformation that can be applied to new data. However,
#'   outside of the observed domain of x, it is unclear how to extrapolate the
#'   transformation. In the ORQ normalization procedure, a binomial glm with a
#'   logit link is used on the ranks in order to extrapolate beyond the bounds
#'   of the original domain of x. The inverse normal CDF is then applied to
#'   these extrapolated predictions in order to extrapolate the transformation.
#'   This mitigates the influence of heavy-tailed distributions while preserving
#'   the 1-1 nature of the transformation. The extrapolation will provide a
#'   warning unless warn = FALSE.) However, we found that the extrapolation was
#'   able to perform very well even on data as heavy-tailed as a Cauchy
#'   distribution (paper to be published).
#'
#'   The fit used to perform the extrapolation uses a default of 10000
#'   observations (or length(x) if that is less). This added approximation
#'   improves the scalability, both computationally and in terms of memory used.
#'   Do not set this value to be too low (e.g. <100), as there is no benefit to
#'   doing so. Increase if your test data set is large relative to 10000 and/or 
#'   if you are worried about losing signal in the extremes of the range.
#'
#'   This transformation can be performed on new data and inverted via the
#'   \code{predict} function.
#'
#' @param x A vector to normalize
#' @param n_logit_fit Number of points used to fit logit approximation
#' @param newdata a vector of data to be (reverse) transformed
#' @param inverse if TRUE, performs reverse transformation
#' @param object an object of class 'orderNorm'
#' @param warn transforms outside observed range or ties will yield warning
#' @param ... additional arguments
#'
#' @return A list of class \code{orderNorm} with elements
#'
#'   \item{x.t}{transformed original data} \item{x}{original data}
#'   \item{n}{number of nonmissing observations} \item{ties_status}{indicator if
#'   ties are present} \item{fit}{fit to be used for extrapolation, if needed}
#'   \item{norm_stat}{Pearson's P / degrees of freedom}
#'
#'   The \code{predict} function returns the numeric value of the transformation
#'   performed on new data, and allows for the inverse transformation as well.
#'
#' @examples
#'
#' x <- rgamma(100, 1, 1)
#'
#' orderNorm_obj <- orderNorm(x)
#' orderNorm_obj
#' p <- predict(orderNorm_obj)
#' x2 <- predict(orderNorm_obj, newdata = p, inverse = TRUE)
#'
#' all.equal(x2, x)
#' @references
#'
#' Bartlett, M. S. "The Use of Transformations." Biometrics, vol. 3, no. 1,
#' 1947, pp. 39-52. JSTOR www.jstor.org/stable/3001536.
#'
#' Van der Waerden BL. Order tests for the two-sample problem and their power.
#' 1952;55:453-458. Ser A.
#'
#' Beasley TM, Erickson S, Allison DB. Rank-based inverse normal transformations
#' are increasingly used, but are they merited? Behav. Genet. 2009;39(5):
#' 580-595. pmid:19526352
#'
#'
#' @seealso  \code{\link{boxcox}}, \code{\link{lambert}},
#'   \code{\link{bestNormalize}}, \code{\link{yeojohnson}}
#' @importFrom stats qnorm glm
#' @export
orderNorm <- function(x, n_logit_fit = min(length(x), 10000), ..., warn = TRUE) {
  stopifnot(is.numeric(x))
  ties_status <- 0
  nunique <- length(unique(x))
  na_idx <- is.na(x)
  
  if (nunique < length(x)) {
    if(warn) warning('Ties in data, Normal distribution not guaranteed\n')
    ties_status <- 1
  }
  
  q.x <- (rank(x, na.last = 'keep') - .5) / (length(x) - sum(na_idx))
  x.t <- qnorm(q.x)
  
  # fit model for future extrapolation
  # create "reduced" x with n_logit_fit equally spaced observations
  keep_idx <- round(seq(1, length(x), length.out = min(length(x), n_logit_fit)))
  x_red <- x[order(x[!na_idx])[keep_idx]]
  n_red = length(x_red)
  q_red <- (rank(x_red, na.last = 'keep') - .5) / n_red
  
  # fit model for future extrapolation
  fit <- suppressWarnings(
    glm(q_red ~ x_red, family = 'binomial', 
        weights = rep(n_red, n_red))
  )
  
  ptest <- nortest::pearson.test(x.t)
  
  val <- list(
    x.t = x.t,
    x = x,
    n = length(x) - sum(is.na(x)),
    n_logit_fit =  n_logit_fit,
    ties_status = ties_status,
    fit = fit,
    norm_stat =  unname(ptest$statistic / ptest$df)
  )
  
  class(val) <- 'orderNorm'
  val
}

#' @rdname orderNorm
#' @method predict orderNorm
#' @export
predict.orderNorm <- function(object,
                              newdata = NULL,
                              inverse = FALSE, 
                              warn = TRUE,
                              ...) {
  stopifnot(is.null(newdata) || is.numeric(newdata))
  
  # Perform transformation
  if(!inverse) {
    if(is.null(newdata)) newdata <- object$x
    na_idx <- is.na(newdata)
    
    newdata[!na_idx] <- orderNorm_trans(object, newdata[!na_idx], warn)
    return(newdata)
  } 
  
  # Perform reverse transformation
  if (is.null(newdata)) newdata <- object$x.t
  
  na_idx <- is.na(newdata)
  newdata[!na_idx] <- inv_orderNorm_trans(object, newdata[!na_idx], warn)
  
  return(newdata)
}

#' @rdname orderNorm
#' @method print orderNorm
#' @importFrom stats quantile
#' @export
print.orderNorm <- function(x, ...) {
  cat('orderNorm Transformation with', x$n, 
      'nonmissing obs and', 
      ifelse(
        x$ties_status == 1, 
        paste0('ties\n - ', length(unique(x$x)), ' unique values'),
        'no ties'), '\n',
      '- Original quantiles:\n')
  print(round(quantile(x$x, na.rm = TRUE), 3))
}

#' @importFrom stats approx fitted predict.glm qnorm
orderNorm_trans <- function(orderNorm_obj, new_points, warn) {
  x_t <- orderNorm_obj$x.t
  old_points <- orderNorm_obj$x
  vals <- suppressWarnings(
    approx(old_points, x_t, xout = new_points, rule = 1)
  )
  
  # If predictions have been made outside observed domain
  if (any(is.na(vals$y))) {
    if (warn) warning('Transformations requested outside observed domain; logit approx. on ranks applied')
    fit <- orderNorm_obj$fit
    p <- qnorm(fitted(fit, type = "response"))
    l_idx <- vals$x < min(old_points, na.rm = TRUE)
    h_idx <- vals$x > max(old_points, na.rm = TRUE)
    
    # Check 
    if (any(l_idx)) {
      xx <- data.frame(x_red = vals$x[l_idx])
      vals$y[l_idx] <- qnorm(predict(fit, newdata = xx, type = 'response')) - 
        (min(p, na.rm = TRUE) - min(x_t, na.rm = TRUE))
      
    }
    if (any(h_idx)) {
      xx <- data.frame(x_red = vals$x[h_idx])
      vals$y[h_idx] <- qnorm(predict(fit, newdata = xx, type = 'response')) - 
        (max(p, na.rm = TRUE) - max(x_t, na.rm = TRUE))
    }
  }
  
  vals$y
}

#' @importFrom stats approx fitted qnorm pnorm
inv_orderNorm_trans <- function(orderNorm_obj, new_points_x_t, warn) {
  x_t <- orderNorm_obj$x.t
  old_points <- orderNorm_obj$x
  vals <- suppressWarnings(
    approx(x_t, old_points, xout = new_points_x_t, rule = 1)
  )
  
  # If predictions have been made outside observed domain
  if (any(is.na(vals$y))) {
    if (warn) warning('Transformations requested outside observed domain; logit approx. on ranks applied')
    
    fit <- orderNorm_obj$fit
    p <- qnorm(fitted(fit, type = "response"))
    l_idx <- vals$x < min(x_t, na.rm = TRUE)
    h_idx <- vals$x > max(x_t, na.rm = TRUE)
    
    # Check 
    if (any(l_idx)) {
      # Solve algebraically from original transformation
      logits <- log(pnorm(vals$x[l_idx] + min(p, na.rm = TRUE) - min(x_t, na.rm = TRUE)) / 
                      (1 - pnorm(vals$x[l_idx] + min(p, na.rm = TRUE) - min(x_t, na.rm = TRUE))))
      vals$y[l_idx] <- 
        unname((logits - fit$coef[1]) / fit$coef[2])
    }
    if (any(h_idx)) {
      logits <- log(pnorm(vals$x[h_idx] + max(p, na.rm = TRUE) - max(x_t, na.rm = TRUE)) / 
                      (1 - pnorm(vals$x[h_idx] + max(p, na.rm = TRUE) - max(x_t, na.rm = TRUE))))
      vals$y[h_idx] <- 
        unname((logits - fit$coef[1]) / fit$coef[2])
    }
  }
  
  vals$y
}

## interpolation only
inv_orderNorm_trans2 <- function(orderNorm_obj, new_points_x_t, warn) {
  x_t <- orderNorm_obj$x.t
  old_points <- orderNorm_obj$x
  vals <- suppressWarnings(
    approx(x_t, old_points, xout = new_points_x_t, rule = 1)
  )
  
  # If predictions have been made outside observed domain
  if (any(is.na(vals$y))) {
    if(warn) warning('Transformations requested outside observed domain; logit approx. on ranks applied')
    
    fit <- orderNorm_obj$fit
    p <- qnorm(fitted(fit, type = "response"))
    l_idx <- vals$x < min(x_t, na.rm = TRUE)
    h_idx <- vals$x > max(x_t, na.rm = TRUE)
    
    # Check 
    if (any(l_idx)) {
      # Solve algebraically from original transformation
      logits <- log(pnorm(vals$x[l_idx] + min(p, na.rm = TRUE) - min(x_t, na.rm = TRUE)) / 
                      (1 - pnorm(vals$x[l_idx] + min(p, na.rm = TRUE) - min(x_t, na.rm = TRUE))))
      vals$y[l_idx] <- 
        unname((logits - fit$coef[1]) / fit$coef[2])
    }
    if (any(h_idx)) {
      logits <- log(pnorm(vals$x[h_idx] + max(p, na.rm = TRUE) - max(x_t, na.rm = TRUE)) / 
                      (1 - pnorm(vals$x[h_idx] + max(p, na.rm = TRUE) - max(x_t, na.rm = TRUE))))
      vals$y[h_idx] <- 
        unname((logits - fit$coef[1]) / fit$coef[2])
    }
  }
  
  vals$y
}

Tform <- function(mydf, varnames = c("egfr", "hba1c"), probs =  seq(0, 1, 0.001), 
                  thinRDP = TRUE, maxpts = 20, eps = 0.05, increment = 0.05, maxeps = 1,
                  ...) {
  if (any( paste0(varnames, "_t") %in% names(mydf))) warning("Will overwrite existing transformation")
  ## Performs transformation and recovery from quantiles, and plots diagnostics for adequacy of this approach
  for (varname in varnames) {
    print(paste0("Transforming ", varname))
    ## perform transformation and add to dataframe
    res <- orderNorm(x = mydf[[varname]])
    mydf[[paste0(varname, "_t")]] <- res$x.t
    ## get quantiles
    quants_full <- data.frame(
      probs = probs,
      orig_q  =  quantile(res$x,   probs = probs, na.rm = TRUE),
      tform_q  = quantile(res$x.t, probs = probs, na.rm = TRUE))
    ## Apply RDP function to reduce the number of points
    print(thinRDP)
    a <- quants_full
    if (thinRDP) {
      pts <- nrow(a)
      mye <- eps
      while (pts > maxpts) {
        a <- RDP::RamerDouglasPeucker(quants_full$orig_q, quants_full$tform_q, epsilon = mye)
        a <- as.data.frame(a)
        names(a) <- c("orig_q", "tform_q")
        a$epsilon <- mye
        pts <- nrow(a)
        print(pts)
        print(mye)
        mye <- mye + increment
        if (mye >= maxeps) break
      }
      quants <- a  
    } else  quants <- quants_full
    
    ## store quantiles in tibble (note same for every row)
    mydf[[paste0(varname, "_q")]] <- vector(mode = "list", length = nrow(mydf))
    mydf[[paste0(varname, "_q")]] <- lapply(mydf[[paste0(varname, "_q")]], function(x) quants)
    
    ## recover original vector from quantiles and transformed vector
    mydf[[paste0(varname, "_r")]] <- approx(quants[ , "tform_q"], quants[, "orig_q"], mydf[[paste0(varname, "_t")]], na.rm = FALSE)$y
    
    ## diagnostic plots
    par(mfrow = c(1,2))
    plot(quants_full[ , c("orig_q", "tform_q")], main = "Orig and tform \n(blue = selected)", 
         xlab = "Original data",
         ylab = "Transformed data",
         pch = 20,
         cex = 0.5)
    lines(quants[ , c("orig_q", "tform_q")], col = "red")
    points(quants[ , c("orig_q", "tform_q")], col = "blue", pch = 22)
    plot(mydf[sample(1:nrow(mydf), min(200, nrow(mydf))),
              paste0(varname, c("", "_r"))], main = "Orig and recovered \n random sample")
  }
  mydf
}



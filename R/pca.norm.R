##' Bin counts are normalized by regressing out the effect of the first Principal
##' Components. Beforehands, the average coverage is normalized. Then PC are computed
##' using \code{prcomp} function and regressed out using linear regression.
##' @title PCA-based normalization of bin counts
##' @param bc.df a data.frame with 'chr', 'start', 'end' columns and then one column per sample with its bin counts.
##' @param nb.pcs the number of Principal Components to include in the regression model.
##' @param nb.cores the number of cores to use. Default is 1.
##' @param norm.stats.comp Should some statistics on the normalized bin count be computed (mean, sd, outliers). Default is TRUE.
##' @return a list with
##' \item{norm.stats}{a data.frame witht some metrics about the normalization of each
##' bin (row) : coverage average and standard deviation; number of outlier reference samples; principal components}
##' \item{bc.norm}{a data.frame, similar to the input 'bc.df', with the normalized bin counts.}
##' @author Jean Monlong
##' @export
pca.norm <- function(bc.df, nb.pcs = 3, nb.cores = 1, norm.stats.comp = TRUE) {

  all.samples = setdiff(colnames(bc.df), c("chr", "start", "end"))
  rownames(bc.df) = bins = paste(bc.df$chr, as.integer(bc.df$start), as.integer(bc.df$end),sep = "-")

  bc.norm = createEmptyDF(c("character", rep("integer", 2), rep("numeric", length(all.samples))),
    length(bins))
  colnames(bc.norm) = c("chr", "start", "end", all.samples)
  bc.norm$chr = bc.df$chr
  bc.norm$start = bc.df$start
  bc.norm$end = bc.df$end

  bc = as.matrix(bc.df[, all.samples])
  bc.cov = as.numeric(parallel::mclapply(1:ncol(bc), function(cc) stats::median(bc[, cc],
    na.rm = TRUE), mc.cores = nb.cores))
  bc = (bc * stats::median(bc.cov)) %*% diag(1/bc.cov)
  if (any(is.na(bc))) {
    bc[is.na(bc)] = 0
  }

  pca.o = stats::prcomp(bc, center=FALSE)
  rot = pca.o$rotation
  rot[,1:nb.pcs] = 0
  bc.norm[, all.samples] = pca.o$x %*% t(rot)

  if (norm.stats.comp) {
    norm.stats = createEmptyDF(c("character", rep("integer", 2), rep("numeric", 3 +
                                                                       nb.pcs)), length(bins))
    colnames(norm.stats) = c("chr", "start", "end", "m", "sd", "nb.remove", paste0("PC",
              1:nb.pcs))
    norm.stats$chr = bc.df$chr
    norm.stats$start = bc.df$start
    norm.stats$end = bc.df$end
    norm.stats[, 4:6] = matrix(as.numeric(unlist(parallel::mclapply(1:nrow(bc.norm),
                function(rr) {
                  rrr = as.numeric(bc.norm[rr, all.samples])
                  return(c(mean(rrr, na.rm=TRUE), stats::sd(rrr, na.rm=TRUE), NA))
                }, mc.cores = nb.cores))), nrow(bc.norm))
    norm.stats[, -(1:6)] = pca.o$x[,1:nb.pcs]
  } else {
    norm.stats = NULL
  }

  return(list(norm.stats = norm.stats, bc.norm = bc.norm))
}

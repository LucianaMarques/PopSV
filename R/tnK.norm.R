##' Bin count targeted normalization using K-mean clustering to group bins with similar coverage profile across the samples. For outlier bins, i.e. showing unique profile, the set of most similar bins is computed for each bin. Eventually the importance of each sample in the definition of the coverage profile can be weighted using principal components. This normalization is still in development state. It is supposed to be more faster than the full targeted normalization ('tn.norm') and better normalize outlier samples (e.g. if the data is not homogeneous).
##' @title Weighted targeted normalization using K-mean optimization.
##' @param bc.ref a data.frame with the coverage in the reference samples.
##' @param samp the name of the sample to normalize.
##' @param bc.to.norm If non-null and the 'samp' is not in 'bc.ref', this data.frame is used. It should be a single sample coverage data.frame, i.e. with columns exactly: chr, start, end and bc.
##' @param cont.sample the name of the control sample to normalize the coverage to. 
##' @param pca.weights should the samples be weighted using principal components.
##' @param max.size the maximum size of a cluster of bins.
##' @param plot should some graphs be outputed ? Default FALSE.
##' @return a data.frame with the normalized bin counts. columns: chr, start, end, bc.
##' @author Jean Monlong
##' @export
tnK.norm <- function(bc.ref, samp, bc.to.norm = NULL, cont.sample, pca.weights = FALSE, 
    max.size = 1000, plot = FALSE) {
    nb.pcs = 2
    k = 2
    
    if (all(cont.sample != colnames(bc.ref))) {
        stop("'cont.sample' is not in 'bc.ref'")
    }
    
    norm.mat <- function(bc, row.ids, col.id, ref.col.id = 1) {
        col.bc = bc[row.ids, col.id]
        bc.out = col.bc * stats::median(bc[row.ids, ref.col.id])/stats::median(col.bc)
        names(bc.out) = rownames(bc)[row.ids]
        return(bc.out)
    }
    norm.outlier <- function(bc, id.bins, bc.n, bins, samp, cont.sample, nb.support.bins = 500) {
        res.v = sapply(bins, function(bin) {
            d.b = rowSums((bc.n - matrix(bc.n[bin, ], byrow = TRUE, nrow(bc.n), ncol(bc.n)))^2)
            bins.support = names(d.b)[order(d.b)[1:nb.support.bins]]
            samp.bc.n = norm.mat(bc, id.bins[bins.support], colnames(bc) == samp, 
                colnames(bc) == cont.sample)
            return(samp.bc.n[bin])
        })
        names(res.v) = bins
        return(res.v)
    }
    rec.kmeans <- function(mat, k = 2, max.size = 100) {
        km.o = stats::kmeans(mat, k)
        res.l = list()
        for (kid in 1:k) {
            if (km.o$size[kid] > max.size) {
                res.l = c(res.l, rec.kmeans(mat[km.o$cluster == kid, ], k = k, max.size = max.size))
            } else {
                res.l = c(res.l, list(rownames(mat)[km.o$cluster == kid]))
            }
        }
        res.l
    }
    
    bc.rn = with(bc.ref, paste(chr, as.integer(start), as.integer(end), sep = "-"))
    samples = setdiff(colnames(bc.ref), c("chr", "start", "end"))
    bc.out = bc.ref[, c("chr", "start", "end")]
    if (all(samp != colnames(bc.ref)) & !is.null(bc.to.norm)) {
        id.bins = 1:nrow(bc.to.norm)
        names(id.bins) = with(bc.to.norm, paste(chr, as.integer(start), as.integer(end), 
            sep = "-"))
        med.bc = stats::median(apply(bc.ref[, samples], 2, stats::median, na.rm = TRUE))
        med.samp = stats::median(bc.to.norm[, 4], na.rm = TRUE)
        bc.ref = cbind(bc.to.norm[id.bins[bc.rn], 4] * med.bc/med.samp, bc.ref[, 
            samples])
        colnames(bc.ref)[1] = samp
    } else {
        bc.ref = bc.ref[, samples]
    }
    
    bc.ref = as.matrix(bc.ref)
    id.bins = 1:nrow(bc.ref)
    names(id.bins) = row.names(bc.ref) = bc.rn
    samples = colnames(bc.ref)
    
    ## PCA
    if (pca.weights) {
        bc.rand = bc.ref[sample.int(nrow(bc.ref), min(10000, nrow(bc.ref))), ]
        pca.o = stats::prcomp(t(bc.rand[apply(bc.rand, 1, function(ee) all(!is.na(ee))), 
            ]))
        pca.d = stats::dist(t(t(pca.o$x[samples, 1:nb.pcs])))
        w.i = as.matrix(pca.d)[samples == samp, ]
        w.i = 1 - w.i/max(w.i)
    } else {
        w.i = rep(1, length(samples))
    }
    w.i[samples == samp] = 0
    
    ## Transform BC for geometric distance computation
    quant.c = apply(bc.ref, 1, stats::quantile, probs = 0.75)
    bc.n = (bc.ref/quant.c) %*% diag(w.i)
    colnames(bc.n) = samples
    quant.c.non.null = which(quant.c > 0)
    bc.n = bc.n[quant.c.non.null, ]
    
    ## Rec kmeans
    bins.km = rec.kmeans(bc.n, k = k, max.size = max.size)
    if (plot) {
        km.size = unlist(lapply(bins.km, length))
        ggplot2::qplot(km.size) + ggplot2::ylab("number of cluster") + ggplot2::xlab("cluster size") + 
            ggplot2::theme_bw()
    }
    
    ## Normalize
    bc.samp.n = unlist(lapply(bins.km, function(bins) {
        if (length(bins) < max.size * 0.1) {
            return(norm.outlier(bc.ref, id.bins, bc.n, bins, samp, cont.sample))
        } else {
            return(norm.mat(bc.ref, id.bins[bins], which(samples == samp), ref.col.id = which(samples == 
                cont.sample)))
        }
    }))
    
    bc.out$bc = rep(NA, nrow(bc.ref))
    bc.out$bc[id.bins[names(bc.samp.n)]] = bc.samp.n
    return(bc.out)
} 

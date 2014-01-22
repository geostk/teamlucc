#' Scales a layer by power of a given integer and rounds to nearest integer
#'
#' Useful for scaling a layer and rounding to integer so that a layer can be 
#' saved as 'INT2' or 'INT2S'.
#'
#' @export
#' @docType methods
#' @rdname scale_raster-methods
#' @param x a \code{Raster*} object
#' @param power_of raster will be scaled using the highest possible power of 
#' this number
#' @param max_out the scaling factors will be chosen for each layer to ensure 
#' that the maximum and minimum (if minimum is negative) values of each layer 
#' do not exceed \code{max_out}
#' @param do_scaling perform the scaling and return a \code{Raster*} (if 
#' \code{do_scaling} is TRUE) or return a list of scale factors (if 
#' \code{do_scaling} is FALSE)
#' @param round_output whether to round the output to the nearest integer
#' @return a \code{Raster*} if \code{do_scaling} is TRUE, or a list of scaling 
#' factors if \code{do_scaling} is false.
setGeneric("scale_raster", function(x, power_of=10, max_out=32767, 
                                    round_output=TRUE, do_scaling=TRUE) {
    standardGeneric("scale_raster")
})

scale_layer <- function(x, power_of, max_out, round_output, do_scaling) {
    if (!x@data@haveminmax) {
        warning('no stored minimum and maximum values - running setMinMax')
        x <- setMinMax(x)
    }
    layer_max <- max(abs(c(minValue(x), maxValue(x))))
    scale_factor <- power_of ^ floor(log(max_out / layer_max, base=power_of))
    if (do_scaling) {
        x <- calc(x, function(vals, ...) {
                  vals <- vals * scale_factor
                  if (round_output) vals <- round(vals)
                  vals
                  })
        return(x)
    } else {
        return(scale_factor)
    }
}

#' @rdname scale_raster-methods
#' @aliases scale_raster,RasterLayer,ANY-method
setMethod("scale_raster", signature(x="RasterLayer"),
    function(x, power_of, max_out, round_output, do_scaling) {
        ret <- scale_layer(x, power_of, max_out, round_output, do_scaling)
        names(ret) <- names(x)
        return(ret)
    }
)

scale_stack_or_brick <- function(x, power_of, max_out, round_output, do_scaling) {
    cl <- options('rasterClusterObject')[[1]]
    if (is.null(cl) || (nlayers(x) == 1)) {
        inparallel <- FALSE
    } else if (!require(foreach)) {
        warning('Cluster object found, but "foreach" is required to run scaling in parallel. Running sequentially.')
        inparallel <- FALSE
    } else if (!require(doSNOW)) {
        warning('Cluster object found, but "doSNOW" is required to run scaling in parallel. Running sequentially.')
        inparallel <- FALSE
    } else {
        inparallel <- TRUE
    }

    if (inparallel) {
        registerDoSNOW(cl)
        unscaled_layer=NULL
        if (do_scaling) {
            scale_outputs <- foreach(unscaled_layer=unstack(x), .combine='addLayer', 
                                .multicombine=TRUE, .init=raster(), 
                                .packages=c('raster', 'rgdal', 'teamr'),
                                .export=c('scale_layer')) %dopar% {
                scale_output <- scale_layer(unscaled_layer, power_of, max_out, 
                                            round_output, do_scaling)
            }
        } else {
            scale_factors <- foreach(unscaled_layer=unstack(x), 
                                .multicombine=TRUE, .init=raster(), 
                                .packages=c('raster', 'rgdal', 'teamr'),
                                .export=c('scale_layer')) %dopar% {
                scale_factor <- scale_layer(unscaled_layer, power_of, max_out, 
                                            round_output, do_scaling)
            }
        }
    } else {
        scale_outputs <- c()
        for (layer_num in 1:nlayers(x)) {
            unscaled_layer <- raster(x, layer=layer_num)
            scale_output <- scale_layer(unscaled_layer, power_of, max_out, 
                                        round_output, do_scaling)
            scale_outputs <- c(scale_outputs, list(scale_output))
        }
        if (do_scaling) {
            scale_outputs <- stack(scale_outputs)
        }
    }
    names(scale_outputs) <- names(x)
    return(scale_outputs)
}

#' @rdname scale_raster-methods
#' @aliases scale_raster,RasterStack,ANY-method
setMethod("scale_raster", signature(x="RasterStack"),
    function(x, power_of, max_out, round_output, do_scaling) {
        ret <- scale_stack_or_brick(x, power_of, max_out, round_output, 
                                    do_scaling)
        return(ret)
    }
)

#' @rdname scale_raster-methods
#' @aliases scale_raster,RasterBrick,ANY-method
setMethod("scale_raster", signature(x="RasterBrick"),
    function(x, power_of, max_out, round_output, do_scaling) {
        ret <- scale_stack_or_brick(x, power_of, max_out, round_output, 
                                    do_scaling)
        return(ret)
    }
)
##' ## Wieling test case

##+ opts,echo=FALSE
batchfn <- "wieling_batch1.RData"
if (require(knitr)) opts_chunk$set(tidy=FALSE)

##' (This R code can be run via `R CMD BATCH` or alternately via knitr::spin
##'  to create nicely formatted output.  Rather than use knitr's caching
##'  mechanism we explicitly create a `r batchfn` file, so
##'  delete this file if you want to update the output ...)

##+ pkgs,message=FALSE,warning=FALSE
pkgs <- c("lme4","optimx","lme4.0","nloptr")
invisible(lapply(pkgs,library,character.only=TRUE))
print(sapply(pkgs,function(x) as.character(packageVersion(x))),quote=FALSE)

##' Wrapper to make `nloptwrap` look the way `glmer` wants it to
##+ nloptwrapper
nloptwrap2 <- function(fn,par,lower,upper,control=list(),...) {
    ## use DMB's suggested setting of xtol_rel=1e-6
    if (is.null(control$xtol_rel)) control$xtol_rel <- 1e-6
    if (is.null(control$maxeval)) control$maxeval <- 1e5
    res <- nloptr(x0=par,eval_f=fn,lb=lower,ub=upper,opts=control,...)
    with(res,list(par=solution,
                  fval=objective,
                  feval=iterations,
                  conv=if (status>0) 0 else status,
                  message=message))
}

##+ getData,cache=TRUE
( load("dialectNL.rda") ) # "dialectNL
## str(dialectNL)

## Find more factors: which are integer or half-integer?
which(isI <- sapply(dialectNL, function(x) !is.factor(x) &&
                    isTRUE(all.equal(2 * x, round(2 * x), tol=1e-12))))
##' Five of them (this one has quite interesting values ...)
##+ speakerIsMale
with(dialectNL, table(SpeakerIsMale))

dialectNL[isI] <- lapply(dialectNL[isI], as.factor)
str(dialectNL)

fullForm <- PronDistStdDutch.c ~ Geo + PopSize.log_residGeo.z +
    PopAvgAge_residPopAvgIncome.log_Geo.z +
    PopAvgIncome.log_residGeo.z + WordFreq.log.z +
    WordIsNounOrAdverb + WordVCratio.log.z +
    (1 | Word) +
    (0 + PopSize.log_residGeo.z + PopAvgAge_residPopAvgIncome.log_Geo.z + PopAvgIncome.log_residGeo.z | Word) +
    (1 + WordFreq.log.z + WordIsNounOrAdverb | Location) +
    (1 | Transcriber)

sampfrac <- 0.01
ntot <- nrow(dialectNL)
set.seed(101)
## random subset of 1% :
subdat <- dialectNL[sample(round(sampfrac*ntot)),]

fitLme4.0 <- function(data=subdat) {
    tval <- system.time(fit <- lme4.0::lmer(fullForm, data=data))
    list(time=tval, fit=fit)
}

fitLme4 <- function(optCtrl=list(), optimizer, data=subdat) {
    tval <- system.time(fit <- lme4::lmer(fullForm,data=data,
          control=lmerControl(optimizer=optimizer, optCtrl=optCtrl)))
    list(time=tval, fit=fit)
}

## use this rather than the nloptwrap2 control above so that
## the control settings are recorded in the fitted object ...
nlopt <- function(algorithm,xtol_rel=1e-6,maxeval=1e5) {
    list(algorithm=algorithm,xtol_rel=xtol_rel,maxeval=maxeval)
}
argList <-
    list(
        nm1=list(optimizer="Nelder_Mead"),
        nm2=list(optimizer="Nelder_Mead",optCtrl=list(maxfun=1e5)),
        bobyqa1=list(optimizer="bobyqa"),
        nlminb=list(optimizer="optimx",optCtrl=list(method="nlminb")),
        lbfgsb=list(optimizer="optimx",optCtrl=list(method="L-BFGS-B")),
        ## nloptr derivative-free choices
        nloptbobyqa=list(optimizer="nloptwrap2",
            optCtrl=nlopt("NLOPT_LN_BOBYQA")),
        nloptcobyla=list(optimizer="nloptwrap2",
            optCtrl=nlopt("NLOPT_LN_COBYLA")),
        nloptNM=list(optimizer="nloptwrap2",
            optCtrl=nlopt("NLOPT_LN_NELDERMEAD")),
        nloptsubplex=list(optimizer="nloptwrap2",
            optCtrl=nlopt("NLOPT_LN_SBPLX"))
        )

##+ fitAll
if (!file.exists(batchfn)) {
    fitList0 <- fitLme4.0()
    fitList1 <- lapply(argList, do.call, what=fitLme4)
    save("fitList0","fitList1",
         file=batchfn)
}
load(batchfn)

##+ calcOutput,echo=FALSE
fitList <- c(lme4.0 = list(fitList0), fitList1)
tinfo <- function(x) {
    times <- c(x[["time"]][1:3])
    evals <- if (!is(f <- x[["fit"]],"merMod")) NA else f@optinfo$feval
    c(times,nevals=evals)
}
ttab <- t(sapply(fitList,tinfo))
fits <- lapply(fitList, `[[`, "fit")
ff <- sapply(fits, fixef)
REMLcrit <- sapply(fits, deviance)
ff1 <- ff; rownames(ff1) <- abbreviate(rownames(ff))
ff1 <- cbind(REML=REMLcrit, t(ff1))
rownames(ff1) <- colnames(ff)
ff1 <- ff1[order(REMLcrit),]
ttab <- ttab[order(REMLcrit),]

##+ output, echo=FALSE
cat("Timing:\n")
ttab
op <- options(width=120, digits=4)
ff1
options(op)
## see .md or .html files for output ...

##' ### Notes/conclusion
##'
##' * `lme4.0`, and `L-BFGS-B` get similar parameters and log-likelihoods (probably because they're both derivative-based, although `nlminb` is different
##' * most of the `nloptr` optimizers do OK with deviance (although `COBYLA` does relatively poorly), but the parameters are all over the place (very flat surface ...)
##' * `nm2` (built-in Nelder-Mead with `maxfun` extended to 1e5) gets slightly worse logLik and bogus parameters
##' * `nm1` (built-in Nelder-Mead with default `maxfun=1e4`) gets stuck, bad LL and parameters; we get a convergence warning, but I think there's a glitch somewhere because the `@optinfo$conv` flag isn't set??
fits[["nm1"]]@optinfo


##' ### To do
##' * could make caching more flexible (re-run individual models rather than all or nothing)
##' * look at slices to explore the likelihood/deviance surface (will be slooow -- approx 400*7*13 evaluations for good slices)
##' * start scaling up: compare timings 

##+ nlopttest,eval=FALSE
## dd <- update(fits[["nm1"]],devFunOnly=TRUE)  ## FAILS (bad stuff with finding optCtrl in environments ...)
dd <- lme4::lmer(fullForm,data=subdat,devFunOnly=TRUE)
lbound <- lme4:::getME(fits[["nm1"]],"lower")
res <- nloptr(x0=rep(1,14),eval_f=dd,lb=lbound,opts=nlopt("NLOPT_LN_BOBYQA"))

load("wieling_batch2.RData")


#' LBSPR Simulation Model
#'
#' Function that generates the expected equilbrium size composition given biological parameters, and fishing mortality and selectivity pattern.
#'
#' @param LB_pars an object of class \code{'LB_pars'} that contains the life history information
#' @param Control a list of control options for the LBSPR model.
#' @param verbose display messages?
#' @details The Control options are:
#' \describe{
#'  \item{\code{modtype}}{Model Type: either Growth-Type-Group Model (default: "GTG") or Age-Structured ("absel")}
#'  \item{\code{maxsd}}{Maximum number of standard deviations for length-at-age distribution (default is 2)}
#'  \item{\code{ngtg}}{Number of groups for the GTG model. Default is 13}
#'  \item{\code{P}}{Proportion of survival of initial cohort for maximum age for Age-Structured model. Default is 0.01}
#'  \item{\code{Nage}}{Number of pseudo-age classes in the Age Structured model. Default is 101}
#'  \item{\code{maxFM}}{Maximum value for F/M. Estimated values higher than this are trunctated to \code{maxFM}. Default is 4}
#' }
#' @return a object of class \code{'LB_obj'}
#' @author A. Hordyk
#' @useDynLib LBSPR
#' @importFrom Rcpp evalCpp sourceCpp
#'
#' @export
LBSPRsim <- function(LB_pars=NULL, Control=list(), verbose=TRUE) {
  # if (class(LB_pars) != "LB_pars") stop("LB_pars must be of class 'LB_pars'. Use: new('LB_pars')")
  if (length(LB_pars@SPR)>0) {
    if (LB_pars@SPR > 1 | LB_pars@SPR < 0) stop("SPR must be between 0 and 1")
    if (length(LB_pars@FM) >0) message("Both SPR and F/M have been specified. Using SPR and ignoring F/M")
	opt <- optimise(getFMfun, interval=c(0.001, 7), LB_pars, Control=Control)
	LB_pars@FM <- opt$minimum
	temp <- LBSPRsim_(LB_pars, Control=Control, verbose=verbose)
	temp@SPR <- round(temp@SPR,2)
	temp@FM <- round(temp@FM, 2)
	if (temp@SPR != round(LB_pars@SPR,2)) {
	  warning("Not possible to reach specified SPR. SPR may be too low for current selectivity pattern")
	  message("SPR is ", temp@SPR, " instead of ", LB_pars@SPR)
	}
	return(temp)
  } else {
    out <- LBSPRsim_(LB_pars, Control=Control, verbose=verbose)
	out@SPR <- round(out@SPR, 2)
    return(out)
  }
}

#' Internal LBSPR Simulation Model
#'
#' A internal function that generates the expected equilbrium size composition given biological parameters, and fishing mortality and selectivity pattern.  Typically only used by other functions in the package.
#'
#' @param LB_pars an object of class \code{'LB_pars'} that contains the life history information
#' @param Control a list of control options for the LBSPR model.
#' @param verbose display messages?
#' @param doCheck check if the LB_pars object is valid? Switch off when calling function from a optimization routine.
#' @details The Control options are:
#' \describe{
#'  \item{\code{modtype}}{Model Type: either Growth-Type-Group Model (default: "GTG") or Age-Structured ("absel")}
#'  \item{\code{maxsd}}{Maximum number of standard deviations for length-at-age distribution (default is 2)}
#'  \item{\code{ngtg}}{Number of groups for the GTG model. Default is 13}
#'  \item{\code{P}}{Proportion of survival of initial cohort for maximum age for Age-Structured model. Default is 0.01}
#'  \item{\code{Nage}}{Number of pseudo-age classes in the Age Structured model. Default is 101}
#'  \item{\code{maxFM}}{Maximum value for F/M. Estimated values higher than this are trunctated to \code{maxFM}. Default is 4}
#' }
#' @return a object of class \code{'LB_obj'}
#' @author A. Hordyk
#'
#' @export
LBSPRsim_ <- function(LB_pars=NULL, Control=list(), verbose=TRUE, doCheck=TRUE) {
  # if (class(LB_pars) != "LB_pars") stop("LB_pars must be of class 'LB_pars'. Use: new('LB_pars')")

  # Error Checks
  # if (length(LB_pars@Species) < 1) {
    # if (verbose) message("No species name provided - using a default")
	# LB_pars@Species <- "My_Species"
  # }

  if (doCheck) check_LB_pars(LB_pars)
  if (doCheck) if(class(LB_pars) == "LB_pars") validObject(LB_pars)

  # Biological Parameters
  Species <- LB_pars@Species
  Linf <- LB_pars@Linf
  CVLinf <- LB_pars@CVLinf
  SDLinf <- CVLinf * Linf # Standard Deviation of Length-at-Age # Assumed constant CV here
  MK <- LB_pars@MK
  L50 <- LB_pars@L50
  L95 <- LB_pars@L95
  Walpha <- LB_pars@Walpha
  if (is.null(Walpha) | length(Walpha) < 1) {
    if (verbose) message("Walpha not set. Model not sensitive to this parameter - using default")
	LB_pars@Walpha <- Walpha <- 0.001
  }
  Wbeta <- LB_pars@Wbeta
  if (is.null(Wbeta) | length(Wbeta) < 1) {
    if (verbose) message("Wbeta not set. Model not sensitive to this parameter - using default")
	LB_pars@Wbeta <- Wbeta <- 3
  }
  FecB <- LB_pars@FecB
  if (is.null(FecB) | length(FecB) < 1) {
    if (verbose) message("FecB (Fecundity-at-length allometric parameter) not set. Using default - check value")
	LB_pars@FecB <- FecB <- 3
  }
  Steepness <- LB_pars@Steepness
  if (is.null(Steepness) | length(Steepness) < 1) {
      if (verbose) message("Steepness not set. Only used for yield analysis. Not sensitive if per-recruit. Using default of 1 (per-recruit model)")
	LB_pars@Steepness <- Steepness <- 0.99
  }
  if (Steepness <= 0.2 | Steepness >= 1) stop("Steepness must be greater than 0.2 and less than 1.0")

  Mpow <- LB_pars@Mpow
  if (is.null(Mpow) | length(Mpow) < 1) Mpow <- 0
  R0 <- LB_pars@R0
  if (is.null(R0) | length(R0) < 1) R0 <- 1

  # Exploitation Parameters
  SL50 <- LB_pars@SL50
  SL95 <- LB_pars@SL95
  FM <- LB_pars@FM

  # Length Classes
  MaxL <- LB_pars@BinMax
  if (is.null(MaxL) | length(MaxL) < 1) {
    if (verbose) message("BinMax not set. Using default of 1.3 Linf")
	MaxL <- LB_pars@BinMax <- 1.3 * Linf
  }
  MinL <- LB_pars@BinMin
  if (is.null(MinL) | length(MinL) < 1) {
    if (verbose) message("BinMin not set. Using default value of 0")
	MinL <- LB_pars@BinMin <- 0
  }
  BinWidth <- LB_pars@BinWidth
  if (is.null(BinWidth) | length(BinWidth) < 1) {
    if (verbose) message("BinWidth not set. Using default value of 1/20 Linf")
	BinWidth <- LB_pars@BinWidth <- 1/20 * Linf
  }

  LBins <- seq(from=MinL, by=BinWidth, to=MaxL)
  LMids <- seq(from=LBins[1] + 0.5*BinWidth, by=BinWidth, length.out=length(LBins)-1)

  By <- BinWidth
  if (MinL > 0 & (MinL-By) > 0) { # the simulation model must start from 0 size class
	  fstBins <- rev(seq(from=MinL-By, to=0, by=-By))
	  LBins <- c(fstBins, LBins)
	  LMids <- seq(from=LBins[1] + 0.5*BinWidth, by=BinWidth, length.out=length(LBins)-1)
  }
  if (MaxL < Linf) stop(paste0("Maximum length bin (", MaxL, ") can't be smaller than asymptotic size (", Linf ,"). Increase size of maximum length class ['maxL']"))
  # Control Parameters
  con <- list(maxsd=2, modtype=c("GTG","absel"), ngtg=13, P=0.01, Nage=101, 
    maxFM=4, method="BFGS")
  nmsC <- names(con)
  con[(namc <- names(Control))] <- Control
  if (length(noNms <- namc[!namc %in% nmsC]))
        warning("unknown names in Control: ", paste(noNms, collapse = ", "))
  maxsd <- con$maxsd # maximum number of standard deviations from the mean for length-at-age distributions
  if (maxsd < 1) warning("maximum standard deviation is too small. See the help documentation")
  modType <- match.arg(arg=con$modtype, choices=c("GTG", "absel"))

  # Model control parameters
  P <- con$P
  if (P > 0.1 | P < 0.0001) warning("P parameter may be set to high or too low. See the help documentation")
  Nage <- con$Nage
  if (Nage < 90) warning("Nage should be higher. See the help documentation")
  maxFM <- con$maxFM
  ngtg <- con$ngtg
  Yield <- vector()
  
  newngtg <- max(ngtg, ceiling((2*maxsd*SDLinf + 1)/BinWidth))
  if (newngtg != ngtg) {
    if(verbose) message("ngtg increased to ", newngtg, " because of small bin size")
	ngtg <- newngtg  
  }
  
  if (modType == "GTG") {
    # Linfs of the GTGs
    gtgLinfs <- seq(from=Linf-maxsd*SDLinf, to=Linf+maxsd*SDLinf, length=ngtg)
    dLinf <- gtgLinfs[2] - gtgLinfs[1]
    
    # Distribute Recruits across GTGS
    recP <- dnorm(gtgLinfs, Linf, sd=SDLinf) / sum(dnorm(gtgLinfs, Linf, sd=SDLinf))

    Weight <- Walpha * LMids^Wbeta
    # Maturity and Fecundity for each GTG
    L50GTG <- L50/Linf * gtgLinfs # Maturity at same relative size
    L95GTG <- L95/Linf * gtgLinfs # Assumes maturity age-dependant
    DeltaGTG <- L95GTG - L50GTG
    MatLengtg <- sapply(seq_along(gtgLinfs), function (X)
	  1.0/(1+exp(-log(19)*(LMids-L50GTG[X])/DeltaGTG[X])))
    FecLengtg <- MatLengtg * LMids^FecB # Fecundity across GTGs

    # Selectivity - asymptotic only at this stage - by careful with knife-edge
    SelLen <- 1.0/(1+exp(-log(19)*(LBins-(SL50+0.5*By))/ ((SL95+0.5*By)-(SL50+0.5*By))))

    # Life-History Ratios
    MKL <- MK * (Linf/(LBins+0.5*By))^Mpow # M/K ratio for each length class
    # Matrix of MK for each GTG
    MKMat <- matrix(rep(MKL, ngtg), nrow=length(MKL), byrow=FALSE)
    FK <- FM * MK # F/K ratio
    FKL <- FK * SelLen # F/K ratio for each length class
    ZKLMat <- MKMat + FKL # Z/K ratio (total mortality) for each GTG

    # Set Up Empty Matrices
    # number-per-recruit at length
    NPRFished <- NPRUnfished <- matrix(0, nrow=length(LBins), ncol=ngtg)
    NatLUF <- matrix(0, nrow=length(LMids), ncol=ngtg) # N at L unfished
    NatLF <- matrix(0, nrow=length(LMids), ncol=ngtg) # N at L fished
    FecGTG <- matrix(0, nrow=length(LMids), ncol=ngtg) # fecundity of GTG

    # Distribute Recruits into first length class
    NPRFished[1, ] <- NPRUnfished[1, ] <- recP * R0
    for (L in 2:length(LBins)) { # Calc number at each size class
      NPRUnfished[L, ] <- NPRUnfished[L-1, ] * ((gtgLinfs-LBins[L])/(gtgLinfs-LBins[L-1]))^MKMat[L-1, ]
      NPRFished[L, ] <- NPRFished[L-1, ] * ((gtgLinfs-LBins[L])/(gtgLinfs-LBins[L-1]))^ZKLMat[L-1, ]
	  ind <- gtgLinfs  < LBins[L]
	  NPRFished[L, ind] <- 0
	  NPRUnfished[L, ind] <- 0
    }
    NPRUnfished[is.nan(NPRUnfished)] <- 0
    NPRFished[is.nan(NPRFished)] <- 0
    NPRUnfished[NPRUnfished < 0] <- 0
    NPRFished[NPRFished < 0] <- 0

    for (L in 1:length(LMids)) { # integrate over time in each size class
      NatLUF[L, ] <- (NPRUnfished[L,] - NPRUnfished[L+1,])/MKMat[L, ]
      NatLF[L, ] <- (NPRFished[L,] - NPRFished[L+1,])/ZKLMat[L, ]
	  FecGTG[L, ] <- NatLUF[L, ] * FecLengtg[L, ]
    }

    SelLen2 <- 1.0/(1+exp(-log(19)*(LMids-SL50)/(SL95-SL50))) # Selectivity-at-Length
    NatLV <- NatLUF * SelLen2 # Unfished Vul Pop
    NatLC <- NatLF * SelLen2 # Catch Vul Pop


    # Aggregate across GTGs
    Nc <- apply(NatLC, 1, sum)/sum(apply(NatLC, 1, sum))
    VulnUF <- apply(NatLV, 1, sum)/sum(apply(NatLV, 1, sum))
    PopUF <- apply(NatLUF, 1, sum)/sum(apply(NatLUF, 1, sum))
    PopF <- apply(NatLF, 1, sum)/sum(apply(NatLF, 1, sum))

    # Calc SPR
    EPR0 <- sum(NatLUF * FecLengtg) # Eggs-per-recruit Unfished
    EPRf <- sum(NatLF * FecLengtg) # Eggs-per-recruit Fished
    SPR <- EPRf/EPR0

    # Equilibrium Relative Recruitment
    recK <- (4*Steepness)/(1-Steepness) # Goodyear compensation ratio
    reca <- recK/EPR0
    recb <- (reca * EPR0 - 1)/(R0*EPR0)
    RelRec <- max(0, (reca * EPRf-1)/(recb*EPRf))
    if (!is.finite(RelRec)) RelRec <- 0
    # RelRec/R0 - relative recruitment
    YPR <- sum(NatLC  * Weight * SelLen2) * FM
    Yield <- YPR * RelRec

    # Calc Unfished Fitness - not used here
    Fit <- apply(FecGTG, 2, sum, na.rm=TRUE) # Total Fecundity per Group
    FitPR <- Fit/recP # Fitness per-recruit
    FitPR <- FitPR/median(FitPR, na.rm=TRUE)

    # Calculate spawning-per-recruit at each size class
    SPRatsize <- cumsum(rowSums(NatLUF * FecLengtg))
    SPRatsize <- SPRatsize/max(SPRatsize)

    # Simulated length data
    LenOut <- cbind(mids=LMids, n=Nc)
    LenOut <- LenOut[LenOut[,1] >= MinL,]
    LenOut[,2] <- LenOut[,2]/sum(LenOut[,2])
  }
  if (modType == "absel") {
    # LBSPR model with pseudo-age classes
    x <- seq(from=0, to=1, length.out=Nage) # relative age vector
    EL <- (1-P^(x/MK)) * Linf # length at relative age
    rLens <- EL/Linf # relative length
    SDL <- EL * CVLinf # standard deviation of length-at-age
    Nlen <- length(LMids)
    Prob <- matrix(NA, nrow=Nage, ncol=Nlen)
    Prob[,1] <- pnorm((LBins[2] - EL)/SDL, 0, 1) # probablility of length-at-age
    for (i in 2:(Nlen-1)) {
      Prob[,i] <- pnorm((LBins[i+1] - EL)/SDL, 0, 1) -
	  	pnorm((LBins[i] - EL)/SDL, 0, 1)
    }
    Prob[,Nlen] <- 1 - pnorm((LBins[Nlen] - EL)/SDL, 0, 1)

    # Truncate normal dist at MaxSD
    mat <- array(1, dim=dim(Prob))
    for (X in 1:Nage) {
	  ind <- NULL
      if (EL[X] > (0.25 * Linf)) ind <- which(abs((LMids - EL[X]) /SDL[X]) >= maxsd)
      mat[X,ind] <- 0
    }

	Prob <- Prob * mat
	
    SL <- 1/(1+exp(-log(19)*(LMids-SL50)/(SL95-SL50))) # Selectivity at length
    Sx <- apply(t(Prob) * SL, 2, sum) # Selectivity at relative age
    MSX <- cumsum(Sx) / seq_along(Sx) # Mean cumulative selectivity for each age
    Ns <- (1-rLens)^(MK+(MK*FM)*MSX) # number at relative age in population

    Cx <- t(t(Prob) * SL) # Conditional catch length-at-age probablilities
    Nc <- apply(Ns * Cx, 2, sum) #

	PopF <- apply(Ns * Prob, 2, sum)
	PopF <- PopF/sum(PopF)

    Ml <- 1/(1+exp(-log(19)*(LMids-L50)/(L95-L50))) # Maturity at length
    Ma <-  apply(t(Prob) * Ml, 2, sum) # Maturity at relative age

    N0 <- (1-rLens)^MK # Unfished numbers-at-age
    PopUF <- apply(N0 * Prob, 2, sum)
	PopUF <- PopUF/sum(PopUF)
    VulnUF	<- apply(N0 * Cx, 2, sum) #
	VulnUF <- VulnUF/sum(VulnUF)
    SPR <- sum(Ma * Ns * rLens^FecB)/sum(Ma * N0 * rLens^FecB)
    
	# Equilibrium Relative Recruitment
	EPR0 <- sum(Ma * N0 * rLens^FecB)
	EPRf <- sum(Ma * Ns * rLens^FecB)
    recK <- (4*Steepness)/(1-Steepness) # Goodyear compensation ratio
    reca <- recK/EPR0
    recb <- (reca * EPR0 - 1)/(R0*EPR0)
    RelRec <- max(0, (reca * EPRf-1)/(recb*EPRf))
    if (!is.finite(RelRec)) RelRec <- 0
	
    # RelRec/R0 - relative recruitment
    YPR <- sum(Nc  * LMids^FecB ) * FM
    Yield <- YPR * RelRec

	# Simulated length data
    LenOut <- cbind(mids=LMids, n=Nc)
    LenOut <- LenOut[LenOut[,1] >= MinL,]
    LenOut[,2] <- LenOut[,2]/sum(LenOut[,2])
  }

  # if (FM > maxFM) {
    # if (verbose) message("F/M (", round(FM,2), ") greater than max F/M parameter (", maxFM, ")")
	# if (verbose) message("setting F/M to maxFM (see Control in documentation)")
    # FM <- maxFM
  # }
  LBobj <- new("LB_obj", verbose=verbose)
  Slots <- slotNames(LB_pars)
  for (X in 1:length(Slots)) slot(LBobj, Slots[X]) <- slot(LB_pars, Slots[X])
  LBobj@SPR <- SPR
  LBobj@Yield <- Yield
  LBobj@YPR <- YPR
  LBobj@LMids <- LenOut[,1]
  LBobj@pLCatch <- matrix(LenOut[,2])
  LBobj@RelRec <- RelRec
  LBobj@pLPop <- round(array(c(LMids, PopUF, PopF, VulnUF, Nc),
    dim=c(length(PopUF), 5), dimnames=list(NULL, c("LMids", "PopUF", "PopF", "VulnUF", "VulnF")))
	, 6)
  LBobj@maxFM <- maxFM
  LBobj
}

#' Calculate F/M given SPR and other parameters
#'
#' A internal function that optimizes for F/M when SPR is provided in the simulation parameters.
#'
#' @param FM a F/M value
#' @param LB_pars an object of class \code{'LB_pars'} that contains the life history information
#' @param Control a list of control options for the LBSPR model.
#'
#' @details The Control options are:
#' \describe{
#'  \item{\code{modtype}}{Model Type: either Growth-Type-Group Model (default: "GTG") or Age-Structured ("absel")}
#'  \item{\code{maxsd}}{Maximum number of standard deviations for length-at-age distribution (default is 2)}
#'  \item{\code{ngtg}}{Number of groups for the GTG model. Default is 13}
#'  \item{\code{P}}{Proportion of survival of initial cohort for maximum age for Age-Structured model. Default is 0.01}
#'  \item{\code{Nage}}{Number of pseudo-age classes in the Age Structured model. Default is 101}
#'  \item{\code{maxFM}}{Maximum value for F/M. Estimated values higher than this are trunctated to \code{maxFM}. Default is 4}
#' }
#' @return sum of squares value
#' @author A. Hordyk
#'
#' @export
getFMfun <- function(FM, LB_pars, Control=list()) {
  LB_pars@FM <- FM
  (LB_pars@SPR - LBSPRsim_(LB_pars, Control=Control, verbose=FALSE)@SPR)^2
}



#' Fit LBSPR model to length data
#'
#' A function that fits the LBSPR model to length data
#'
#' @param LB_pars an object of class \code{'LB_pars'} that contains the life history information
#' @param LB_lengths an object of class \code{'LB_lengths'} that contains the length data
#' @param yrs index of years to include. If NA the model is run on all years
#' @param Control a list of control options for the LBSPR model.
#' @param pen apply a penalty if estimate of selectivity is very high?
#' @param verbose display messages?
#' @param useCPP use cpp optimization code?
#' @param ... additional parameters to pass to \code{FilterSmooth}
#' @details The Control options are:
#' \describe{
#'  \item{\code{modtype}}{Model Type: either Growth-Type-Group Model (default: "GTG") or Age-Structured ("absel")}
#'  \item{\code{maxsd}}{Maximum number of standard deviations for length-at-age distribution (default is 2)}
#'  \item{\code{ngtg}}{Number of groups for the GTG model. Default is 13}
#'  \item{\code{P}}{Proportion of survival of initial cohort for maximum age for Age-Structured model. Default is 0.01}
#'  \item{\code{Nage}}{Number of pseudo-age classes in the Age Structured model. Default is 101}
#'  \item{\code{maxFM}}{Maximum value for F/M. Estimated values higher than this are trunctated to \code{maxFM}. Default is 4}
#' }
#' @return a object of class \code{'LB_obj'}
#' @author A. Hordyk
#'
#' @importFrom utils flush.console
#' @importFrom methods new slot slot<- slotNames validObject
#' @export
LBSPRfit <- function(LB_pars=NULL, LB_lengths=NULL, yrs=NA, Control=list(), pen=TRUE, verbose=TRUE, useCPP=TRUE, ...) {

  if (class(LB_pars) != "LB_pars") stop("LB_pars must be of class 'LB_pars'. Use: new('LB_pars')")
  if (class(LB_lengths) != "LB_lengths") stop("LB_lengths must be of class 'LB_lengths'. Use: new('LB_lengths')")

  # Error Checks
  # if (length(LB_pars@Species) < 1) {
    # if (verbose) message("No species name provided - using a default")
	# LB_pars@Species <- "My_Species"
  # }
  if (length(LB_pars@SL50) == 0) LB_pars@SL50 <- 1
  if (length(LB_pars@SL95) == 0) LB_pars@SL95 <- 2
  if (length(LB_pars@FM) == 0) LB_pars@FM <- 1

  check_LB_pars(LB_pars)
  validObject(LB_pars)

  if (class(LB_lengths@Years) != "numeric" & class(LB_lengths@Years) != "integer") {
    warning("Years must be numeric values")
	message("Attempting to convert to numeric values")
	options(warn=-1)
	LB_lengths@Years <-  gsub("X", "", LB_lengths@Years)
	LB_lengths@Years <- as.numeric(LB_lengths@Years)
	options(warn=1)
    if (all(is.na(LB_lengths@Years))) LB_lengths@Years <- 1:length(LB_lengths@Years)
  }


  if (all(is.na(yrs))) { # run model on all years
    nyrs <- ncol(LB_lengths@LData)
    yearNames <- LB_lengths@Years
    if (is.null(yearNames)) yearNames <- 1:nyrs
	cols <- 1:nyrs
  } else { # run model on some years
    if (class(yrs) != "numeric" & class(yrs) != "integer")
	  stop("yrs must numeric value indicating column(s), or NA for all")
    nyrs <- length(yrs)
    yearNames <- LB_lengths@Years[yrs]
    if (is.null(yearNames)) yearNames <- yrs
	cols <- yrs
  }
  if (verbose) message("Fitting model")
  if (verbose) message("Year:")
  flush.console()
  runMods <- sapply(cols, function (X)
	LBSPRfit_(yr=X, LB_pars=LB_pars, LB_lengths=LB_lengths, Control=Control,  
	  pen=pen, useCPP=useCPP, verbose=verbose))

  LBobj <- new("LB_obj")
  Slots <- slotNames(LB_pars)
  for (X in 1:length(Slots)) slot(LBobj, Slots[X]) <- slot(LB_pars, Slots[X])
  Slots <- slotNames(LB_lengths)
  for (X in 1:length(Slots)) slot(LBobj, Slots[X]) <- slot(LB_lengths, Slots[X])

  LBobj@NYears <- nyrs
  LBobj@Years <- yearNames
  LBobj@LData <- LB_lengths@LData[,cols, drop=FALSE]
  LBobj@NLL <- unlist(lapply(runMods, slot, "NLL"))
  LBobj@SL50 <- round(unlist(lapply(runMods, slot, "SL50")),2)
  LBobj@SL95 <- round(unlist(lapply(runMods, slot, "SL95")),2)
  LBobj@FM <- round(unlist(lapply(runMods, slot, "FM")),2)
  LBobj@SPR <- unlist(lapply(runMods, slot, "SPR"))
  LBobj@Yield <- round(unlist(lapply(runMods, slot, "Yield")),2)
  LBobj@YPR <- round(unlist(lapply(runMods, slot, "YPR")),2)
  LBobj@fitLog <- unlist(lapply(runMods, slot, "fitLog"))
  LBobj@Vars <-  matrix(unlist(lapply(runMods, slot, "Vars")), ncol=4, byrow=TRUE)
  colnames(LBobj@Vars) <- c("SL50", "SL95", "FM", "SPR")
  LBobj@pLCatch <- do.call(cbind, lapply(runMods, slot, "pLCatch"))
  LBobj@maxFM <- unlist(lapply(runMods, slot, "maxFM"))[1]
 
  DF <- data.frame(SL50=LBobj@SL50, SL95=LBobj@SL95, FM=LBobj@FM, SPR=LBobj@SPR)
  if (nrow(DF) == 1) LBobj@Ests <- as.matrix(DF)
  if (nrow(DF) > 1) LBobj@Ests <- apply(DF, 2, FilterSmooth, ...)
  LBobj@Ests <- round(LBobj@Ests, 2)

  LBobj
}


#' Kalman filter and Rauch-Tung-Striebel smoother
#'
#' A function that applies a filter and smoother to estimates
#'
#' @param RawEsts a vector of estimated values
#' @param R variance of sampling noise
#' @param Q variance of random walk increments
#' @param Int covariance of initial uncertainty
#' @return a vector of smoothed values
#' @author A. Hordyk
#'
#' @export
FilterSmooth <- function(RawEsts, R=1, Q=0.1, Int=100) {
  # Kalman smoother and Rauch-Tung-Striebel smoother on random walk estimation
  #http://read.pudn.com/downloads88/ebook/336360/Kalman%20Filtering%20Theory%20and%20Practice,%20Using%20MATLAB/CHAPTER4/RTSvsKF.m__.htm
  # R  # Variance of sampling noise
  # Q  # Variance of random walk increments
  # Int # Covariance of initial uncertainty
  Ppred <-  rep(Int, length(RawEsts))
  nNA <- sum(is.na(RawEsts))
  while(nNA > 0) { # NAs get replaced with last non-NA
    RawEsts[is.na(RawEsts)] <- RawEsts[which(is.na(RawEsts))-1]
    nNA <- sum(is.na(RawEsts))
  }

  Pcorr <- xcorr <- xpred <- rep(0, length(RawEsts))
  # Kalman Filter
  for (X in 1:length(Ppred)) {
    if (X !=1) {
	  Ppred[X] <- Pcorr[X-1] + Q
	  xpred[X] <- xcorr[X-1]
	}
	W <- Ppred[X]/(Ppred[X] + R)
	xcorr[X] <- xpred[X] + W * (RawEsts[X] - xpred[X]) # Kalman filter estimate
	Pcorr[X] <- Ppred[X] - W * Ppred[X]
  }
  # Smoother
  xsmooth <- xcorr
  for (X in (length(Pcorr)-1):1) {
    A <- Pcorr[X]/Ppred[X+1]
	xsmooth[X] <- xsmooth[X] + A*(xsmooth[X+1] - xpred[X+1])
  }
  return(xsmooth)

}

#' Internal function to fit LBSPR model to length data
#'
#' An internal function that fits the LBSPR model to a single year of length data
#'
#' @param yr index of the year column to fit model to
#' @param LB_pars an object of class \code{'LB_pars'} that contains the life history information
#' @param LB_lengths an object of class \code{'LB_lengths'} that contains the length data
#' @param Control a list of control options for the LBSPR model.
#' @param pen apply a penalty if estimate of selectivity is very high?
#' @param useCPP use cpp optimization code?
#' @param verbose display messages?
#' @details The Control options are:
#' \describe{
#'  \item{\code{modtype}}{Model Type: either Growth-Type-Group Model (default: "GTG") or Age-Structured ("absel")}
#'  \item{\code{maxsd}}{Maximum number of standard deviations for length-at-age distribution (default is 2)}
#'  \item{\code{ngtg}}{Number of groups for the GTG model. Default is 13}
#'  \item{\code{P}}{Proportion of survival of initial cohort for maximum age for Age-Structured model. Default is 0.01}
#'  \item{\code{Nage}}{Number of pseudo-age classes in the Age Structured model. Default is 101}
#'  \item{\code{maxFM}}{Maximum value for F/M. Estimated values higher than this are trunctated to \code{maxFM}. Default is 4}
#' }
#' @return a object of class \code{'LB_obj'}
#' @author A. Hordyk
#'
#' @importFrom stats dbeta dnorm median nlminb optimise pnorm optim runif
#' @export
LBSPRfit_ <- function(yr=1, LB_pars=NULL, LB_lengths=NULL, Control=list(), 
  pen=TRUE, useCPP=TRUE, verbose=TRUE) {
  if (verbose) message(yr)
  flush.console()

  if (class(LB_pars) != "LB_pars") stop("LB_pars must be of class 'LB_pars'. Use: new('LB_pars')")
  if (class(LB_lengths) != "LB_lengths") stop("LB_lengths must be of class 'LB_lengths'. Use: new('LB_lengths')")
  if (yr > LB_lengths@NYears) stop("yr greater than LBSPR_obj@NYears")

  SingYear <- LB_lengths
  SingYear@LData <- as.matrix(SingYear@LData[,yr])
  SingYear@Years <- LB_lengths@Years[yr]
  SingYear@NYears <- 1
  ldat <- SingYear@LData
  LMids <- SingYear@LMids

  LB_pars@BinWidth <- LMids[2] - LMids[1]
  LB_pars@BinMin <- LMids[1] - 0.5 * LB_pars@BinWidth
  LB_pars@BinMax <- LMids[length(LMids)] + 0.5 * LB_pars@BinWidth

  # Control Parameters
  con <- list(maxsd=2, modtype=c("GTG","absel"), ngtg=13, P=0.01, Nage=101, 
    maxFM=4, method="BFGS")
  nmsC <- names(con)
  con[(namc <- names(Control))] <- Control
  if (length(noNms <- namc[!namc %in% nmsC])) {
    warning("unknown names in Control: ", paste(noNms, collapse = ", "))
	cat("Options are: ", paste(names(con), collapse = ", "), "\n")
  }
  maxsd <- con$maxsd # maximum number of standard deviations from the mean for length-at-age distributions
  if (maxsd < 1) warning("maximum standard deviation is too small. See the help documentation")
  modType <- match.arg(arg=con$modtype, choices=c("GTG", "absel"))
  ngtg <- con$ngtg
  # Starts
  sSL50 <- LMids[which.max(ldat)]/LB_pars@Linf # Starting guesses
  sDel <- 0.2 * LMids[which.max(ldat)]/LB_pars@Linf
  sFM <- 0.5
  Start <- log(c(sSL50, sDel, sFM))

  if (useCPP & modType=="GTG") { # use cpp code
    By <- SingYear@LMids[2] - SingYear@LMids[1]
	LMids <- SingYear@LMids
    LBins <- seq(from=LMids[1]-0.5*By, by=By, length.out=length(SingYear@LMids)+1)
	LDat <- SingYear@LData
	if (LBins[1] !=0 & (LBins[1] -By) > 0) {
	  fstBins <- seq(from=0, by=By, to=LBins[1]-By)
	  fstMids <- seq(from=0.5*By, by=By, to=LMids[1]-By)
	  ZeroDat <- rep(0, length(fstMids))
	  LMids <- c(fstMids, LMids)
	  LBins <- c(fstBins, LBins)
	  LDat <- c(ZeroDat, LDat)
	}
    SDLinf <- LB_pars@CVLinf * LB_pars@Linf
	gtgLinfs <- seq(from= LB_pars@Linf-maxsd*SDLinf, to= LB_pars@Linf+maxsd*SDLinf, length=ngtg)
	MKMat <- matrix(LB_pars@MK, nrow=length(LBins), ncol=ngtg)
	recP <- dnorm(gtgLinfs, LB_pars@Linf, sd=SDLinf) / sum(dnorm(gtgLinfs, LB_pars@Linf, sd=SDLinf))
    usePen <- 1
	if (!pen) usePen <- 0
	opt <- try(optim(Start, LBSPR_NLLgtg, LMids=LMids, LBins=LBins, LDat=LDat,
	  gtgLinfs=gtgLinfs, MKMat=MKMat,  MK=LB_pars@MK, Linf=LB_pars@Linf,
	  ngtg=ngtg, recP=recP,usePen=usePen, hessian=TRUE, method=Control$method), 
	  silent=TRUE)
	varcov <- try(solve(opt$hessian), silent=TRUE)
	if (class(varcov) == "try-error") class(opt) <- "try-error"
	if (class(varcov) != "try-error" && any(diag(varcov) < 0)) 
	  class(opt) <- "try-error"
	count <- 0 
	countmax <- 10
	quants <- seq(from=0, to=0.95, length.out=countmax)
	while (class(opt) == "try-error" & count < countmax) { # optim crashed - try different starts 
      count <- count + 1 
	  sSL50 <- quantile(c(LMids[min(which(ldat>0))]/LB_pars@Linf, 
	    LMids[which.max(ldat)]/LB_pars@Linf), probs=quants)[count]
	  sSL50 <- as.numeric(sSL50)
	  Start <- log(c(sSL50, sDel, sFM))	
      opt <- try(optim(Start, LBSPR_NLLgtg, LMids=LMids, LBins=LBins, LDat=LDat,
	    gtgLinfs=gtgLinfs, MKMat=MKMat,  MK=LB_pars@MK, Linf=LB_pars@Linf,
	    ngtg=ngtg, recP=recP,usePen=usePen, hessian=TRUE, method=Control$method),
		silent=TRUE)	
	  varcov <- try(solve(opt$hessian), silent=TRUE) 
	  if (class(varcov) == "try-error") class(opt) <- "try-error"
	  if (class(varcov) != "try-error" && any(diag(varcov) < 0)) 
	    class(opt) <- "try-error"
	}	

	if (class(opt) == "try-error") { # optim crashed - try without hessian  
      opt <- try(optim(Start, LBSPR_NLLgtg, LMids=LMids, LBins=LBins, LDat=LDat,
	    gtgLinfs=gtgLinfs, MKMat=MKMat,  MK=LB_pars@MK, Linf=LB_pars@Linf,
	    ngtg=ngtg, recP=recP,usePen=usePen, hessian=FALSE, method=Control$method))	
	  varcov <- matrix(NA, 3,3) 
	}  
	NLL <- opt$value
  } else {
    # opt <- nlminb(Start, LBSPRopt, LB_pars=LB_pars, LB_lengths=SingYear, 
	# Control=Control, pen=pen, control=list(iter.max=300, eval.max=400, 
	# abs.tol=1E-20))
	# NLL <- opt$objective
	opt <- optim(Start, LBSPRopt, LB_pars=LB_pars, LB_lengths=SingYear, 
	Control=Control, pen=pen, hessian=TRUE, method=Control$method)
	varcov <- solve(opt$hessian)
	NLL <- opt$value
  }
  LB_pars@SL50 <- exp(opt$par)[1] * LB_pars@Linf
  LB_pars@SL95 <- LB_pars@SL50 + (exp(opt$par)[2] * LB_pars@Linf)
  LB_pars@FM <- exp(opt$par)[3]

  # Estimate variance of derived parameters using delta method 
  MLEs <- opt$par 
  vSL50 <- (exp(opt$par[1]) * LB_pars@Linf)^2 * varcov[1,1]
  vSL95 <- (LB_pars@Linf * exp(MLEs[2]))^2 * varcov[2,2] + 
             (LB_pars@Linf * exp(MLEs[1]))^2 * varcov[1,1] +
              LB_pars@Linf * exp(MLEs[2]) * LB_pars@Linf * exp(MLEs[1]) * 
			  varcov[1,2]
  vFM <- exp(opt$par[3])^2 * varcov[3,3]
  vSPR <- varSPR(opt$par, varcov, LB_pars)
  elog <- 0
  # Error Logs 
  if (all(is.na(varcov)) | any(diag(varcov) < 0)) {
    warning("The final Hessian is not positive definite. Estimates may be unreliable")
	flush.console()
	elog <- 1 # 
  }
  if (LB_pars@SL50/LB_pars@Linf > 0.85) elog <- 2
  if (LB_pars@FM > 5) elog <- 3
  if (LB_pars@SL50/LB_pars@Linf > 0.85 & LB_pars@FM > 5) elog <- 4
  
  runMod <- LBSPRsim_(LB_pars, Control=Control, verbose=FALSE, doCheck=FALSE)

  LBobj <- new("LB_obj")
  Slots <- slotNames(LB_pars)
  for (X in 1:length(Slots)) slot(LBobj, Slots[X]) <- slot(LB_pars, Slots[X])
  Slots <- slotNames(SingYear)
  for (X in 1:length(Slots)) slot(LBobj, Slots[X]) <- slot(SingYear, Slots[X])
  

  LBobj@Vars <- matrix(c(vSL50, vSL95, vFM, vSPR), ncol=4)
  LBobj@pLCatch <- runMod@pLCatch
  LBobj@NLL <- NLL
  LBobj@SPR <- runMod@SPR
  LBobj@Yield <- runMod@Yield
  LBobj@YPR <- runMod@YPR
  LBobj@maxFM <- runMod@maxFM
  LBobj@fitLog <- elog
  LBobj

}


varSPR <- function(MLEs, varcov, LB_pars) {
  var <- diag(varcov)
  vars <- c("lSL50", "ldL", "lFM")
  p1 <- 0
  for (i in seq_along(MLEs)) p1 <- p1 + derivative(dSPR, x=MLEs[i], var=vars[i], 
    LB_pars=LB_pars)^2 * var[i]

  p2 <- derivative(dSPR, x=MLEs[1], var=vars[1],  LB_pars=LB_pars) * 
    derivative(dSPR, x=MLEs[2], var=vars[2],  LB_pars=LB_pars) * varcov[1,2]
  
  p3 <- derivative(dSPR, x=MLEs[1], var=vars[1],  LB_pars=LB_pars) * 
    derivative(dSPR, x=MLEs[3], var=vars[3],  LB_pars=LB_pars) * varcov[1,3]
  
  p4 <- derivative(dSPR, x=MLEs[3], var=vars[3],  LB_pars=LB_pars) * 
    derivative(dSPR, x=MLEs[2], var=vars[2],  LB_pars=LB_pars) * varcov[3,2]
  p1 + p2 + p3 + p4   
}

dSPR <- function(x, LB_pars, var=c("lSL50", "ldL", "lFM"),Control=NULL) {
  lvar <- match.arg(var)
  ex <- exp(x)
  if (lvar == "lFM") myslot <- "FM" 
  if (lvar == "lSL50") {
    myslot <- "SL50"
	ex <- ex * LB_pars@Linf
  }
  if (lvar == "ldL") {
    myslot <- "SL95"
	ex <-  ex * LB_pars@Linf + LB_pars@L50
  }
  slot(LB_pars, myslot) <- ex 
  temp <- LBSPRsim_(LB_pars, Control=Control, verbose=FALSE, doCheck=FALSE)
  temp@SPR
}

# From http://blog.quantitations.com/tutorial/2013/02/12/numerical-derivatives-in-r/
derivative <- function(f, x, ..., order = 1, delta = 0.01, sig = 6) {
    # Numerically computes the specified order derivative of f at x
    vals <- matrix(NA, nrow = order + 1, ncol = order + 1)
    grid <- seq(x - delta/2, x + delta/2, length.out = order + 1)
    vals[1, ] <- sapply(grid, f, ...) - f(x, ...)
    for (i in 2:(order + 1)) {
        for (j in 1:(order - i + 2)) {
            stepsize <- grid[i + j - 1] - grid[i + j - 2]
            vals[i, j] <- (vals[i - 1, j + 1] - vals[i - 1, j])/stepsize
        }
    }
    return(signif(vals[order + 1, 1], sig))
}

#' Optimisation Routine for fitting LBSPR
#'
#' A function that calculate the negative log-likelihood of the LBSPR model
#'
#' @param trypars a vector of exploitation parameters in log space
#' @param yr index of the year column to fit the model to
#' @param LB_pars an object of class \code{'LB_pars'} that contains the life history information
#' @param LB_lengths an object of class \code{'LB_lengths'} that contains the length data
#' @param Control a list of control options for the LBSPR model.
#' @param pen apply a penalty if estimate of selectivity is very high?
#' @details The Control options are:
#' \describe{
#'  \item{\code{modtype}}{Model Type: either Growth-Type-Group Model (default: "GTG") or Age-Structured ("absel")}
#'  \item{\code{maxsd}}{Maximum number of standard deviations for length-at-age distribution (default is 2)}
#'  \item{\code{ngtg}}{Number of groups for the GTG model. Default is 13}
#'  \item{\code{P}}{Proportion of survival of initial cohort for maximum age for Age-Structured model. Default is 0.01}
#'  \item{\code{Nage}}{Number of pseudo-age classes in the Age Structured model. Default is 101}
#'  \item{\code{maxFM}}{Maximum value for F/M. Estimated values higher than this are trunctated to \code{maxFM}. Default is 4}
#' }
#' @return a NLL value
#' @author A. Hordyk
#'
#' @export
LBSPRopt <- function(trypars, yr=1, LB_pars=NULL, LB_lengths=NULL,  Control=list(), pen=TRUE) {
  if (class(LB_pars) != "LB_pars") stop("LB_pars must be of class 'LB_pars'. Use: new('LB_pars')")
  if (class(LB_lengths) != "LB_lengths") stop("LB_lengths must be of class 'LB_lengths'. Use: new('LB_lengths')")

  LB_pars@SL50 <- exp(trypars)[1] * LB_pars@Linf
  LB_pars@SL95 <- LB_pars@SL50 + (exp(trypars)[2]* LB_pars@Linf)
  LB_pars@FM <- exp(trypars[3])

  runMod <- LBSPRsim_(LB_pars, Control=Control, verbose=FALSE, doCheck=FALSE)

  ldat <- LB_lengths@LData[,yr] + 1E-15 # add tiny constant for zero catches
  LenProb <- ldat/sum(ldat)
  predProb <- runMod@pLCatch
  predProb <- predProb + 1E-15 # add tiny constant for zero catches
  NLL <- -sum(ldat * log(predProb/LenProb))
  # add penalty for SL50
  trySL50 <- exp(trypars[1])
  PenVal <- NLL
  Pen <- dbeta(trySL50, shape1=5, shape2=0.01) * PenVal
  if(!is.finite(NLL)) return(1E9 + runif(1, 1E4, 1E5))
  if (Pen == 0) Pen <- PenVal * trySL50
  if (!pen) Pen <- 0
  NLL <- NLL+Pen
  NLL
}

#' Plot simulated size composition
#'
#' A function that plots the expected size composition in the fished and unfished state
#'
#' @param LB_obj an object of class \code{'LB_obj'} that contains the life history and fishing information
#' @param type a character value indicating which plots to include: "all", "len.freq", "growth", "maturity.select", "yield.curve"
#' @param lf.type a character value indicating if the \code{catch} or \code{pop} (population) should be plotted for the length frequency
#' @param growth.type should growth be plotted as length-at-age (\code{"LAA"}) or weight-at-age (\code{"WAA"})
#' @param perRec a logical to indicate if plot should be per-recruit (ignore steepness) or not (zero recruitment if SPR below replacement level)
#' @param incSPR a logical to indicate if SPR value should be printed in top right corner of plot
#' @param Cols optional character vector of colours for the plot
#' @param size.axtex size of the axis text
#' @param size.title size of axis title
#' @param size.SPR size of SPR text
#' @return a ggplot object
#' @author A. Hordyk
#' @importFrom ggplot2 ggplot aes geom_line geom_point geom_bar scale_color_manual guides guide_legend xlab ylab theme theme_bw element_text scale_fill_manual scale_fill_discrete ggtitle
#' @importFrom gridExtra arrangeGrob
#' @export


plotSim <- function(LB_obj=NULL, type=c("all", "len.freq", "growth", "maturity.select", "yield.curve"), 
  lf.type=c("catch", "pop"), growth.type=c("LAA", "WAA"), perRec=FALSE, incSPR=TRUE, 
  Cols=NULL, size.axtex=12, size.title=14, size.SPR=4) {
  if (class(LB_obj) != "LB_obj") stop("LB_obj must be of class 'LB_obj'. Use: LBSPRsim")
  type <- match.arg(type, several.ok=TRUE)
  growth.type <- match.arg(growth.type)
  lf.type <- match.arg(lf.type)
  LMids <- LB_obj@LMids
  
  pLCatch <- LB_obj@pLCatch # predicted size comp of catch
  pLPop <- LB_obj@pLPop # predicted size comp of population
  
  if (length(pLPop) < 1) stop("No simulated population data")
  PopF <- pLPop[,"PopF"] 
  PopUF <- pLPop[,"PopUF"] 
  PopSizeDat <- data.frame(pLPop)
  
  if (!perRec) {
    relativePop <- PopF / (PopF[1]/PopUF[1]) * (LB_obj@RelRec/LB_obj@R0)
    PopSizeDat[,"PopF"] <- relativePop
  
    ind <- which(PopSizeDat[,"VulnUF"] > 0)[1]
    relativeCatch <- pLCatch / (pLCatch[ind]/PopSizeDat[,"VulnUF"][ind]) * (LB_obj@RelRec/LB_obj@R0)
    pLCatch <- relativeCatch
  }

  if (lf.type == "catch") {
    ind <- match(LMids, PopSizeDat[,1])
    Dat <- data.frame(LMids=LMids, VulnUF=PopSizeDat[ind, "VulnUF"], pLCatch=pLCatch)
	longDat <- gather(Dat, "PopType", "PLength", 2:ncol(Dat))
	Title <- "Catch"
	Leg <- c("Fished", "Unfished")
  }
  if (lf.type == "pop") {
    longDat <- gather(PopSizeDat, "PopType", "PLength", 2:ncol(PopSizeDat))
    longDat <- dplyr::filter(longDat, PopType == "PopUF" | PopType == "PopF")
	Title <- "Population"
	Leg <- c("Fished", "Unfished")
  }
  if (length(LB_obj@L_units) > 0) {
    XLab <- paste0("Length (", LB_obj@L_units, ")")
  } else XLab <- "Length"
  
  PopType <- PLength <- NULL # hack to get past CRAN
  LF.Plot <- ggplot(longDat, aes(x=LMids, y=PLength, fill=PopType)) +
	geom_bar(stat="identity", position = "identity") +
	xlab(XLab) +
    ylab("Relative Number") +
	theme_bw() +
	theme(axis.text=element_text(size=size.axtex),
        axis.title=element_text(size=size.title,face="bold"), legend.position="top")
 if (all(is.null(Cols))) LF.Plot <- LF.Plot + scale_fill_discrete(Title, labels = Leg)
 if (!all(is.null(Cols))) LF.Plot <- LF.Plot + scale_fill_manual(Title, labels = Leg, values=Cols)
 if (incSPR) {
    LF.Plot <- LF.Plot + annotate("text", x = 0.8*max(longDat$LMids), 
	  y = 0.95*max(longDat$PLength), label = paste("SPR =", LB_obj@SPR), size=size.SPR)
 }
 
 
 # Maturity & Selectivity 
 MatSel.Plot <- plotMat(LB_obj, size.axtex=size.axtex, size.title=size.title, useSmooth=TRUE, Title=NULL)
 
 Age <- Length <- Weight <- Y <- Reference <- FM <- Value <- Type  <- NULL # hack to get past CRAN check
 # Length at Age 
 P <- 0.01 
 x <- seq(from=0, to=1, length.out=200) # relative age vector
 EL <- (1-P^(x/LB_obj@MK )) *  LB_obj@Linf # length at relative age
 
 MaxAge <- 1 
 if (length(LB_obj@M) > 0) MaxAge <- ceiling(-log(P)/LB_obj@M)
 
 A50 <- x[min(which(EL >= LB_obj@L50))] * MaxAge
 SA50 <- x[min(which(EL >= LB_obj@SL50))] * MaxAge
 
 matdat <- data.frame(X=c(A50, SA50), 
   Y=c(LB_obj@L50, LB_obj@SL50), Reference=c("Maturity", "Selectivity"))
 matdat2 <- data.frame(X=c(A50, SA50), 
   Y=c(LB_obj@Walpha*LB_obj@L50^LB_obj@Wbeta, LB_obj@Walpha*LB_obj@SL50^LB_obj@Wbeta), 
   Reference=c("Maturity", "Selectivity"))
 
 lendat <- data.frame(Age=x*MaxAge, Length=EL)
 lendat2 <- data.frame(Age=x*MaxAge, Weight=LB_obj@Walpha*EL^LB_obj@Wbeta)
 
 if (MaxAge == 1) XLab <- "Relative Age\n"
 if (MaxAge != 1) XLab <- "Age"
 if (growth.type=="LAA") {
   if (length(LB_obj@L_units) > 0) {
     YLab <- paste0("Length (", LB_obj@L_units, ")")
    } else YLab <- "Length"
 } 
 if (growth.type=="WAA") {
   if (length(LB_obj@Walpha_units) > 0) {
     YLab <- paste0("Weight (", LB_obj@Walpha_units, ")")
    } else YLab <- "Weight"
 }
 
 LaA.Plot1 <- ggplot(lendat, aes(x=Age, y=Length)) + geom_line(size=1.5) + 
   geom_point(data=matdat, aes(x=X, y=Y, colour=Reference), size=4) +
   theme_bw() +
   guides(color=guide_legend(title="")) +
   theme(axis.text=element_text(size=size.axtex),
        axis.title=element_text(size=size.title,face="bold"), legend.position="top") +
   xlab(XLab) + ylab(YLab) 		
 
 WaA.Plot1 <- ggplot(lendat2, aes(x=Age, y=Weight)) + geom_line(size=1.5) + 
   geom_point(data=matdat2, aes(x=X, y=Y, colour=Reference), size=4) +
   theme_bw() +
   guides(color=guide_legend(title="")) +
   theme(axis.text=element_text(size=size.axtex),
        axis.title=element_text(size=size.title,face="bold"), legend.position="top") +
   xlab(XLab) + ylab(YLab)

  if (growth.type=="LAA") LaA.Plot <- LaA.Plot1
  if (growth.type=="WAA") LaA.Plot <- WaA.Plot1
  
 # SPR versus F &  # Yield versus F 
 if ("yield.curve" %in% type) {
   FMVec <- seq(from=0, to=LB_obj@maxFM, by=0.05)
   SPROut <- matrix(NA, nrow=length(FMVec), ncol=2)
   YieldOut <- matrix(NA, nrow=length(FMVec), ncol=2)
   YPROut <- matrix(NA, nrow=length(FMVec), ncol=2)
   
   LB_obj2 <- LB_obj
   LB_obj2@SPR <- numeric()
   nsim <- length(FMVec)
   Vals <- vapply(1:nsim, function(X) {
     LB_obj2@FM <- FMVec[X] 
     c(SPR=LBSPRsim(LB_obj2)@SPR,
     LBSPRsim(LB_obj2)@YPR,
     LBSPRsim(LB_obj2)@Yield)
   }, FUN.VALUE=array(0,dim=c(3)))
   Vals <- t(Vals)
   colnames(Vals) <- c("SPR", "YPR", "Yield")
   
   # Add units for size
   Vals[,"YPR"] <- Vals[,"YPR"]/max(Vals[,"YPR"])
   Vals[,"Yield"] <- Vals[,"Yield"]/max(Vals[,"Yield"])
   
   if (perRec) {
     ValDF <- data.frame(Value=c(Vals[,"SPR"],  Vals[,"YPR"]),
     Type=c(rep("SPR", nsim), rep("Relative Yield-per-Recruit", nsim)), FM=FMVec)
     ValDF$Type <- factor(ValDF$Type, levels = c("SPR", "Relative Yield-per-Recruit"))
	 tempVal <- min(which(FMVec >= LB_obj@FM))
	 yieldpoint <- Vals[tempVal,"YPR"] 
	 pointdat <- data.frame(X=c(LB_obj@FM, LB_obj@FM), Y=c(LB_obj@SPR, yieldpoint),
     Type=c("SPR", "Relative Yield-per-Recruit"))
   } else {
     ValDF <- data.frame(Value=c(Vals[,"SPR"],  Vals[,"Yield"]),
     Type=c(rep("SPR", nsim), rep("Relative Yield", nsim)), FM=FMVec)
     ValDF$Type <- factor(ValDF$Type, levels = c("SPR", "Relative Yield"))
	 tempVal <- min(which(FMVec >= LB_obj@FM))
	 yieldpoint <- Vals[tempVal,"Yield"] 
	 pointdat <- data.frame(X=c(LB_obj@FM, LB_obj@FM), Y=c(LB_obj@SPR, yieldpoint),
     Type=c("SPR", "Relative Yield"))
   }
   
   Yield.Plot <- ggplot(ValDF, aes(x=FM, y=Value)) + geom_line(size=1.5, aes(color=Type)) +
     theme_bw() +
     guides(color=guide_legend(title="")) +
     theme(axis.text=element_text(size=size.axtex),
          axis.title=element_text(size=size.title,face="bold"), legend.position="top") +
     xlab("Relative Fishing Mortality \n(F/M)") + 
     ylab("") +
	 geom_point(data=pointdat, aes(x=X, y=Y, color=Type), size=3) 
   
 }

 L <- list() 
 if ("all" %in% type) {  
   L[[1]] <- LF.Plot
   L[[2]] <- LaA.Plot 
   L[[3]] <- MatSel.Plot
   L[[4]] <- Yield.Plot
   plot(arrangeGrob(grobs=L, layout_matrix=matrix(1:length(L), ncol=2, nrow=2)))
 } else {
   for (X in seq_along(type)) {
     if ("len.freq" %in% type[X]) L[[X]] <- LF.Plot 
	 if ("growth" %in% type[X]) L[[X]] <- LaA.Plot
	 if ("maturity.select" %in% type[X]) L[[X]] <- MatSel.Plot
	 if ("yield.curve" %in% type[X]) L[[X]] <- Yield.Plot
   }

   plot(arrangeGrob(grobs=L, layout_matrix=matrix(1:length(L), ncol=length(L), nrow=1)))
 }
 
}

#' Plot the maturity-at-length and selectivity-at-length curves
#'
#' A function that plots the maturity-at-length and selectivity-at-length curves
#'
#' @param LB_obj an object of class \code{'LB_obj'} that contains the life history and fishing information
#' @param size.axtex size of the axis text
#' @param size.title size of axis title
#' @param useSmooth use the smoothed estimates?
#' @param Title optional character string for plot title
#' @return a ggplot object
#' @author A. Hordyk
#'
#' @importFrom grDevices colorRampPalette
#' @importFrom tidyr gather
#' @importFrom RColorBrewer brewer.pal
#' @export
plotMat <- function(LB_obj=NULL, size.axtex=12, size.title=14, useSmooth=TRUE, Title=NULL) {
  if (class(LB_obj) != "LB_obj" & class(LB_obj) != "LB_pars") stop("LB_obj must be of class 'LB_obj' or class 'LB_pars'")

  if ("LMids" %in% slotNames(LB_obj)) Lens <- seq(from=LB_obj@LMids[1], to=LB_obj@LMids[length(LB_obj@LMids)], by=1)
  if (!("LMids" %in% slotNames(LB_obj))) Lens <- seq(from=0, to=LB_obj@Linf, by=1)
  # Length at Maturity
  if (length(LB_obj@L_units) > 0) {
    XLab <- paste0("Length (", LB_obj@L_units, ")")
  } else XLab <- "Length"
  LenMat <- 1.0/(1+exp(-log(19)*(Lens-LB_obj@L50)/(LB_obj@L95-LB_obj@L50)))
  DF <- data.frame(Lens=Lens, Dat=LenMat, Line="Maturity")
  Dat <- Proportion <- Line <- SelDat <- Year <- NULL # hack to get past CRAN check
  mplot <- ggplot(DF, aes(x=Lens, y=Dat)) +
    geom_line(aes(color="Maturity"), size=1.5) +
	scale_color_manual(values="black") +
    guides(color=guide_legend(title="")) +
	xlab(XLab) +
    ylab("Proportion") +
	theme_bw() +
	theme(axis.text=element_text(size=size.axtex),
    axis.title=element_text(size=size.title,face="bold"), legend.position="top",
	plot.title = element_text(lineheight=.8, face="bold"))

  if (class(LB_obj) == "LB_obj") {
    if (length(LB_obj@Ests)>0 & (class(LB_obj@Years) != "numeric" & class(LB_obj@Years) != "integer")) {
      warning("Years must be numeric values")
	  message("Attempting to convert to numeric values")
	  options(warn=-1)
      LB_obj@Years <-  gsub("X", "", LB_obj@Years)
	  LB_obj@Years <- as.numeric(LB_obj@Years)
	  options(warn=1)
      if (all(is.na(LB_obj@Years))) LB_obj@Years <- 1:length(LB_obj@Years)
    }

    years <- LB_obj@Years
    if (length(years) < 1) years <- 1

    if (useSmooth & length(LB_obj@Ests) > 0) {
      SL50 <- LB_obj@Ests[,"SL50"]
      SL95 <- LB_obj@Ests[,"SL95"]
    }
    if (!useSmooth | length(LB_obj@Ests) == 0) {
      SL50 <- LB_obj@SL50
      SL95 <- LB_obj@SL95
    }
    if (length(SL50) > 0 & (length(years) == 1 | length(SL50) < 2)) {
      LenSel <- 1.0/(1+exp(-log(19)*(Lens-(SL50))/((SL95)-(SL50))))
      longSel <- data.frame(Lens=Lens, Selectivity=LenSel, Maturity=LenMat)
	  longSel <- gather(longSel, "Line", "Proportion", 2:3)
	  mplot <- ggplot(longSel, aes(x=Lens, y=Proportion)) +
        geom_line(aes(color=Line), size=1.5) +
	    xlab(XLab) +
        ylab("Proportion") +
	    guides(color=guide_legend(title="")) +
	    theme_bw() +
	    theme(axis.text=element_text(size=size.axtex),
        axis.title=element_text(size=size.title,face="bold"), legend.position="top")
    }
    if (length(SL50) > 0 & (length(years) > 1 | length(SL50) > 1)) { # Multiple years exist
      LenSel <- sapply(1:length(years), function(X)
	    1.0/(1+exp(-log(19)*(Lens-(SL50[X]))/((SL95[X])-(SL50[X])))))
      LenSel <- data.frame(LenSel, check.names=FALSE)
	  colnames(LenSel) <- years
      longSel <- gather(LenSel, "Year", "SelDat")
	  colourCount <- length(years)
	  getPalette <- colorRampPalette(brewer.pal(12, "Set3"))
	  cols <- rep(getPalette(min(12, colourCount)),5)[1:colourCount]
	  longSel$Lens <- DF$Lens
	  suppressMessages(
	    mplot <-  mplot +
	      guides(color=guide_legend(title="Est. Selectivity")) +
	      scale_color_manual(values = c(cols, "black")) +
	      geom_line(aes(x=Lens, y=SelDat, color=Year), longSel, size=1)
	  )
    }
  }
  if (!(is.null(Title)) & class(Title)=="character")  mplot <- mplot + ggtitle(Title)

  mplot
}

#' Plot the size data and model fits
#'
#' A function that plots size data and the fitted LBSPR model
#'
#' @param LB_obj an object of class \code{'LB_obj'} that contains the life history and fishing information
#' @param size.axtex size of the axis text
#' @param size.title size of axis title
#' @param Title optional character string for plot title
#' @return a ggplot object
#' @author A. Hordyk
#'
#' @importFrom ggplot2 facet_wrap geom_text
#' @export
plotSize <- function(LB_obj=NULL, size.axtex=12, size.title=14, Title=NULL) {
  if (class(LB_obj) != "LB_obj" & class(LB_obj) != "LB_lengths") stop("Require LB_lengths or LB_obj object")

  if (class(LB_obj@Years) != "numeric" & class(LB_obj@Years) != "integer") {
    warning("Years must be numeric values")
	message("Attempting to convert to numeric values")
	options(warn=-1)
    LB_obj@Years <-  gsub("X", "", LB_obj@Years)
	LB_obj@Years <- as.numeric(LB_obj@Years)
	options(warn=1)
    if (all(is.na(LB_obj@Years))) LB_obj@Years <- 1:length(LB_obj@Years)
  }

  NYrs <- max(1, length(LB_obj@Years))
  Years <- LB_obj@Years
  Ldat <- LB_obj@LData
  if (length(Ldat) < 1) stop("No length data found")
  LMids <- LB_obj@LMids
  Ldat <- data.frame(Ldat, check.names=FALSE)
  colnames(Ldat) <- as.character(Years)
  longDat <- gather(Ldat, "Year", "LBSPR_len")
  longDat$LMids <- LMids
  longDat$Year <- factor(longDat$Year, levels=colnames(Ldat))
  NCol <- ceiling(sqrt(NYrs))
  NRow <- ceiling(NYrs/NCol)
  LBSPR_len <- lab <- NULL # hack to get past CRAN check
  if (length(LB_obj@L_units) > 0) {
    XLab <- paste0("Length (", LB_obj@L_units, ")")
  } else XLab <- "Length"
  bplot <- ggplot(longDat, aes(x=LMids, y=LBSPR_len)) +
   facet_wrap(~Year, ncol=NCol) +
   geom_bar(stat="identity") +
   xlab(XLab) +
   ylab("Count") +
   theme_bw() +
   theme(axis.text=element_text(size=size.axtex),
   axis.title=element_text(size=size.title,face="bold"),
   plot.title = element_text(lineheight=.8, face="bold"))

  if (!(is.null(Title)) & class(Title)=="character") bplot <- bplot + ggtitle(Title)

  chk <- ("pLCatch" %in% slotNames(LB_obj))
  chk2 <- FALSE
  if (chk) if (length(LB_obj@pLCatch) > 0) chk2 <- TRUE
  if (chk & chk2) { # model has been fitted
	NSamp <- apply(LB_obj@LData, 2, sum)
	predlen <- data.frame(sweep(LB_obj@pLCatch, MARGIN=2, NSamp, "*")) #
    longDat2 <- gather(predlen, "Year", "PredLen")
	longDat2$LMids <- LMids
    bplot <- bplot +
	  geom_line(aes(x=longDat2$LMids, y=longDat2$PredLen), colour="black", size=1.25)
	fitLog <- LB_obj@fitLog
	ind <- which(fitLog > 0)
	if (length(ind) > 0) {
	  # Didn't converge
	  yrs <- unique(longDat$Year)[which(fitLog == 1)]
	  if (length(yrs) > 0) {
	    text_dat <- data.frame(Year=factor(yrs), levels=levels(longDat$Year),
	      LMids=longDat$LMids[0.5*length(longDat$LMids)],
		  LBSPR_len=0.99 * max(longDat$LBSPR_len), lab="Model didn't converge")
        bplot <- bplot + geom_text(data=text_dat, aes(label=lab), size=6)
	  }
	  # High Selectivity 
	  yrs <- unique(longDat$Year)[which(fitLog == 2)]
	  if (length(yrs) > 0) {
	    text_dat <- data.frame(Year=factor(yrs), levels=levels(longDat$Year),
	      LMids=longDat$LMids[0.5*length(longDat$LMids)],
		  LBSPR_len=0.99 * max(longDat$LBSPR_len), 
		  lab="Estimated selectivity\n may be realistically high")
        bplot <- bplot + geom_text(data=text_dat, aes(label=lab), size=6)	
	  }
	  # High F/M
	  yrs <- unique(longDat$Year)[which(fitLog == 3)]
	  if (length(yrs) > 0) {
	    text_dat <- data.frame(Year=factor(yrs), levels=levels(longDat$Year),
	      LMids=longDat$LMids[0.5*length(longDat$LMids)],
		  LBSPR_len=0.99 * max(longDat$LBSPR_len), 
		  lab="Estimated F/M appears\n be realistically high")
        bplot <- bplot + geom_text(data=text_dat, aes(label=lab), size=6)	
	  }
	  # High F/M & Selectivity
	  yrs <- unique(longDat$Year)[which(fitLog == 4)]
	  if (length(yrs) > 0) {	  
	    text_dat <- data.frame(Year=factor(yrs), levels=levels(longDat$Year),
	      LMids=longDat$LMids[0.5*length(longDat$LMids)],
		  LBSPR_len=0.99 * max(longDat$LBSPR_len), 
		  lab="Estimated selectivity\n and F/M may be realistically high")
        bplot <- bplot + geom_text(data=text_dat, aes(label=lab), size=6)		  
	  }
	}
  }

  bplot
}

#' Circle of estimated SPR and target and limit points
#'
#' A function that creates a circle plot showing the estimated SPR relative to the
#' target and limit reference points
#'
#' @param LB_obj an object of class \code{'LB_obj'} that contains the life history and fishing information
#' @param SPRTarg a numeric value specifying the SPR target
#' @param SPRLim a numeric value specifying the SPR limit
#' @param useSmooth use the smoothed estimates? Usually would want to do this
#' @param Title include the title?
#' @param Leg include the legend?
#' @param limcol colour for SPR Limit (hex; default is red)
#' @param targcol colour for SPR target (hex; default is orange) 
#' @param abtgcol colour for above SPR target (hex; default is green)
#' @param labcol optional fixed colour for estimated SPR label
#' @param bgcol colour for the background
#' @param labcex size for the estimated SPR label
#' @param texcex size for estimated other labels 

#' @author A. Hordyk
#' @importFrom plotrix draw.circle draw.ellipse draw.radial.line radialtext
#' @export
plotSPRCirc <- function(LB_obj=NULL, SPRTarg=0.4, SPRLim=0.2, useSmooth=TRUE, 
  Title=FALSE, Leg=TRUE, limcol="#ff1919", targcol="#ffb732", abtgcol="#32ff36", 
  labcol=NULL, bgcol="#FAFAFA", labcex=2, texcex=1.3) {
  if (class(LB_obj) != "LB_obj") stop("LB_obj must be of class 'LB_obj'. Use LBSPRfit")

  par(mfrow=c(1,1), mar=c(1,2,3,2), oma=c(1,1,1,1))
  plot(1:10, asp = 1,main="", type="n", bty="n", axes=FALSE,
    xlim=c(0,10), ylim=c(0,10), xlab="", ylab="")
  a <- 4.5
  x <- 5
  if (useSmooth) spr <- LB_obj@Ests[,"SPR"]
  if (!useSmooth) spr <- LB_obj@SPR
  if (length(spr) > 1) {
    message("More than one SPR value. Using last value")
    flush.console()
	spr <- spr[length(spr)]
  }

  ang <- 90 - (spr*360)
  ang2 <- 90
  tg  <- 90 - (SPRTarg*360)
  lim <- 90 - (SPRLim*360)
  # limcol <- "#ff1919"
  # targcol <- "#ffb732"
  # abtgcol <- "#32ff36"
  nv <- 200
  # texcex <- 1.3 
  # texcex2 <- 2
  # Circle
	  
  draw.circle(x=x, y=x, radius=a, border=bgcol, col=bgcol, nv=nv)
  # Limit Ellipse
  draw.ellipse(x=x, y=x, a=a, b=a, angle=0, segment=c(max(lim, ang), ang2),
      col=limcol, arc.only=FALSE, border=FALSE, nv=nv)
  if (spr > SPRLim) {
  draw.ellipse(x=x, y=x, a=a, b=a, angle=0, segment=c(max(tg, ang), lim),
    col=targcol, arc.only=FALSE, border=FALSE, nv=nv)
  }
  if (spr > SPRTarg) {
    draw.ellipse(x=x, y=x, a=a, b=a, angle=0, segment=c(min(360, ang), tg),
      col=abtgcol, arc.only=FALSE, border=FALSE, nv=nv)
  }
  # radialtext(as.character(round(spr,2)), center=c(x,x), start=NA,
    # middle=a/2, end=NA, deg=ang, expand=FALSE, stretch=1, nice=TRUE,
   # cex=1, xpd=NA)
  draw.radial.line(0, a, center=c(x, x), deg=lim,
       expand=FALSE, col=limcol, lwd=1, lty=1)
  draw.radial.line(0, a, center=c(x, x), deg=tg,
       expand=FALSE, col=targcol, lwd=1, lty=1)
  draw.radial.line(0, x-0.5, center=c(x, x), deg=ang,
       expand=FALSE, col="black", lwd=3, lty=2)
	   
  rndspr <- round(spr,2)*100
 
  if (rndspr <= SPRLim*100) textcol <- limcol
  if (rndspr <= SPRTarg*100 & rndspr > SPRLim*100) textcol <- targcol
  if (rndspr > SPRTarg*100)  textcol <- abtgcol
  if (class(labcol) == "character") textcol <- labcol
  radialtext(paste0(round(spr,2)*100, "%"), 
    center=c(x,x), start=x-0.2, middle=1, end=NA, deg=ang,  expand=0, stretch=1, 
	nice=TRUE, cex=labcex, xpd=NA, col=textcol)
  
  if (Title) mtext(side=3, paste0("Estimated SPR = ", round(spr,2)),
    cex=1.25, line=-4 ,outer=TRUE)
  if (Leg) legend("topleft", legend=c(as.expression(bquote(Below ~ Limit ~ .(SPRLim*100) * "%")),
    as.expression(bquote(Below ~ Target ~ .(SPRTarg*100) * "%")), "Above Target"), bty="n", pch=15, pt.cex=2,
	col=c(limcol, targcol, abtgcol),
	bg=c(limcol, targcol, abtgcol), title=expression(bold("SPR")), cex=texcex)
  # if (Leg) legend("topright", bty="n",
    # legend=as.expression(bquote(Estimate ~ .(round(spr,2)*100) * "%")),
	# lty=2,lwd=3, cex=texcex)
    
  text(x, x+a, "0%", pos=3, xpd=NA, cex=texcex)
  text(x+a, x, "25%", pos=4, xpd=NA, cex=texcex)
  text(x, x-a, "50%", pos=1, xpd=NA, cex=texcex)
  text(x-a, x, "75%", pos=2, xpd=NA, cex=texcex)
}


#' Plot LBSPR model estimates
#'
#' A function that plots the estimates of the LBSPR with a smoother line
#'
#' @param LB_obj an object of class \code{'LB_obj'} that contains the life history and fishing information
#' @param pars a character vectors specifying which plots to create
#' @param Lwd line width
#' @param ptCex size of plotted points
#' @param axCex size of the axis
#' @param labCex size of axis label
#' @param doSmooth apply the smoother?
#' @param incL50 include L50 line?
#' @param CIcol colour of the confidence interval bars
#' @param L50col colour of L50 line (if included)
#' @author A. Hordyk
#' @importFrom graphics abline axis hist legend lines mtext par plot points text
#' @importFrom plotrix plotCI
#' @export
plotEsts <- function(LB_obj=NULL, pars=c("Sel", "FM", "SPR"), Lwd=2.5, ptCex=1.25, 
  axCex=1.45, labCex=1.55, doSmooth=TRUE, incL50=FALSE, CIcol="darkgray", L50col="gray") {
  if (class(LB_obj) != "LB_obj") stop("LB_obj must be of class 'LB_obj'. Use LBSPRfit")
  if (length(LB_obj@Ests) < 1) stop("No estimates found. Use LBSPRfit")
  pars <- match.arg(pars, several.ok=TRUE)
  rawEsts <- data.frame(SL50=LB_obj@SL50, SL95=LB_obj@SL95, FM=LB_obj@FM, SPR=LB_obj@SPR)
  if (class(LB_obj@Years) != "numeric" & class(LB_obj@Years) != "integer") {
    warning("Years must be numeric values")
	message("Attempting to convert to numeric values")
	options(warn=-1)
    LB_obj@Years <-  gsub("X", "", LB_obj@Years)
	LB_obj@Years <- as.numeric(LB_obj@Years)
	options(warn=1)
    if (all(is.na(LB_obj@Years))) LB_obj@Years <- 1:length(LB_obj@Years)
  }

  rawEsts$Years <-  LB_obj@Years
  if (length(LB_obj@Years) < 2) message("This plot doesn't make much sense with only 1 year. But here it is anyway")
  smoothEsts <- data.frame(LB_obj@Ests)
  smoothEsts$Years <- LB_obj@Years
  
  ## 95% CIs ##
  CIlower <- rawEsts[,1:4] - 1.96 * sqrt(LB_obj@Vars)
  CIupper <- rawEsts[,1:4] + 1.96 * sqrt(LB_obj@Vars)
  
  # correct bounded parameters - dodgy I know!
  CIlower[CIlower[,3]<0,3] <- 0
  CIlower[CIlower[,4]<0,4] <- 0
  CIupper[CIupper[,4]>1,4] <- 1 
  
  CIlower[!apply(CIlower, 2, is.finite)] <- NA
  CIupper[!apply(CIupper, 2, is.finite)] <- NA
  # CIlower[!is.finite(CIlower)] <- NA
  # CIupper[!is.finite(CIupper)] <- NA
	
  scol <- CIcol 
  
  at <- seq(from=min(LB_obj@Years)-1, to=max(LB_obj@Years)+1, by=1)
  nplots <- 0
  doSel <- doFM <- doSPR <- FALSE
  if ("Sel" %in% pars) {
    doSel <- TRUE
    nplots <- nplots + 1
  }
  if ("FM" %in% pars) {
    nplots <- nplots + 1
	doFM <- TRUE
  }
  if ("SPR" %in% pars) {
    nplots <- nplots + 1
	doSPR <- TRUE
  }
  par(mfrow=c(1,nplots), bty="l", las=1, mar=c(3,4,2,2), oma=c(2,2,0,0))
  # Selectivity
  if (doSel) {
    YLim <- c(min(CIlower[,1], na.rm=TRUE) * 0.95, max(CIupper[,2], na.rm=TRUE) * 1.05)
	YLim <- range(pretty(YLim))
    # plot(rawEsts$Years,  rawEsts$SL50, ylim=YLim, xlab="", ylab="", axes=FALSE, type="n")
	# myLeg <- legend("topright", bty="n", legend=c(expression(S[L50]), expression(S[L95]),
	  # expression(L[50])), lty=c(1,2,1), lwd=Lwd, col=c("black", "black", "gray"),
	  # cex=1.75, xpd=NA, plot=FALSE)

    # YLim[2] <- 1.04*(YLim[2]+myLeg$rect$h)
    par(mfrow=c(1,nplots), bty="l", las=1, mar=c(3,4,2,2), oma=c(2,2,0,0))
	plot(rawEsts$Years,  rawEsts$SL50, ylim=YLim, xlab="", ylab="", axes=FALSE, type="n")
	plotrix::plotCI(x=rawEsts$Years, y=rawEsts$SL50, ui=CIupper[,1], li=CIlower[,1], add=TRUE, scol=scol,
	   pch=19, cex=ptCex)
	
	axis(side=1, at=at, cex.axis=axCex)
	axis(side=2, at=pretty(YLim), cex.axis=axCex)
    if(doSmooth) lines(smoothEsts$Years,  smoothEsts$SL50, lwd=Lwd)
   
    # points(rawEsts$Years,  rawEsts$SL95, pch=17)
	plotrix::plotCI(x=rawEsts$Years, y=rawEsts$SL95, ui=CIupper[,2], li=CIlower[,2], add=TRUE, pch=17, scol=scol,
	  cex=ptCex)
    if(doSmooth) lines(smoothEsts$Years,  smoothEsts$SL95, lwd=Lwd, lty=2)
    if (incL50) abline(h=LB_obj@L50, col=L50col, lwd=0.5)
	mtext(side=2, line=4, "Selectivity", cex=labCex, las=3)
	if (incL50 & doSmooth) 
	  legend("topright", bty="n", legend=c(expression(S[L50]), expression(S[L95]),
	  expression(L[50])), lty=c(1,2,1), lwd=Lwd, col=c("black", "black", "gray"),
	  cex=1.75, xpd=NA)
	if (!incL50 & doSmooth) 
	  legend("topright", bty="n", legend=c(expression(S[L50]), expression(S[L95])), 
	  lty=c(1,2), lwd=Lwd, col=c("black"),  cex=1.75, xpd=NA)	
	if (incL50 & !doSmooth)
	  legend("topright", bty="n", legend=c(expression(S[L50]), expression(S[L95]),
	  expression(L[50])), pch=c(17, 19, 15), col=c("black", "black", L50col),
	  cex=ptCex, xpd=NA)
	if (!incL50 & !doSmooth)
	  legend("topright", bty="n", legend=c(expression(S[L50]), expression(S[L95])),
	  pch=c(19, 17), col=c("black"), cex=ptCex, xpd=NA)	
  }
  # Relative Fishing Mortality
  if (doFM) {
    YMax <- max(CIupper[,3], na.rm=TRUE) * 1.05
    YMin <- min(CIlower[,3], na.rm=TRUE) * 0.95
	YLim <- round(c(YMin, YMax),2)
	YLim <- range(pretty(YLim))
    plot(rawEsts$Years,  rawEsts$FM, ylim=YLim, type="n", xlab="", ylab="", cex.axis=axCex, axes=FALSE)
	plotrix::plotCI(x=rawEsts$Years, y=rawEsts$FM, ui=CIupper[,3], li=CIlower[,3], add=TRUE, scol=scol,
	  cex=ptCex, pch=19)
    axis(side=1, at=at, cex.axis=axCex)
	axis(side=2, at=pretty(YLim), cex.axis=axCex)
    if(doSmooth) lines(smoothEsts$Years,  smoothEsts$FM, lwd=Lwd)
	mtext(side=2, line=4, "F/M", cex=labCex, las=3)
  }
  # SPR
  if (doSPR) {
    plot(rawEsts$Years,  rawEsts$SPR, ylim=c(0,1), type="n", xlab="", ylab="", cex.axis=axCex, axes=FALSE)
	plotrix::plotCI(x=rawEsts$Years, y=rawEsts$SPR, ui=CIupper[,4], li=CIlower[,4], add=TRUE, scol=scol,
	 cex=ptCex, pch=19)
	axis(side=1, at=at, cex.axis=axCex)
	axis(side=2, at=pretty(c(0,1)), cex.axis=axCex)
    if(doSmooth) lines(smoothEsts$Years,  smoothEsts$SPR, lwd=Lwd)
	mtext(side=2, line=4, "SPR", cex=labCex, las=3)
  }
  mtext(outer=TRUE, side=1, line=1, "Years", cex=labCex)
}

#' Report the location of the Data Files
#'
#' A function that returns the location of the example CSV files
#'
#' @author A. Hordyk modified (i.e., stolen) from T. Carruthers' code (DLMtool package)
#' @export
DataDir<-function(){
    return(paste(searchpaths()[match("package:LBSPR",search())],"/",sep=""))
}


#' Plot sampled length structure against target simulated size composition
#'
#' A function that plots the observed size structure against the expected size composition at the target SPR
#'
#' @param LB_pars an object of class \code{'LB_pars'} that contains the life history and fishing information
#' @param LB_lengths an object of class \code{'LB_lengths'} that contains the observed size data 
#' @param yr index for sampled length data (defaults to 1)
#' @param Cols optional character vector of colours for the plot
#' @param size.axtex size of the axis text
#' @param size.title size of axis title
#' @return a ggplot object
#' @author A. Hordyk
#' @importFrom ggplot2 ggplot aes geom_line geom_bar scale_color_manual guides guide_legend xlab ylab theme theme_bw element_text scale_fill_manual scale_fill_discrete ggtitle scale_alpha_manual annotate
#' @importFrom stats optimize quantile
#' @export
plotTarg <- function(LB_pars=NULL, LB_lengths=NULL, yr=1, Cols=NULL, size.axtex=12, size.title=14) {
  if (class(LB_pars) != "LB_pars") stop("LB_pars must be of class 'LB_pars' Use: new('LB_lengths')")
  if (class(LB_lengths) != "LB_lengths") stop("LB_lengths must be of class 'LB_lengths'. Use: new('LB_lengths')")
  
  if (length(LB_pars@SPR) < 1) stop("Must supply SPR target (LB_pars@SPR)")
  if (length(LB_pars@SL50) < 1) stop("Must supply SL50 (LB_pars@SL50)")
  if (length(LB_pars@SL95) < 1) stop("Must supply SL95 (LB_pars@SL95)")

  LMids <- LB_lengths@LMids 
  LB_pars@BinWidth <- LMids[2] - LMids[1]
  LB_pars@BinMin <- min(LMids) - 0.5 * LB_pars@BinWidth
  LB_pars@BinMax <- max(LMids) + 0.5 * LB_pars@BinWidth

  LB_obj <- LBSPRsim(LB_pars, verbose=FALSE)
  pLCatch <- LB_obj@pLCatch # predicted size comp of catch - target
  pLSample <- as.matrix(LB_lengths@LData[,yr]) # predicted size comp of population
  
  # scale predicted to sample
  ScaleCatch <- function(Scale, Sample, PredCatch) {
    ind <- which.max(Sample) 
	if (ind < 1) ind <- 1 
	wght <- Sample[1:ind]
	sum((((PredCatch[1:ind] * Scale) -  Sample[1:ind]) * wght)^2)
  }
  
  Scale <- optimize(ScaleCatch, interval=c(1, 5000), Sample=pLSample, PredCatch=pLCatch)$minimum
 
  pLCatch <- pLCatch * Scale
  
  Dat <- data.frame(LMids=LMids, pLCatch=pLCatch, Sample=pLSample)
  longDat <- gather(Dat, "PopType", "PLength", 2:ncol(Dat))
  Title <- "Size Structure"
  Leg <- c("Target", "Sample")
  longDat$alphayr <- c(rep(1, length(pLCatch)), rep(0.6, length(pLCatch)))
  
  SPRtarg <- LB_pars@SPR 
  if (SPRtarg < 1) SPRtarg <- SPRtarg * 100 
  
  targ <- paste0("SPR Target: ", SPRtarg, "%")
  x <- quantile(LMids, 0.8)
  y <- max(longDat$PLength) *0.8
  
  if (length(LB_obj@L_units) > 0) {
    XLab <- paste0("Length (", LB_obj@L_units, ")")
  } else XLab <- "Length"
  PopType <- PLength <- alphayr <- NULL # hack to get past CRAN
  Plot <- ggplot(longDat, aes(x=LMids, y=PLength, fill=PopType, alpha=factor(alphayr))) +
	geom_bar(stat="identity", position = "identity") +
	xlab(XLab) +
    ylab("Relative Number") +
	scale_alpha_manual(values = c("0.6"=0.6, "1"=1), guide='none') + 
	theme_bw() +
	theme(axis.text=element_text(size=size.axtex),
        axis.title=element_text(size=size.title,face="bold"))
  if (all(is.null(Cols))) Plot <- Plot + scale_fill_discrete(Title, labels = Leg)
  if (!all(is.null(Cols))) Plot <- Plot + scale_fill_manual(Title, labels = Leg, 
    values=Cols)
  Plot <- Plot + annotate("text", x=x, y=y, label=targ)
  
  Plot
}

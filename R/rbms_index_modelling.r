##==========================================
## Name Convention in the rbms package
##
##      FUNCTION: ts_snake_function()
##      ARGUMENT: CamelNotation
##      OBJECT: object_snake_name
##      VARIABLE NAME: UPPER_CASE
##
##      Date:   02.01.2018
##
##      index_modelling: functions for abundance index model
##
##==========================================


#' fit_gam
#' fit a Generalized Additive Model to butterfly count data to extract the annual flight curve.
#' @param dataset_y data.table with filtered butterfly counts for species x over year y over all sites.
#' @param NbrSample integer inherited from \link{flight_curve}, default=100.
#' @param GamFamily string inherited from \link{flight_curve}, default='poisson', but can be 'nb' or 'quasipoisson'.
#' @param MaxTrial integer inherited from \link{flight_curve}, default=3.
#' @param SpeedGam Logical to use the \link[mgcv]{bam} method instead of the \link[mgcv]{gam} method.
#' @param OptiGam Logical to set use bam when data are larger than 100 and gam for smaller dataset
#' @param ... additional parameters passed to gam or bam function from the \link[mgcv]{gam} package.
#' @return A list with three objects, i) **f_curve**: a data.table with the flight curve \code{f_curve} with expected relative abudance, normalize to sum to one over a full season,
#'         ii) **f_model**: the resulting gam model \code{f_model} fitted on the count data and iii) **f_data**: a data.table with the data used to fit the GAM model.
#' @keywords gam
#' @seealso \link{flight_curve}, \link[mgcv]{gam}, \link[mgcv]{bam}
#' @author Reto Schmucki - \email{reto.schmucki@@mail.mcgill.ca}
#' @import data.table
#' @export fit_gam
#'

fit_gam <- function(dataset_y, NbrSample = NbrSample, GamFamily = GamFamily, MaxTrial = MaxTrial,
                    SpeedGam = TRUE, OptiGam = TRUE, ...){

        check_package('data.table')

        tr <- 1
        gam_obj_site <- c()

        while((tr == 1 | class(gam_obj_site)[1] == "try-error") & tr <= MaxTrial){

            if (dataset_y[, uniqueN(SITE_ID)] > NbrSample) {
                sp_data_all <- data.table::copy(dataset_y[SITE_ID %in% sample(unique(dataset_y[, SITE_ID]), NbrSample, replace = FALSE), ])
            } else {
                sp_data_all <- data.table::copy(dataset_y)
            }

            if(isTRUE(OptiGam)){
                if(sp_data_all[, uniqueN(SITE_ID)] < 100){
                    SpeedGam <- FALSE
                }
            }

            gamMethod <-'gam()'
            if(isTRUE(SpeedGam)){
                gamMethod <- 'SpeedGAM [bam()]'
            }

            print(paste("Fitting the RegionalGAM for species", as.character(sp_data_all$SPECIES[1]), "and year", sp_data_all$M_YEAR[1], "with",
                        sp_data_all[, uniqueN(SITE_ID)], "sites, using", gamMethod, ":", Sys.time(), "-> trial", tr))

            if(isTRUE(SpeedGam)){
                if(length(sp_data_all[, unique(SITE_ID)]) > 1){
                    gam_obj_site <- try(mgcv::bam(COUNT ~ s(trimDAYNO, bs = "cr") + as.factor(SITE_ID), data=sp_data_all, family=GamFamily, ...), silent = TRUE)
                } else {
                    gam_obj_site <- try(mgcv::bam(COUNT ~ s(trimDAYNO, bs = "cr"), data=sp_data_all, family=GamFamily, ...), silent = TRUE)
                }
            } else {
                if(length(sp_data_all[, unique(SITE_ID)]) > 1){
                    gam_obj_site <- try(mgcv::gam(COUNT ~ s(trimDAYNO, bs = "cr") + as.factor(SITE_ID), data=sp_data_all, family=GamFamily, ...), silent = TRUE)
                } else {
                    gam_obj_site <- try(mgcv::gam(COUNT ~ s(trimDAYNO, bs = "cr"), data=sp_data_all, family=GamFamily, ...), silent = TRUE)
                }
            }

            tr <- tr + 1

        }

        if (class(gam_obj_site)[1] == "try-error") {
            print(paste("Error in fitting the RegionalGAM for species", as.character(sp_data_all$SPECIES[1]), "and year", sp_data_all$M_YEAR[1],
                    "; Model did not converge after", tr, "trials"))
            sp_data_all[, c("FITTED", "NM") := .(NA, NA)]
        } else {
            sp_data_all[, FITTED := mgcv::predict.gam(gam_obj_site, newdata = sp_data_all[, c("trimDAYNO", "SITE_ID")], type = "response")]
            sp_data_all[M_SEASON == 0L, FITTED := 0]

            if(sum(is.infinite(sp_data_all[, FITTED])) > 0){
                sp_data_all[, c("FITTED", "NM") := .(NA, NA)]
            } else {
                sp_data_all[, SITE_SUM := sum(FITTED), by = SITE_ID]
                sp_data_all[, NM := round(FITTED / SITE_SUM, 5)]
            }
        }

        f_curve <- sp_data_all[, .(SPECIES, DATE, WEEK, WEEK_DAY, DAY_SINCE, M_YEAR, M_SEASON, trimDAYNO,NM)]
        data.table::setkey(f_curve)
        f_curve <- unique(f_curve)

        f_curve_mod <- list(f_curve = f_curve, f_model = gam_obj_site, f_data = sp_data_all)

    return(f_curve_mod)
}


#' flight_curve
#' Compute the annual flight curve from butterfly count data collated across multiple sites.
#' @param ts_season_count data.table with complete time series of count and season information returned by \link{ts_monit_count_site}
#' @param NbrSample integer setting the maximum number of site to use to compute the flight curve, default=100.
#' @param MinVisit integer setting the minimum number of visit required for a site to included in the computation, default=3.
#' @param MinOccur integer setting the minimum number of positive records (e.g. >= 1) observed over the year in a site default=2.
#' @param MinNbrSite integer setting the minimum number of site required to compute the flight curve, default=1.
#' @param MaxTrial integer setting the maximum number of trial to reach convergence of the model, default=3.
#' @param FcMethod string defining the method to be used for computation of the flight curve, default='regionalGAM' (no other method is available yet).
#' @param GamFamily string setting the distribution of the error term in the GAM, default='poisson', but can be 'nb' or 'quasipoisson'.
#' @param CompltSeason Logical to restrict computation of flight curve for years where the complete season has been sampled, default=TRUE.
#' @param SelectYear integer to select a specific year to compute the flight curve, default=NULL.
#' @param SpeedGam Logical to use the \link[mgcv]{bam} method instead of the \link[mgcv]{gam} method.
#' @param OptiGam Logical to set use bam when data are larger than 100 and gam for smaller dataset.
#' @param KeepModel Logical to keep model output in a list object named \code{flight_curve_model}.
#' @param KeepModelData Logical to keep the data used for the GAM.
#' @param ... additional parameters passed to gam or bam function from the \link[mgcv]{gam} package.
#' @return A list with three objects, i) **pheno**: a vector with annual flight curves \code{f_pheno} with expected relative abudance, normalize to sum to one over a full season,
#'         ii) **model**: a list of the resulting gam models \code{f_model} fitted on the count data for each year and iii) **data**: a data.table with the data used to fit the GAM model.
#' @keywords gam, flight curve
#' @seealso \link{fit_gam}
#' @seealso \link[mgcv]{gam}
#' @seealso \link[mgcv]{bam}
#' @author Reto Schmucki - \email{reto.schmucki@@mail.mcgill.ca}
#' @import data.table
#' @export flight_curve
#'

flight_curve <- function(ts_season_count, NbrSample = 100, MinVisit = 3, MinOccur = 2, MinNbrSite = 1, MaxTrial = 3, FcMethod = 'regionalGAM',
                            GamFamily = 'poisson', CompltSeason = TRUE, SelectYear = NULL, SpeedGam = TRUE, OptiGam = TRUE, KeepModel = TRUE, KeepModelData = TRUE, ...) {

        check_package('data.table')

        names(ts_season_count) <- toupper(names(ts_season_count))
        check_names(ts_season_count,c("COMPLT_SEASON", "M_YEAR", "SITE_ID", "SPECIES", "DATE", "WEEK", "WEEK_DAY", "DAY_SINCE", "M_SEASON", "COUNT", "ANCHOR"))

        if(isTRUE(CompltSeason)){
            ts_season_count <- ts_season_count[COMPLT_SEASON == 1]
        }

        # if(exists("f_pheno")){
        #     rm(f_pheno)
        # }

        if(is.null(SelectYear)){
            year_series <- ts_season_count[, unique(as.integer(M_YEAR))]
        } else {
            year_series <- ts_season_count[M_YEAR %in% SelectYear, unique(as.integer(M_YEAR))]
        }

        f_pheno <- data.table::data.table()
        f_data  <- data.table::data.table()
        f_model <- list()
        
        for (y in year_series) {

            dataset_y <- ts_season_count[as.integer(M_YEAR) == y, .(SPECIES, SITE_ID, DATE, WEEK, WEEK_DAY, DAY_SINCE, M_YEAR, M_SEASON, COUNT, ANCHOR)]
            dataset_y[, trimDAYNO := DAY_SINCE - min(DAY_SINCE) + 1]

            ## filter for site with at least x visits and x occurrences
            visit_occ_site <- merge(dataset_y[!is.na(COUNT) & ANCHOR == 0L, .N, by=SITE_ID], dataset_y[!is.na(COUNT) & ANCHOR == 0L & COUNT > 0, .N, by=SITE_ID], by="SITE_ID", all=TRUE)
            dataset_y <- data.table::copy(dataset_y[SITE_ID %in% visit_occ_site[N.x >= MinVisit & N.y >= MinOccur, SITE_ID],])

            if(dataset_y[,uniqueN(SITE_ID)] < MinNbrSite){
                dataset_y <- ts_season_count[as.integer(M_YEAR) == y, .(SPECIES, DATE, WEEK, WEEK_DAY, DAY_SINCE, M_YEAR, M_SEASON)]
                dataset_y[, trimDAYNO := DAY_SINCE - min(DAY_SINCE) + 1]
                f_curve <- dataset_y[, NM := NA]
                data.table::setkey(f_curve, SPECIES, DAY_SINCE)
                f_curve <- unique(f_curve)
                f_curve_mod <- list(f_curve=f_curve, f_model=NA)
                print(paste("You have not enough sites with observations for estimating the flight curve for species", as.character(dataset_y$SPECIES[1]), "in", dataset_y$M_YEAR[1]))
            } else {
                if(FcMethod=='regionalGAM'){
                    f_curve_mod <- fit_gam(dataset_y, NbrSample = NbrSample, GamFamily = GamFamily, MaxTrial = MaxTrial,
                                            SpeedGam = SpeedGam, OptiGam = OptiGam, KeepModel = KeepModel, ...)
                } else {
                    print("ONLY the regionalGAM method is available so far!")
                }
            }


            f_pheno <- rbind(f_pheno, f_curve_mod$f_curve)

            if(isTRUE(KeepModel)){
              f_model_2 <- list(f_curve_mod$f_model)
              names(f_model_2) <- paste0('FlightModel_', gsub(' ', '_', as.character(dataset_y$SPECIES[1])), '_', dataset_y$M_YEAR[1])
              f_model <- c(f_model, f_model_2)
            }

            if(isTRUE(KeepModelData)){
              f_data <- rbind(f_data, data.table::data.table(f_curve_mod$f_data))
            }

        }

    if(!isTRUE(KeepModelData) & !isTRUE(KeepModel)){
          result_fc <- list(pheno = f_pheno)
        }

    if(!isTRUE(KeepModelData) & isTRUE(KeepModel)){
          result_fc <- list(pheno = f_pheno, model = f_model)
        }

    if(isTRUE(KeepModelData) & isTRUE(KeepModel)){
          result_fc <- list(pheno = f_pheno, model = f_model, data = f_data)
        }

    return(result_fc)
}



#' check_pheno
#' Check for the flight curve of a specific year and if missing, impute the nearest available within a span of 5 years.Function used in \link{impute_count}.
#' @param sp_count_flight_y data.table with the flight curve, relative abundance (NM), for a specific year.
#' @param sp_count_flight data.table with the flight curves, relative abundance (NM), for all years available for search as returned by \link{flight_curve}.
#' @return A data.table with time series of the expected relative abundance of butterfly count per day (NM) for the year or the nearest year where
#'         phenology is available.
#' @keywords flight curve
#' @seealso \link{impute_count}, \link{flight_curve}
#' @author Reto Schmucki - \email{reto.schmucki@@mail.mcgill.ca}
#' @import data.table
#' @export check_pheno
#'

check_pheno <- function(sp_count_flight_y, sp_count_flight){

        if(sp_count_flight_y[is.na(NM), .N] > 0){
            y_ <- unique(sp_count_flight_y[, as.integer(M_YEAR)])
            tr <- 1
            z <- rep(1:5, rep(2, 5)) * c(-1, 1)
            search_op <- unique(sp_count_flight[, as.integer(M_YEAR)])
            valid_y <- c(y_ + z)[c(y_ + z) > min(search_op) & c(y_ + z) < max(search_op)]
            alt_flight <- unique(sp_count_flight[as.integer(M_YEAR) == y_, .(M_YEAR, trimDAYNO, NM)])

            while(alt_flight[is.na(NM), .N] > 0 & tr <= length(valid_y)){
                alt_flight <- unique(sp_count_flight[as.integer(M_YEAR) == valid_y[tr], .(M_YEAR, trimDAYNO, NM)])
                tr <- tr + 1
            }

            if(alt_flight[is.na(NM), .N] > 0){
                print(paste("No reliable flight curve available within a 5 year horizon of", sp_count_flight_y[1, M_YEAR, ]))

            } else {
                warning(paste("We used the flight curve of", alt_flight[1, M_YEAR], "to compute abundance indices for year", sp_count_flight_y[1, M_YEAR, ]))
                sp_count_flight_y[, trimDAYNO := DAY_SINCE - min(DAY_SINCE) + 1]
                data.table::setnames(alt_flight, 'NM', 'NMnew')
                alt_flight[, M_YEAR := NULL]
                data.table::setkey(sp_count_flight_y, trimDAYNO)
                data.table::setkey(alt_flight, trimDAYNO)
                sp_count_flight_y <- merge(sp_count_flight_y, alt_flight, by='trimDAYNO', all.x=TRUE)
                sp_count_flight_y[, NM := NMnew][, NMnew := NULL]
            }
        }

        return(sp_count_flight_y)

    }


#' fit_glm
#' Fit a Generalized Linear Model (GLM) to predict daily count per site, using the regional flight curve as offset. Function used in \link{impute_count}.
#' @param sp_count_flight_y data.table with time series of the expected relative abundance of butterfly count per day (NM) for the year of interest,
#'        or the nearest available.
#' @param non_zero vector of sites with non-zero value to be included in the model (see detail)
#' @param FamilyGlm string for the distribution to be used for the error term in the GLM, inherited from \link{impute_count}, default='quasipoisson'.
#' @return A a list of objects, i) **sp_count_flight_y**: data.table with data and expected relative abundance of butterfly count per day (NM) for the year or the nearest year where
#'         a fligh curve (phenology) is available \code{sp_count_flight_y} and ii) **glm_obj_site**:a glm object for the model \code{glm_obj_site}.
#' @details GLM model is only fitted for site with observations, non-zero, as the abundance for sites where count are only zeros is expected to be null
#' @keywords flight curve
#' @seealso \link{impute_count}, \link{flight_curve}
#' @author Reto Schmucki - \email{reto.schmucki@@mail.mcgill.ca}
#' @import data.table
#' @export fit_glm
#'

fit_glm <- function(sp_count_flight_y, non_zero, FamilyGlm){

            if(sp_count_flight_y[SITE_ID %in% non_zero,uniqueN(SITE_ID)] > 1){
                glm_obj_site <- try(glm(COUNT ~ factor(SITE_ID) + offset(log(NM)) -1, data = sp_count_flight_y[SITE_ID %in% non_zero, ],
                family = FamilyGlm, control = list(maxit = 100)), silent = TRUE)
            } else {
                glm_obj_site <- try(glm(COUNT ~ offset(log(NM)) -1, data = sp_count_flight_y[SITE_ID %in% non_zero, ],
                family = FamilyGlm, control = list(maxit = 100)), silent = TRUE)
            }

            if (class(glm_obj_site)[1] == "try-error") {

                sp_count_flight_y[SITE_ID %in% non_zero, c("FITTED","COUNT_IMPUTED") := .(NA, NA)]

                print(paste("Computation of abundance indices for year",sp_count_flight_y[1, M_YEAR,],
                            "failed with the RegionalGAM, verify the data you provided for that year"))
                # next()

            } else {
                sp_count_flight_y[SITE_ID %in% non_zero, FITTED := predict.glm(glm_obj_site, newdata = sp_count_flight_y[SITE_ID %in% non_zero, ], type = "response")]
            }

            sp_count_flight_mod_y <- list(sp_count_flight_y = sp_count_flight_y, glm_obj_site = glm_obj_site)

        return(sp_count_flight_mod_y)
    }


#' fit_glm.nb
#' Fit a Generalized Linear Model (GLM) to predict daily count per site, using the regional flight curve as offset and the negative binomial error distribution
#' as implemented in the package link[MASS]{glm.nb}. Function used in \link{impute_count}.
#' @param sp_count_flight_y data.table with time series of the expected relative abundance of butterfly count per day (NM) for the year of interest,
#'        or the nearest available.
#' @param non_zero vector of sites with non-zero value to be included in the model (see detail)
#' @return A a list of two objects, i) **sp_count_flight_y**: data.table with data and expected relative abundance of butterfly count per day (NM) for the year or the nearest year where
#'         a fligh curve (phenology) is available \code{sp_count_flight_y} and ii) **glm_obj_site**: a glm object for the model \code{glm_obj_site}.
#' @details GLM model is only fitted for site with observations, non-zero, as the abundance for sites where count are only zeros is expected to be null
#' @keywords flight curve
#' @seealso \link{impute_count}, \link{flight_curve}
#' @author Reto Schmucki - \email{reto.schmucki@@mail.mcgill.ca}
#' @import data.table
#' @export fit_glm.nb
#'

fit_glm.nb <- function(sp_count_flight_y, non_zero){

            if(sp_count_flight_y[SITE_ID %in% non_zero,uniqueN(SITE_ID)] > 1){
                glm_obj_site <- try(MASS::glm.nb(COUNT ~ factor(SITE_ID) + offset(NM), data=sp_count_flight_y[SITE_ID %in% non_zero, ]), silent = TRUE)
            } else {
                glm_obj_site <- try(MASS::glm.nb(COUNT ~ offset(NM) -1, data = sp_count_flight_y[SITE_ID %in% non_zero, ]), silent = TRUE)
            }

            if (class(glm_obj_site)[1] == "try-error") {
                sp_count_flight_y[SITE_ID %in% non_zero, c("FITTED", "COUNT_IMPUTED") := .(NA,NA)]

                print(paste("Computation of abundance indices for year", sp_count_flight_y[1, M_YEAR, ],
                "failed with the RegionalGAM, verify the data you provided for that year"))

                # next()

            } else {
                sp_count_flight_y[SITE_ID %in% non_zero, FITTED := predict(glm_obj_site, newdata = sp_count_flight_y[SITE_ID %in% non_zero, ], type = "response")]
            }

            sp_count_flight_mod_y <- list(sp_count_flight_y = sp_count_flight_y, glm_obj_site = glm_obj_site)

        return(sp_count_flight_mod_y)
    }


#' impute_count
#' Fit a Generalized Linear Model (GLM) to predict daily count per site, using the regional flight curve as offset.
#' @param ts_season_count data.table with time series of counts for a specific species across all sites as returned by \link{ts_monit_count_site}.
#' @param ts_flight_curve data.table with the flight curves, relative abundance (NM), for a specific species as returned by \link{flight_curve}.
#' @param FamilyGlm string for the distribution to be used for the error term in the GLM, default='quasipoisson'.
#' @param CompltSeason logical to define if only years where a complete season is available should be modelled.
#' @param SelectYear vector of specific years of interest, can be a single value (e.g. 2015).
#' @param NearPheno Logical if flight curve from neirhest year should be used, if available within 5 years, default=TRUE
#' @param KeepModel Logical to keep model output in a list object named \code{imp_glm_model}
#' @return A a list of one or two objects, i) **impute_count**: data.table with observed and expected butterfly counts per day imputed based on the flight curve of the year or the nearest year where
#'         a phenology is available \code{sp_ts_season_count} and ii) **model**: a glm object for the GLM model \code{glm_model}.
#' @details GLM model is only fitted for site with observations, non-zero, as the abundance for sites where count are only zeros is expected to be null.
#' @keywords flight curve
#' @seealso \link{fit_glm}, \link{fit_glm.nb}, \link{flight_curve}
#' @author Reto Schmucki - \email{reto.schmucki@@mail.mcgill.ca}
#' @import data.table
#' @export impute_count
#'

impute_count <- function(ts_season_count, ts_flight_curve, FamilyGlm = quasipoisson(), CompltSeason = TRUE,
                                    SelectYear = NULL, KeepModel = TRUE, NearPheno = TRUE) {

        if(ts_season_count$SPECIES[1] != ts_flight_curve$SPECIES[1]){
            stop('Species in count data and flight curve must be the same!')
        }

        if(FamilyGlm[1]=='nb'){
            stop('Negative binomial distribution for GLM is not resolved, please use quasipoisson distribution instead')
        }

        check_package('data.table')

        if(isTRUE(CompltSeason)){
            ts_season_count <- ts_season_count[COMPLT_SEASON==1]
        }

        sp_ts_season_count <- data.table::copy(ts_season_count)
        data.table::setkey(sp_ts_season_count, DATE)
        data.table::setkey(ts_flight_curve, DATE)
        sp_count_flight <- merge(sp_ts_season_count, ts_flight_curve[, .(DATE, trimDAYNO, NM)], all.x=TRUE)
        data.table::setkey(sp_count_flight, M_YEAR, DATE, SITE_ID)

        glmMet <- "glm()"

        if( FamilyGlm[1]=='nb'){
            glmMet <- "glm.nb()"
        }

        if(is.null(SelectYear)){
            year_series <- ts_season_count[, unique(as.integer(M_YEAR))]
        } else {
            year_series <- ts_season_count[M_YEAR %in% SelectYear, unique(as.integer(M_YEAR))]
        }

        i_glm_model <- list()

        for(y in year_series){

            sp_count_flight_y <-  data.table::copy(sp_count_flight[as.integer(M_YEAR) == y, ])

            if(isTRUE(NearPheno)){
                sp_count_flight_y <- check_pheno(sp_count_flight_y, sp_count_flight)
            }

            if(sp_count_flight_y[is.na(NM) & trimDAYNO != 366, .N] > 0){
                print(paste("No glm model will be fitted for", sp_count_flight_y[1, M_YEAR]))
            } else {
                print(paste("Computing abundance indices for", sp_count_flight_y[1, SPECIES], "in", sp_count_flight_y[1, M_YEAR], "across",
                        sp_count_flight_y[,uniqueN(SITE_ID)], "sites, using", glmMet, ":", Sys.time()))
            }

            sp_count_flight_y[M_SEASON == 0L, COUNT := NA]
            sp_count_flight_y[M_SEASON != 0L & NM == 0, NM := 0.000001]
            non_zero <- sp_count_flight_y[, sum(COUNT, na.rm=TRUE), by=(SITE_ID)] [V1 > 0, SITE_ID]
            zero <- sp_count_flight_y[, sum(COUNT, na.rm=TRUE), by=(SITE_ID)] [V1 == 0, SITE_ID]

            if(length(non_zero) >= 1 & sp_count_flight_y[is.na(NM) & trimDAYNO != 366, .N] == 0){
                if(FamilyGlm[1] == 'nb'){
                    sp_count_flight_l <- fit_glm.nb(sp_count_flight_y, non_zero)
                } else {
                    sp_count_flight_l <- fit_glm(sp_count_flight_y, non_zero, FamilyGlm)
                }
            } else {
               sp_count_flight_l <- list(sp_count_flight_y = sp_count_flight_y,
                                    glm_obj_site = paste('No glm fitted for', sp_count_flight_y[1, M_YEAR]))
            }

            sp_count_flight_y <- sp_count_flight_l$sp_count_flight_y

            sp_count_flight_y[SITE_ID %in% zero, FITTED := 0]
            sp_count_flight_y[is.na(COUNT), COUNT_IMPUTED := FITTED][!is.na(COUNT), COUNT_IMPUTED := as.numeric(COUNT)] [M_SEASON == 0L, COUNT_IMPUTED := 0]

            data.table::setkey(sp_ts_season_count, SITE_ID, DAY_SINCE)
            data.table::setkey(sp_count_flight_y, SITE_ID, DAY_SINCE)

            if("FITTED" %in% names(sp_ts_season_count)){
                sp_ts_season_count[sp_count_flight_y, ':=' (trimDAYNO=i.trimDAYNO, NM=i.NM, FITTED=i.FITTED, COUNT_IMPUTED=i.COUNT_IMPUTED)]
            } else {
                sp_ts_season_count <- merge(sp_ts_season_count, sp_count_flight_y[, .(DAY_SINCE, SITE_ID, trimDAYNO, NM, FITTED, COUNT_IMPUTED)], all.x = TRUE)
            }

            if(isTRUE(KeepModel)){
                    glm_model <- list(sp_count_flight_l$glm_obj_site)
                    names(glm_model) <- paste0('glm_mod_', gsub(' ', '_', sp_count_flight_y[1, SPECIES]), '_', sp_count_flight_y[1, M_YEAR])
                    i_glm_model <- c(i_glm_model, glm_model)
                }
            }


        if(!is.null(SelectYear)){
            sp_ts_season_count <- sp_ts_season_count[M_YEAR %in% SelectYear, ]
        } else {
            sp_ts_season_count <- sp_ts_season_count
        }


        if(isTRUE(KeepModel)){
          return(list(impute_count = sp_ts_season_count, model = i_glm_model))
        } else {
          return(list(impute_count = sp_ts_season_count))
        }
}


#' butterfly_day
#' count cumulative butterfly count observed over one monitoring season.
#' @param sp_ts_season_count list of objects, including a data.table with observed and expected butterfly counts per day imputed for each sites based by \link{impute_count}.
#' @param WeekCount logical defining if butterfly day should be counted by week (default), using the 4th day of the week, or as a total of predicted daily counts.
#' @return data.table with total butterfly day observed per species, year, and site.
#' @keywords butterfly count
#' @seealso \link{impute_count}, \link{flight_curve}
#' @author Reto Schmucki - \email{reto.schmucki@@mail.mcgill.ca}
#' @import data.table
#' @export butterfly_day
#'

butterfly_day <- function(sp_ts_season_count, WeekCount = TRUE){
            if (WeekCount == TRUE){
                b_day <- site_year_sp_count$impute_count[COMPLT_SEASON == 1 & M_SEASON != 0 & WEEK_DAY == 4, FITTED, by = .(SITE_ID, M_YEAR, WEEK)][,sum(FITTED), by = .(SITE_ID, M_YEAR)]
            } else {
                b_day <- site_year_sp_count$impute_count[COMPLT_SEASON == 1 & M_SEASON != 0, FITTED, by = .(SITE_ID, M_YEAR, WEEK)][,sum(FITTED), by = .(SITE_ID, M_YEAR)]
            }
            
            data.table::setnames(b_day,"V1","BUTTERFLY_DAY")
            
        return(b_day)
    }

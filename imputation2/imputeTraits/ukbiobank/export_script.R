export_function <- function (uniqueID, moduleDir, outputDir, gtool) {
    if (!file.exists(outputDir)) {
        stop(paste("Did not find a output data with this id", uniqueID))
    }
    suppressWarnings(dir.create(file.path(outputDir, "table_out")))
    suppressWarnings(dir.create(file.path(outputDir, "table_out/ukbiobank")))

    snps_file <- paste0(moduleDir, "/ukbiobank/2017-09-28_semi_curated_version_ukbiobank.rdata")
    trait_file <- paste0(moduleDir, "/ukbiobank/2017-09-28_trait_overoverview.rdata")
    load(snps_file)
    load(trait_file)
    traits <- traits[!traits[, "omit"], ]

    output <- list()
    # output[["documentation"]] <- list()
    # output[["documentation"]][["trait_overview"]] <- "https://github.com/lassefolkersen/impute-me/blob/15ce6cb5a25dfe42f5cdf6c2010b7e3a8af53f18/ukbiobank/2017-09-28_trait_overoverview.rdata"
    # output[["documentation"]][["snp_file"]] <- "https://github.com/lassefolkersen/impute-me/blob/master/ukbiobank/2017-09-28_semi_curated_version_ukbiobank.rdata"

    # get ethnicity parameter
    pDataFile <- paste(outputDir, "/pData.txt", sep = "")
    pData <- try(read.table(pDataFile, header = TRUE, stringsAsFactors = FALSE, sep = "\t"))
    if (class(pData) != "try-error" && "ethnicity" %in% colnames(pData)) {
        ethnicity <- pData[1, "ethnicity"]
    } else {
        ethnicity <- "global"
    }

    for (study_id in rownames(traits)) {
        SNPs_to_analyze <- data[data[, "study_id"] %in% study_id, ]
        # filter with P-value treshold = 10^-7
        snp_p_value <- 7
        SNPs_to_analyze <- SNPs_to_analyze[SNPs_to_analyze[,"P.VALUE"] < 10^ -snp_p_value,]
        # get genotypes
        SNPs_requested <- SNPs_to_analyze[!duplicated(SNPs_to_analyze[, "SNP"]), ]
        rownames(SNPs_requested) <- SNPs_requested[, "SNP"]
        genotypes <- get_genotypes(uniqueID = uniqueID, request = SNPs_requested, gtool = gtool, destinationDir = outputDir, namingLabel = "cached.all_gwas")
        # get correct ethnicity minor_allele_frequency
        if (ethnicity %in% c("EAS", "AMR", "AFR", "EUR", "SAS")) {
            SNPs_requested[, "minor_allele_freq"] <- SNPs_requested[, paste0(ethnicity, "_AF")]
        }
        # calculate GRS
        snp_data <- SNPs_requested
        snp_data[, "genotype"] <- genotypes[rownames(snp_data), "genotype"]
        snp_data <- get_GRS_2(snp_data, mean_scale = TRUE, unit_variance = TRUE)
        population_sum_sd <- sqrt(sum(snp_data[, "population_score_sd"]^2, na.rm = TRUE))
        GRS_beta <- sum(snp_data[, "score_diff"], na.rm = TRUE) / population_sum_sd
        # calculate percentage
        percentage <- floor(pnorm(GRS_beta, mean = 0, sd = 1)*100)
        # calculate risk-allele
        c1 <- apply(SNPs_to_analyze[,c("minor_allele","major_allele","effect_allele","non_effect_allele")]=="?", 1, sum)

        # gather some background info for the study
        trait <- traits[study_id, "trait"]
        sampleSize_case <- unique(SNPs_to_analyze[, "case_count"])
        sampleSize_control <- unique(SNPs_to_analyze[, "control_count"])

        # message
        textToReturn <- paste0("Ethnicity-corrected trait Z-score is ", signif(GRS_beta, 2))
        textToReturn <- paste0(textToReturn, " This genetic risk score is higher than ", percentage, "% of the general population.")
        if (!is.na(percentage)) {
            if (percentage < 20){
                textToReturn <- paste0(textToReturn, " This is a low score.")
            } else if (percentage > 90){
                textToReturn <- paste0(textToReturn, " This is a high score. But keep in mind that additional calculation is necessary to determine a real life-time risk. For example having a very high genetic score for something that is not very heritable may make very little difference. These additional calculations typically require further studies, not always available.")
            } else {
                textToReturn <- paste0(textToReturn, " This is a fairly average score.")
            }
        }
        textToReturn <- paste0(textToReturn, " Result from the analysis of ", nrow(SNPs_to_analyze)," SNPs from the UK biobank, which were reported to be associated with ", tolower(trait), "(field code: ", sub("_ukbiobank$","",study_id),").")
        textToReturn <- paste0(textToReturn," The summary statistics were calculated by Neale lab (http://www.nealelab.is/blog/2017/7/19/rapid-gwas-of-thousands-of-phenotypes-for-337000-samples-in-the-uk-biobank) and reports a total sample size of ",sampleSize_case," cases and ", sampleSize_control," controls as downloaded on 2017-09-15.")

        output[[sub("_ukbiobank$","",study_id)]] <- list()
        output[[sub("_ukbiobank$","",study_id)]][["GRS"]] <- GRS_beta
        output[[sub("_ukbiobank$","",study_id)]][["trait"]] <- tolower(trait)
        output[[sub("_ukbiobank$","",study_id)]][["percentage"]] <- percentage
        output[[sub("_ukbiobank$","",study_id)]][["pop_sd"]] <- population_sum_sd
        output[[sub("_ukbiobank$","",study_id)]][["message"]] <- textToReturn
        
        ### save snp table
        # summarising allele info into single-columns
        snp_data[, "Effect/non-effect Allele"] <- paste(
            snp_data[, "effect_allele"], snp_data[, "non_effect_allele"], sep="/"
        )
        snp_data[, "Major/minor Allele"] <- paste(
            snp_data[, "major_allele"], snp_data[, "minor_allele"], sep="/"
        )
        # rounding MAF
        snp_data[, "minor_allele_freq"] <- signif(snp_data[, "minor_allele_freq"], 2)
        # marking duplicates
        for (col in c("genotype", "personal_score", "score_diff")) {
            snp_data[is.na(snp_data[, col]), col] <- ""
        }
        # round P.VALUE and effect size
        snp_data[, "effect_size"] <- signif(snp_data[, "effect_size"], 2)
        snp_data[, "P.VALUE"] <- signif(snp_data[, "P.VALUE"], 2)
        keep <- c(
            "SNP", "genotype", "Effect/non-effect Allele", "personal_score", "score_diff",
            "effect_size", "P.VALUE", "Major/minor Allele", "minor_allele_freq"
        ) 
        snp_data <- snp_data[, keep]
        colnames(snp_data) <- c(
            "SNP", "Your Genotype", "Effect/ non-effect Allele", "SNP-score", "SNP-score (population normalized)",
            "Effect Size", "P-value", "Major/ minor Allele", "Minor Allele Frequency"
        )
        write.table(snp_data, paste0(outputDir, "/table_out/ukbiobank/", study_id, ".txt"), 
                    sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)
    }
    return(output)
}

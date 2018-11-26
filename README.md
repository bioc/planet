plmec
=====

`plmec` is an R package for inferring ethnicity from placental DNA
methylation microarray data.

Installation
------------

    library(devtools)
    install_github('wvictor14/plmec')

Usage
-----

### Example Data

For demonstration purposes, I downloaded a [placental DNAm dataset from
GEO](https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE75196), which
contains samples collected in an Australian population. To save on
memory, I only use 8/24 samples, which I have saved in this repo as a
`minfi::RGChannelSet` object.

    library(plmec)
    library(minfi)      # for normalization
    library(wateRmelon) # for normalization
    library(ggplot2)    

    data(pl_rgset)
    pl_rgset # 8 samples

    ## class: RGChannelSet 
    ## dim: 622399 8 
    ## metadata(0):
    ## assays(2): Green Red
    ## rownames(622399): 10600313 10600322 ... 74810490 74810492
    ## rowData names(0):
    ## colnames(8): GSM1944959_9376561070_R05C01
    ##   GSM1944960_9376561070_R06C01 ... GSM1944965_9376561070_R05C02
    ##   GSM1944966_9376561070_R06C02
    ## colData names(0):
    ## Annotation
    ##   array: IlluminaHumanMethylation450k
    ##   annotation: ilmn12.hg19

### Preprocessing data

Ideally, your data should be normalized in the same manner as the
training data used to develop the ethnicity-predictive model. If IDATs
are supplied, you can apply both
[noob](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3627582/) and
[BMIQ](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3546795/)
normalization. If only methylated and unmethylated data matrices are
available, you can apply just BMIQ. If neither are available, then you
can still run the algorithm but any differences resulting from the
different normalizations may impact accuracy.

To apply normalization, run `minfi::preprocessNoob()` and then
`wateRmelon::BMIQ()`:

    pl_noob <- preprocessNoob(pl_rgset)
    pl_bmiq <- BMIQ(pl_noob)

Combine the methylation data with the 65 snp probe data (59 SNPs, if
using EPIC):

    pl_snps <- getSnpBeta(pl_rgset)
    pl_dat <- rbind(pl_bmiq, pl_snps)
    dim(pl_dat) # 485577     8

    ## [1] 485577      8

### Infer ethnicity

The reason we added the snp data onto the betas matrix was because a
subset of those are used to predict ethnicity. The input data needs to
contain all 1860 features in the final model. We can check our data for
these features with the `pl_ethnicity_features` vector:

    all(pl_ethnicity_features %in% rownames(pl_dat))

    ## [1] TRUE

You don't need to subset to these 1860 features before running
`pl_ethnicity_infer()` to obtain ethnicity calls:

    dim(pl_dat)

    ## [1] 485577      8

    results <- pl_infer_ethnicity(pl_dat)

    ## [1] "1862 of 1862 predictors present."

    print(results, row.names = F)

    ##                     Sample_ID Predicted_ethnicity_nothresh
    ##  GSM1944959_9376561070_R05C01                        Asian
    ##  GSM1944960_9376561070_R06C01                    Caucasian
    ##  GSM1944961_9376561070_R01C02                        Asian
    ##  GSM1944962_9376561070_R02C02                    Caucasian
    ##  GSM1944963_9376561070_R03C02                    Caucasian
    ##  GSM1944964_9376561070_R04C02                    Caucasian
    ##  GSM1944965_9376561070_R05C02                    Caucasian
    ##  GSM1944966_9376561070_R06C02                    Caucasian
    ##  Predicted_ethnicity Prob_African   Prob_Asian Prob_Caucasian Highest_Prob
    ##                Asian 0.0112982105 0.9605469454     0.02815484    0.9605469
    ##            Caucasian 0.0141716320 0.1378094537     0.84801891    0.8480189
    ##                Asian 0.0203947583 0.8997959733     0.07980927    0.8997960
    ##            Caucasian 0.0007587289 0.0007417092     0.99849956    0.9984996
    ##            Caucasian 0.0026096978 0.0033276436     0.99406266    0.9940627
    ##            Caucasian 0.0068106571 0.0121663549     0.98102299    0.9810230
    ##            Caucasian 0.0018656109 0.0020215270     0.99611286    0.9961129
    ##            Caucasian 0.0009633902 0.0014314017     0.99760521    0.9976052

Note the two columns `Predicted_ethnicity_nothresh` and
`Predicted_ethnicity`. The latter refers to the classification which is
determined by the highest class-specific probability. The former first
applies a cutoff to the highest class-specific probability to determine
if a sample can be confidently classified to a single ethnicity group.
If a sample fails this threshold, this indicates mixed ancestry, and the
sample is given an `Ambiguous` label. The default threshold is 0.75.

    qplot(data = results, x = Prob_Caucasian, y = Prob_African, 
         col = Predicted_ethnicity, xlim = c(0,1), ylim = c(0,1))

![](README_files/figure-markdown_strict/plot_results-1.png)

    qplot(data = results, x = Prob_Caucasian, y = Prob_Asian, 
         col = Predicted_ethnicity, xlim = c(0,1), ylim = c(0,1))

![](README_files/figure-markdown_strict/plot_results-2.png)

\*For the entire dataset (not just the subset shown here), 22/24 were
predicted Caucasian and 2/24 Asian.

We can't compare this to self-reported ethnicity as it is unavailable.
But we know these samples were collected in Sydney, Australia, and are
therefore likely mostly European with some Asian ancestries.

    table(results$Predicted_ethnicity)

    ## 
    ##     Asian Caucasian 
    ##         2         6

### Adjustment in differential methylation analysis

Because 'Ambiguous' samples might have different mixtures of ancestries,
it might be inaccurate to adjust for them as one group in an analysis of
admixed populations. (In retrospect, I should have called samples
`African/Asian`, `African/Caucasian`, `Asian/Caucasian` as opposed to
all as `Ambiguous`). Instead, I recommend adjusting for the actual
probabilities in a linear modelling analysis, and to use only 2/3 of the
probabilities, since the third will be redundant (probabilities sum to
1).
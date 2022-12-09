# smrs_popn_dist

This repository contains code to demonstrate:- 
1. Summarising an individual-level participant data (IPD) dataset - [Scripts/01_summarise_ipd.R]
2. Simulating an IPD dataset from summaries - [Scripts/02_simulate_popn.R]

The two scripts are complementary.
01. Starts with an IPD dataset [Data/fake_ipd.csv] and summarises this (see [Outputs/])
02. Starts with the summaries and generates [Data/fake_ipd.csv]

## Normalisation step

For continuous variables, each variable is converted to a standard normal distribution using ordered quantile normalisation. See the [bestNormalize package vignette](https://cran.r-project.org/web/packages/bestNormalize/vignettes/bestNormalize.html) for details.

The code stores a set of original values and corresponding transformed values to allow subsequent "back-transformation" (ie recovery) of the original values [Outputs/quantiles_to_untransform.csv]. The algorithm for back transformation is non-parametric; it uses the observed relationship between the original and normalised variable. Where any values requiring to be back-transformed are not present in this set of values the relationship is obtained by simple linear interpolation (via the `approx()` function in R). Therefore, in order to obtain a set of values which capture the relationship in the fewest number of data points, we used the  Ramer–Douglas–Peucker (RDP) algorithm. The RDP algorithm was designed to reduce the number of points needed represent a polygon, and so could be used to represent the curve describing the relationship between the original and normalised values with fewer points. This algorithm trades off error (in the form of deviations from the curve) against the required number number of points. We ran a simple loop (`while()` function in R) to obtain a level of error wherein the curve was represented by 10 or fewer points per variable.

## Summarisation step

The categorical variables are summarised as simple counts. There is one row per unique combination of categorical variables. For this example data, this corresponds to around 500 rows summarising data for around 100,000 patients and are stored in the csv files ([Outputs/unique_comb_categorical_variables_count.csv] and [Outputs/unique_comb_categorical_variables_lkp.csv]).

Within the unique combinations of the categorical variables, the joint distributions of the (normalised) continuous variables are summarised as the mean and standard deviation (which can be higher or lower than the overall population mean and standard deviations which will be zero and one respectively) and the correlation between these variables. These are stored in the csv files ([Outputs/continuous_variables_cor.csv] and
[Outputs/continuous_variables_mean_sd.csv])

## Simulation step

IPD are simulated based on:-
 a) The count of the number of individuals with each combination of categorical variables ([Outputs/unique_comb_categorical_variables_count.csv])
 b) The means, SDs and correlations for the continuous variables for each combination of categorical variables ([Outputs/continuous_variables_cor.csv] and
[Outputs/continuous_variables_mean_sd.csv]).
 
The IPD are simulated by sampling from a multivariate normal distribution for each of the approximately 500 unique combinations of categorical variables. This gives around 100,000 simulated individuals.

## Back transformation step

Finally, for the entire set of around 100,000 simulated individuals, we back transform the continuous variables onto the original distributions using the set of original values and corresponding transformed values. The method for doing so is described in the normalisation step.

## ordernorm.R

Since the [bestNormalize package vignette](https://cran.r-project.org/web/packages/bestNormalize/vignettes/bestNormalize.html) package was not available for the versions of R on which this code was written, the functions were taken directly from the github repository. This script also contains the function ` Tform()` which performs the normalisation while also producing diagnostic plots to check the adequacy of the approximation to the curve describing the relationship between the original and normalised values.

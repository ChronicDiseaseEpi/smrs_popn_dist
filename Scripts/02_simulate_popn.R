library(tidyr)
library(dplyr)
library(purrr)
library(stringr)
library(readr)
library(ggplot2)
library(MASS)
library(Matrix)

## read in summary data  ----
catunq <- read_csv("Outputs/unique_comb_categorical_variables_count.csv")
catlkp <- read_csv("Outputs/unique_comb_categorical_variables_lkp.csv")
trgt_smry_con <- read_csv("Outputs/continuous_variables_mean_sd.csv")
trgt_smry_cor <- read_csv("Outputs/continuous_variables_cor.csv")
smry_cor <- read_csv("Outputs/summary_correlations_continuous.csv")
quants <- read_csv("Outputs/quantiles_to_untransform.csv")

## rename quants so matches transformed variable
quants <- quants %>% 
  mutate(varname = str_remove(varname, "_q$"))

## join data for running samples
trgt_smry <- catunq %>% 
  inner_join(trgt_smry_con) %>% 
  inner_join(trgt_smry_cor)
rm(catunq, trgt_smry_con, trgt_smry_cor)

## Nest data to allow looping over unique combinations of categorical variables
trgt_smry <- trgt_smry %>% 
  group_by(unq_id) %>% 
  nest() %>% 
  ungroup()

## make the components for the simulation. the correlations are currently in wide format
MakeCompSim <- function(a) {
  mns <- a[,str_detect(names(a), "_m$")]
  mns_v <- as.double(mns)
  names(mns_v) <- str_sub(names(mns), 1, -3)
  sds <- a[,str_detect(names(a), "_s$")]
  sds_v <- as.double(sds)
  names(sds_v) <- str_sub(names(sds), 1, -3)
  
  crs <- a[,str_detect(names(a), "\\:")]
  crs <- crs %>% 
    gather("var", "value") %>% 
    separate(var, into = c("row", "col"), sep = "\\:")
  crs <- bind_rows(crs,
                   crs %>% rename(col = row, row = col))
  crs <- bind_rows(crs,
                   crs %>% 
                     distinct(row) %>% 
                     mutate(col = row,
                            value = 1)) %>% 
    spread(col, value)
  crsrow <- crs$row
  crs <- as.matrix(crs %>% dplyr::select(-row))
  crs[] <- as.double(crs)
  rownames(crs) <- crsrow
  rm(mns, sds, crsrow)
  
  ## organise so columns and rows match
  crs <- crs[names(mns_v), names(mns_v)]
  sds_v <- sds_v[names(mns_v)]
  
  colnames(crs) == names(sds_v)
  rownames(crs) == colnames(crs)
  names(sds_v) == names(mns_v)
  cvs <- diag(sds_v) %*% crs %*% diag(sds_v)
  
  n <- if_else(a$n == "le10", sample(1:10, 1),  as.integer(a$n))
  list(n = n, mns = mns_v, sds = sds_v, crs = crs, cvs = cvs)
  
}
trgt_smry$components <- map(trgt_smry$data, MakeCompSim)

## Check properties of correlation and covariance matrices, following should be true
all(map_lgl(trgt_smry$components, ~ Matrix::isSymmetric(.x$crs)))
all(map_lgl(trgt_smry$components, ~ Matrix::isSymmetric(.x$cvs)))

## In case rounding etc caused the matrices not to be positive definite, use near PD function
trgt_smry$cvs <- map(trgt_smry$components, ~ Matrix::nearPD(.x$cvs)$mat)
trgt_smry$mns <- map(trgt_smry$components, ~ .x$mns)
trgt_smry$n <- map_int(trgt_smry$components, ~ .x$n)
trgt_smry$components <- NULL
trgt_smry$data <- NULL

## sample from distribution after checking that vector of means matrix match
if (all(map2_lgl(trgt_smry$mns, trgt_smry$cvs, ~ all(names(.x) == rownames(.y) ))) ) {
  trgt_smry$indiv <- pmap(list(trgt_smry$n, trgt_smry$mns, trgt_smry$cvs), function(n, m, cvs) {
    a <- MASS::mvrnorm(n, m, cvs) %>% 
      matrix(ncol = length(m)) 
    colnames(a) <- names(m)
    a %>% 
      as_tibble()
  })
}
## Unnest data to simulate a set of individuals
trgt_smry <- trgt_smry %>% 
  dplyr::select(-cvs, -mns) %>% 
  unnest(indiv)
cont_siml <- trgt_smry
rm(trgt_smry)

## rename to remove _t
names(cont_siml) <- str_remove(names(cont_siml), "_t$")


## Convert each back into original scale
for (varname in unique(quants$varname)) {
  print(varname)
  cont_siml[[varname]] <- approx(quants$tform_q[quants$varname == varname],
         quants$orig_q[quants$varname == varname],
         xout = cont_siml[[varname]], rule = 1)$y
}

## joing back to categorical data
siml_data <- catlkp %>% 
  inner_join(cont_siml) %>% 
  dplyr::select(-n, -unq_id)
write_csv(siml_data, "Data/fake_ipd.csv")

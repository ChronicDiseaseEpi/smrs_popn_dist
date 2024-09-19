library(tidyr)
library(dplyr)
library(purrr)
library(ggplot2)
library(stringr)
library(readr)
library(RDP)

source("Scripts/ordernorm.R")

## Read in IPD
targetpop <- read_csv("Data/fake_ipd.csv")
# targetpop <- targetpop %>% 
#   mutate(cardio = if_else(cvd == 1L, sample(size = nrow(.), 0:1, replace = TRUE), 0),
#          cerebr = if_else(cvd == 1 & cardio == 0, sample(size = nrow(.), 0:1, replace = TRUE), 0),
#          periph = cvd - cardio - cerebr)
# targetpop <- targetpop %>% 
#   select(-cvd)
write_csv(targetpop, "Data/fake_ipd.csv")
# list names of continuous and categorical variables
contvar <- c("age", "durn", "sbp", "dbp", "hba1c", "tchol", 
             "hdl", "egfr", "bmi", "ht")
catvar <- c("gndr", "ethnic", "insulin", "noninsulin", "metformin", "hf", 
            "cardio", "cerebr", "periph", "cursmok")

## create lookup table between unique combination of categorical variables and id
catlkp <- targetpop[, catvar] %>% 
  distinct() %>% 
  mutate(unq_id = 1:nrow(.))

## assign a unique rowid for unique combinations of categorical variables
targetpop <- targetpop %>% 
  inner_join(catlkp)

## drop categorical variables from main dataset
targetpop <- targetpop[ ,setdiff(names(targetpop), catvar)]

## count occurrence of each unique combination
catunq <- targetpop %>% 
  count(unq_id)

## transform all continuous variables using quantile normalisation
targetpop <- Tform(targetpop,
                   varnames = contvar,
                   eps = 0.01,
                   increment = 0.01, 
                   maxpts = 10)
## pull out quantiles, required for back transformation. Htese are stored as list columns for convenience in
## function
quants <- targetpop %>% 
  dplyr::select(ends_with("_q")) %>% 
  distinct() %>% 
  gather("varname", "res") 
quants$res <- map(quants$res, as_tibble)
quants <- bind_rows(quants) %>% 
  unnest(res)

## drop untransformed values, recovered values and lists of quantiles for transformation
targetpop <- targetpop[ , setdiff(names(targetpop), 
                                  c(contvar,
                                    paste0(contvar, "_q"),
                                    paste0(contvar, "_r")))]


## summarise continuous variables by mean and sd
trgt_smry_con <- targetpop %>%
  group_by(unq_id) %>%
  summarise_all(.funs = list(m = mean, s = sd), na.rm = TRUE) %>% 
  ungroup()

#Get correlation matrices for each combination
trgt_smry_cor <- targetpop %>%
  group_by(unq_id) %>%
  nest() %>%
  ungroup()
trgt_smry_cor$cor <- map(trgt_smry_cor$data, ~ cor(.x, use = "pairwise.complete.obs"))
trgt_smry_cor$cor <- map(trgt_smry_cor$cor, ~ .x %>% 
                           as_tibble(rownames = "rows") %>% 
                           gather("cols", "values", -rows))
trgt_smry_cor <- trgt_smry_cor %>% 
  dplyr::select(-data) %>% 
  unnest(cor)

## same correlation for age:hba1c as for hba1c age (etc) so only take one of each
forcomb <- trgt_smry_cor$cols %>% unique() %>% sort()
forcomb <- combn(forcomb, 2, simplify = FALSE)
forcomb <- map(forcomb, ~ tibble(rows = .x[1], cols = .x[2])) %>% bind_rows()
trgt_smry_cor <- trgt_smry_cor %>% 
  semi_join(forcomb) %>% 
  mutate(res = paste0(rows, ":", cols)) 
trgt_smry_cor <- trgt_smry_cor %>% 
  inner_join(catunq)
corplots <- ggplot(trgt_smry_cor %>% 
                     mutate(n_lvl = if_else(n > 20, "gt20", "le20")), aes(x = res, y = values)) +
  geom_violin(draw_quantiles = 0.5) +
  facet_wrap(~n_lvl) +
  coord_flip()
pdf("Outputs/Summary_of_correlations.pdf")
corplots
dev.off()
smry_cor <- trgt_smry_cor %>% 
  filter(n > 20) %>% 
  group_by(res) %>% 
  summarise(cor_m = mean(values), cor_s = sd(values)) %>% 
  ungroup()

## Apply disclosure control measures, rounding and summarising; then as required spread to wide
## replace NA correlations with a random sample from the distribution of correlations
# also round correlations to two decimal places
trgt_smry_cor <- trgt_smry_cor %>% 
  inner_join(smry_cor) %>% 
  mutate(values = if_else(is.na(values), rnorm(nrow(.), cor_m, cor_s), values),
         values = round(values, 2)) %>% 
  dplyr::select(-rows, -cols, -cor_m, -cor_s) %>% 
  spread(res, values) %>% 
  dplyr::select(-n)

# Deal with where SD = 0 as would allow someone to infer that n=1; also replace NAs for means
## function will replace missing values with the mean SD plus a small error (so cannot recover identical values)
## then round to two dp fr all continuous variables
ReplaceNaSd <- function(x) {
  if_else(is.na(x),
          mean(x, na.rm = TRUE) * runif(length(x), 0.95, 1.05),
          x)
}
trgt_smry_con[ , setdiff(names(trgt_smry_con), "unq_id")] <- map(trgt_smry_con[ , setdiff(names(trgt_smry_con), "unq_id")],
                                                                 ~ .x %>% ReplaceNaSd() %>% round(2))

## replace counts of <=10 with le10
catunq <- catunq %>% 
  mutate(n = if_else(n <= 10, "le10", as.character(n)))

## round quantiles
quants <- quants %>% 
  mutate(tform_q = round(tform_q, 2),
         orig_q = round(orig_q, 2))
write_csv(catunq, "Outputs/unique_comb_categorical_variables_count.csv")
write_csv(catlkp, "Outputs/unique_comb_categorical_variables_lkp.csv")
write_csv(trgt_smry_con, "Outputs/continuous_variables_mean_sd.csv")
write_csv(trgt_smry_cor, "Outputs/continuous_variables_cor.csv")
write_csv(smry_cor, "Outputs/summary_correlations_continuous.csv")
write_csv(quants, "Outputs/quantiles_to_untransform.csv")

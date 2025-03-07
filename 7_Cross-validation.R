## cross-validation for bbs models
#setwd("C:/GitHub/Spatial_hierarchical_trend_models")
#setwd( "C:/Users/SmithAC/Documents/GitHub/Spatial_Hierarchical_Trend_Models")

library(bbsBayes2)
library(tidyverse)


comparisons <- data.frame(species = c("Wood Thrush",
                                      "Eastern Whip-poor-will",
                                      "Eastern Whip-poor-will",
                                      "Carolina Wren",
                                      "Baird's Sparrow",
                                      "Baird's Sparrow",
                                      "Scissor-tailed Flycatcher",
                                      "Scissor-tailed Flycatcher",
                                      "Rufous Hummingbird",
                                      "Rufous Hummingbird",
                                      "Bewick's Wren",
                                      "Mountain Bluebird"),
                          sp_n = c(7550,
                                   4171,
                                   4171,
                                   7180,
                                   5450,
                                   5450,
                                   4430,
                                   4430,
                                   4330,
                                   4330,
                                   7190,
                                   7680),
                          model = c("gamye",
                                    "gamye",
                                    "first_diff",
                                    "first_diff",
                                    "first_diff",
                                    "gamye",
                                    "first_diff",
                                    "gamye",
                                    "first_diff",
                                    "gamye",
                                    "first_diff",
                                    "gamye"),
                          stratification = c("bbs_usgs",
                                             "bbs_usgs",
                                             "bbs_usgs",
                                             "bbs_usgs",
                                             "latlong",
                                             "latlong",
                                             "latlong",
                                             "latlong",
                                             "latlong",
                                             "latlong",
                                             "bbs_usgs",
                                             "bbs_usgs"))



# Data preparation for Cross-validation -----------------------------
# wd setting may be necessary to run outside of RStudio for more stable behaviour
#setwd( "C:/Users/SmithAC/Documents/GitHub/Spatial_Hierarchical_Trend_Models")

model_variants <- c("hier","spatial")

for(j in 1:nrow(comparisons)){
  
  
species <- comparisons[j,"species"]
sp_n <- comparisons[j,"sp_n"]
stratification <- comparisons[j,"stratification"]
model <- comparisons[j,"model"]

s <- stratify(stratification,species)
p <- prepare_data(s, min_n_routes = 1)
map<-load_map(stratify_by = stratification)
sp<-prepare_spatial(p,map)


#variant <- model_variants[1]



  m_spatial <- prepare_model(sp,model,
                         model_variant = "spatial",
                         calculate_cv = TRUE) 
  saveRDS(m_spatial,paste0("data/cv_prepared_",model,"_spatial_",sp_n,".rds"))
  
  m_hier <- prepare_model(p,model,
                             model_variant = "hier",
                             calculate_cv = TRUE) 
  saveRDS(m_hier,paste0("data/cv_prepared_",model,"_hier_",sp_n,".rds"))
         
  
  
}
  
   
  

# Fitting loop by species model variant -----------------------------------



for(j in 1:nrow(comparisons)){
  
  
  species <- comparisons[j,"species"]
  sp_n <- comparisons[j,"sp_n"]
  stratification <- comparisons[j,"stratification"]
  model <- comparisons[j,"model"]
  

#k <- # setting k to one of 1:10 in each separate R session
 for(k in 1:10){ 
  for(variant in model_variants){

m_sel <- readRDS(paste0("data/cv_prepared_",model,"_",variant,"_",sp_n,".rds"))
  m_tmp <- run_model(m_sel,
                     refresh = 500,
                     k = k,
                     save_model = FALSE)

  sum_cv <- get_summary(m_tmp,variables = "log_lik_cv")
  
  sum_cv <- sum_cv %>%
    mutate(original_count_index = m_tmp$model_data$test)
  
  saveRDS(sum_cv,paste0("output/cv_sum_",sp_n,"_",model,"_",variant,"_",k,".rds"))
  
  print(paste(model,variant,k))
  
}

}

  
}


# compile cv results ------------------------------------------------------


# Loop over species and model comparisons ---------------------------------




model_variants <- c("hier","spatial")
sum_cv <- NULL
cv_wide <- NULL
for(i in 1:nrow(comparisons)){

  species <- comparisons[i,"species"]
  sp_n <- comparisons[i,"sp_n"]
  model <- comparisons[i,"model"]
  

for(variant in model_variants){
  m_sel <- readRDS(paste0("data/cv_prepared_",model,"_",variant,"_",sp_n,".rds"))
  raw_data <- m_sel$raw_data %>% 
    mutate(folds = m_sel$folds,
           original_count_index = row_number())
  sum_cv1 <- NULL
  for(k in 1:10){
    
    sum_cv_tmp <- readRDS(paste0("output/cv_sum_",sp_n,"_",model,"_",variant,"_",k,".rds"))
    
    sum_cv1 <- bind_rows(sum_cv1,sum_cv_tmp)
    
  }
  
  
    
  sum_cv1 <- sum_cv1 %>% 
    inner_join(.,raw_data,
               by = "original_count_index") %>% 
    mutate(model_variant = variant,
           model = model,
           species = species,
           sp_n = sp_n)

  cv_wide_t <- sum_cv1 %>% 
    select(mean,original_count_index,
           strata_name,year,route,count) %>% 
    rename_with(.,~gsub(x = .x,"mean",paste(variant,"lppd",sep = "_"))) %>% 
    mutate(species = species,
           model = model,
           sp_n = sp_n)
  
  sum_cv <- bind_rows(sum_cv,sum_cv1)

  if(variant == model_variants[1]){
    cv_wide_s <- cv_wide_t
  }else{
  cv_wide_s <- left_join(cv_wide_s,cv_wide_t)
  }
  
}

cv_wide <- bind_rows(cv_wide,cv_wide_s)

 

}#end i loop



# summed lppd by species model variant
totals <- sum_cv %>% 
  group_by(model_variant,model,species) %>% 
  summarise(sum_lppd = sum(mean),
            mean_lppd = mean(mean),
            sd_lppd = sd(mean)) %>% 
  arrange(model,species)

# point-wise differences spatial - hierarchical (so positive = higher lppd with spatial)
diffs <- cv_wide %>%
  mutate(diff_lppd = spatial_lppd - hier_lppd)
# simple summary of species and model differences including approximate z-score
# positive values = support for spatial model.
sp_diff_summary <- diffs %>% 
  group_by(species,model) %>% 
  summarise(mean = mean(diff_lppd),
            sd = sd(diff_lppd),
            n = n(),
            z = mean/(sd/sqrt(n)),
            .groups = "keep")


diff_sum_stratum <- diffs %>% 
  # filter(species == "Baird's Sparrow",
  #        model == "first_diff",
  #        year > 1990) %>% 
  group_by(strata_name, species, model) %>% 
  summarise(mean_diff = mean(diff_lppd),
            n = n(),
            sd_diff = sd(diff_lppd),
            z_diff = mean_diff/(sd(diff_lppd)/sqrt(n)))

map<-load_map(stratify_by = stratification)

diff_map <- map %>% 
  inner_join(diff_sum_stratum,
             by = "strata_name")
diff_map_plot <- ggplot()+
  geom_sf(data = diff_map,
          aes(fill = z_diff))+
  colorspace::scale_fill_continuous_diverging()+
  theme_bw()+
  facet_wrap(vars(model,species))
diff_map_plot


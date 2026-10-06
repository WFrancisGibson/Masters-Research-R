##########################################
#########  bCCNN: rolling-origin partitions of the annual triangle
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Figures 3 and 9;
#########  figure layout after the Department's Research Assignment Guide
#########  (2026), Sections 5.3 and 5.7
##########################################

## reads the triangle written by "bCCNN fit.R" (no Keras needed)
source(here::here("analysis", "00_setup.R"))
fig_dir <- file.path(paths$figures, "03_bCCNN")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

scale <- cfg$data$scale
dat_upper <- as.matrix(fread(file.path(paths$interim,
                                       "tri_annual_upper.csv"))[, -1]) / scale

##########################################
#########  partitions and figures
##########################################

parts <- rolling_origin(dat_upper,
                        cfg$bccnn$rolling_origin$test_periods,
                        cfg$bccnn$rolling_origin$vali_periods,
                        cfg$bccnn$rolling_origin$exclude)

## 12 cm wide (the guide asks for one or two figure sizes)
for (k in seq_along(parts)) {
  lab <- if (parts[[k]]$final) "final" else k
  ggsave(paste0("bCCNN rolling origin partition ", lab, ".png"),
         partition_plot(parts[[k]]),
         path = fig_dir,
         device = ragg::agg_png,
         width = 12, height = 12.5, units = "cm", dpi = 300)
}

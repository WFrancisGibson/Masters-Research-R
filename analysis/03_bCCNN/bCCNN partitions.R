##########################################
#########  bCCNN: rolling-origin partitions of the claims triangle
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Figures 3 and 9;
#########  figure layout after the Department's Research Assignment Guide
#########  (2026), Sections 5.3 and 5.7
##########################################

## reads the triangle written by "claims triangles.R" (no Keras needed)
source(here::here("analysis", "00_setup.R"))
fig_dir <- file.path(paths$figures, "03_bCCNN")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

scale <- cfg$data$scale
ro_cfg <- cfg$data$rolling_origin
dat_upper <- readRDS(file.path(paths$interim, "triangles.rds"))$upper / scale

##########################################
#########  partitions and figures
##########################################

parts <- rolling_origin(dat_upper,
                        ro_cfg$test_periods,
                        ro_cfg$vali_periods,
                        ro_cfg$exclude)

## 12 cm wide (the guide asks for one or two figure sizes)
for (k in seq_along(parts)) {
  lab <- if (parts[[k]]$final) "final" else k
  ggsave(paste0("bCCNN rolling origin partition ", lab, ".png"),
         partition_plot(parts[[k]]),
         path = fig_dir,
         device = ragg::agg_png,
         width = 12, height = 12.5, units = "cm", dpi = 300)
}

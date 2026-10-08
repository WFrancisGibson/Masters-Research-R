##########################################
#########  final run: the task table of the launcher
#########  own design: analysis/06_final-run/launch.ps1, contract 2.
##########################################

## one row per task of the final run, written to
## <RUN_ROOT>/final-run/tasks.csv (under the quick profile, the smoke test:
## <RUN_ROOT>/final-run/quick/tasks.csv). The launcher runs this script at
## every start; by hand, from the project root:
##   Rscript "analysis/06_final-run/final run tasks.R"
## The data sets are the SynthETIC ones of config.yml (baseline, si_calendar,
## long_reporting: one triangle each, no unit). Every number of runs is that
## of the run list the fit script itself loops over (config.yml,
## bccnn_grid_runs(), nncl_runs()). A lower stage goes first when a slot is
## free; what a task waits for is in its needs:
##   0  preparation: Keras check, simulation, fingerprint, triangles, cells
##      of the NN chain ladder, data description, Mack, ODP GLM
##   1  main models: bCCNN under its three early-stopping variants, NN chain
##      ladder main runs under both codings of Age of Claimant, the
##      partition figures
##   2  benchmark: one run of every queue of the later stages, then the
##      estimate of the whole run from these times ("final run status.R")
##   3  bCCNN search, bootstrap and masking study; the training times so far
##   4  NN chain ladder, dummy coding: the two grids
##   5  NN chain ladder, dummy coding: the three searches
##   6  NN chain ladder, numeric coding: the two grids; the codings compared
##   7  NN chain ladder, numeric coding: the three searches
##   8  bCCNN grid under the four stopping rules
##   9  the training times of everything, the status
## Within a stage the data sets are in the order of config.yml, and a task
## of one R session stands before the queues that would take every slot.
## The first run of a grid, the benchmark run, is its cheapest: the status
## runs again when the first queue of each grid is done (stages 4 and 8),
## from where the time of that grid rests on a whole grid
source(here::here("analysis", "00_setup.R"))

##########################################
#########  settings
##########################################

## the smoke test runs the table of the quick profile. A row without a
## profile runs under that of the run; the rows of the numeric coding carry
## their own, which in a quick run must begin with "quick" (contract 2.)
quick <- startsWith(Sys.getenv("R_CONFIG_ACTIVE"), "quick")
profile_numeric <- if (quick) "quick_age_numeric" else "age_numeric"
stopifnot("the table is written under the default or the quick profile" =
            cfg$nncl$synthetic$age == "dummy")
cfg_numeric <- config::get(file = here::here("config.yml"),
                           config = profile_numeric)
state <- here::here(cfg$run_root, "final-run")
if (quick) state <- file.path(state, "quick")
datasets <- names(Filter(function(d) d$generator == "synthetic",
                         cfg$datasets))

## sessions: a queue may have as many R sessions as it has runs, at most
## this many (the launcher starts no more than it has slots and runs left)
max_sessions <- 64
## RUN_MAX: the runs an R session fits before the launcher starts a fresh
## one (the memory of a session that fits Keras networks grew by about
## 0.1 GB a run); proposed for config.yml as final_run: max_runs:
max_runs <- list(nncl = 8,             # a run: one network per development
                 bccnn_grid = 20,      # period
                 bccnn_bootstrap = 1,  # a chunk of refits
                 bccnn_masking = 5)

## the early-stopping variants of "bCCNN fit.R" and its bootstrap: the
## environment variables VALIDATION and FINAL_FIT of their sessions
variants <- data.frame(validation = c("rolling_origin", "rolling_origin",
                                      "claims_split"),
                       final_fit = c("refit", "partition", "refit"))
variants$name <- paste(variants$validation, variants$final_fit, sep = "_")

## the scripts, relative to the project root
sim_dir <- "analysis/00_claim-simulation"
bccnn_dir <- "analysis/03_bCCNN"
nncl_dir <- "analysis/04_nn-chain-ladder/trackA_wuthrich2018"
final_dir <- "analysis/06_final-run"
nncl_fit_script <- file.path(nncl_dir, "NN chain ladder SynthETIC fit.R")
nncl_search_script <- file.path(nncl_dir, paste("NN chain ladder SynthETIC",
                                                "hyperparameter search.R"))
nncl_analysis_script <- file.path(nncl_dir,
                                  "NN chain ladder SynthETIC analysis.R")
nncl_cells_script <- file.path(nncl_dir, "NN chain ladder SynthETIC cells.R")
timings_script <- file.path(final_dir, "final run timings.R")
status_script <- file.path(final_dir, "final run status.R")
## the scripts that fit networks: their tasks come before the training times
fit_scripts <- c(file.path(bccnn_dir, c("bCCNN fit.R",
                                        "bCCNN bootstrap fit.R",
                                        "bCCNN masking fit.R",
                                        "bCCNN grid fit.R",
                                        "bCCNN hyperparameter search.R")),
                 nncl_fit_script,
                 nncl_search_script)

## a row of the table (contract 2.). A task with n_runs is a queue: its run
## files, those of pattern, are in the folder of the fits of its data set
## (paths: processed of config.yml, relative to RUN_ROOT)
task <- function(id,
                 stage,
                 dataset,
                 script,
                 needs = NULL,
                 args = "",
                 profile = "",
                 validation = "",
                 final_fit = "",
                 n_runs = NA,
                 pattern = "",
                 max_runs = NA) {
  queue <- !is.na(n_runs)
  data.frame(id = id,
             stage = stage,
             dataset = dataset,
             unit = "",
             profile = profile,
             validation = validation,
             final_fit = final_fit,
             script = script,
             args = args,
             kind = if (queue) "queue" else "single",
             sessions = if (queue) min(n_runs, max_sessions) else NA,
             max_runs = max_runs,
             n_runs = n_runs,
             run_dir = if (queue) file.path(cfg$paths$processed, dataset) else
               "",
             pattern = pattern,
             needs = paste(needs, collapse = ";"))
}

##########################################
#########  the runs of the queues
##########################################

## NN chain ladder, per coding of Age of Claimant (ids nncl: dummy,
## nncl_numeric: numeric): the runs of each part of the fit script (its
## argument main, grid or cl_grid) and the pattern of their files,
## <tag>_fit_<run>.rds. The tag of the dummy coding starts that of the
## numeric coding and "grid_" ends "clgrid_": every pattern holds the tag up
## to "_fit_" and the whole prefix of its part. The main runs by name: S4
## (s4_balance) is saved with S3, without a claim, and is no run of its own
codings <- list(nncl = list(profile = "", cfg = cfg),
                nncl_numeric = list(profile = profile_numeric,
                                    cfg = cfg_numeric))
for (k in names(codings)) {
  nncl_cfg <- codings[[k]]$cfg$nncl
  runs <- nncl_runs(nncl_cfg, codings[[k]]$cfg$seed)
  part <- sapply(runs, `[[`, "part")
  file_start <- paste0("^", nncl_cfg$synthetic$tag, "_fit_")
  prefix <- sapply(nncl_grids(nncl_cfg), `[[`, "prefix")
  codings[[k]]$n_runs <- table(part)
  codings[[k]]$pattern <- c(
    main = paste0(file_start,
                  "(", paste(names(runs)[part == "main"], collapse = "|"),
                  ")[.]rds$"),
    grid = paste0(file_start, prefix[["grid"]], ".*[.]rds$"),
    cl_grid = paste0(file_start, prefix[["cl_grid"]], ".*[.]rds$")
  )
}
modes <- names(cfg$nncl$tuning$modes)          # the searches, one per mode

## bCCNN: the chunks of "bCCNN bootstrap fit.R" (as its split of the
## refits), the seeds of the masking study and the runs of the grid
nsim <- cfg$bccnn$bootstrap$nsim
n_chunks <- length(unique(ceiling(cfg$bccnn$bootstrap$chunks *
                                    seq_len(nsim) / nsim)))
n_masking <- cfg$bccnn$masking$seeds
n_grid <- length(bccnn_grid_runs(cfg$bccnn$grid, cfg$seed))

##########################################
#########  the tasks of a data set
##########################################

keras <- "keras.check"
tasks <- task(keras, 0, datasets[1], file.path(final_dir, "keras check.R"))
## the status script as a task is given its own id (it counts that task as
## done); its tasks write the same files, so each waits for the one before
status_before <- "status.benchmark"
for (d in datasets) {
  ## stage 0: the claims are simulated and compared with the fingerprint of
  ## the laptop's before anything reads them; the cells script writes the
  ## same shared files under both codings, one coding after the other
  sim <- paste0(d, ".simulation")
  fingerprint <- paste0(d, ".fingerprint")
  triangles <- paste0(d, ".triangles")
  cells <- paste0(d, ".", names(codings), ".cells")
  tasks <- rbind(
    tasks,
    task(sim, 0, d, file.path(sim_dir, "SynthETIC claims simulation.R")),
    task(fingerprint,
         0,
         d,
         file.path(sim_dir, "data fingerprint.R"),
         sim,
         args = "check"),
    task(triangles, 0, d, file.path(sim_dir, "claims triangles.R"),
         fingerprint),
    task(cells[1], 0, d, nncl_cells_script, fingerprint),
    task(cells[2],
         0,
         d,
         nncl_cells_script,
         c(fingerprint, cells[1]),
         profile = profile_numeric),
    task(paste0(d, ".description"),
         0,
         d,
         file.path(sim_dir, "SynthETIC claims description.R"),
         fingerprint),
    task(paste0(d, ".features"),
         0,
         d,
         file.path(sim_dir, "SynthETIC feature impact.R"),
         fingerprint),
    task(paste0(d, ".mack"),
         0,
         d,
         "analysis/01_Mack model/Mack chainladder fit.R",
         triangles),
    task(paste0(d, ".odp"),
         0,
         d,
         "analysis/02_ODP glm model/ODP glm fit plot.R",
         triangles)
  )

  ## stage 1: the bCCNN under each variant (one R session each)
  bccnn_fit <- paste0(d, ".bccnn.fit.", variants$name)
  for (v in seq_len(nrow(variants))) {
    tasks <- rbind(tasks,
                   task(bccnn_fit[v],
                        1,
                        d,
                        file.path(bccnn_dir, "bCCNN fit.R"),
                        c(triangles, keras),
                        validation = variants$validation[v],
                        final_fit = variants$final_fit[v]))
  }
  ## the main runs of the NN chain ladder under each coding, then its
  ## tables and figures; the fits wait for the cells of both codings
  for (k in names(codings)) {
    main <- paste0(d, ".", k, ".main")
    tasks <- rbind(tasks,
                   task(main,
                        1,
                        d,
                        nncl_fit_script,
                        c(cells, keras),
                        args = "main",
                        profile = codings[[k]]$profile,
                        n_runs = codings[[k]]$n_runs[["main"]],
                        pattern = codings[[k]]$pattern[["main"]],
                        max_runs = max_runs$nncl),
                   task(paste0(main, ".analysis"),
                        1,
                        d,
                        nncl_analysis_script,
                        c(cells, main),
                        profile = codings[[k]]$profile))
  }
  ## the partition figures (no fit)
  tasks <- rbind(
    tasks,
    task(paste0(d, ".bccnn.partitions"),
         1,
         d,
         file.path(bccnn_dir, "bCCNN partitions.R"),
         triangles),
    task(paste0(d, ".nncl.partition"),
         1,
         d,
         file.path(nncl_dir, "NN chain ladder SynthETIC partition.R"),
         cells)
  )

  ## stage 3: the bCCNN search (one R session, so before the queues), the
  ## bootstrap of each variant with its tables, the masking study
  search <- paste0(d, ".bccnn.search")
  bootstrap <- paste0(d, ".bccnn.bootstrap.", variants$name)
  masking <- paste0(d, ".bccnn.masking")
  tasks <- rbind(tasks,
                 task(search,
                      3,
                      d,
                      file.path(bccnn_dir, "bCCNN hyperparameter search.R"),
                      c(triangles, keras)))
  for (v in seq_len(nrow(variants))) {
    tasks <- rbind(
      tasks,
      task(bootstrap[v],
           3,
           d,
           file.path(bccnn_dir, "bCCNN bootstrap fit.R"),
           c(bccnn_fit[v], keras),
           validation = variants$validation[v],
           final_fit = variants$final_fit[v],
           n_runs = n_chunks,
           pattern = paste0("^bccnn_bootstrap_", variants$name[v],
                            "_c[0-9]+[.]rds$"),
           max_runs = max_runs$bccnn_bootstrap),
      task(paste0(bootstrap[v], ".analysis"),
           3,
           d,
           file.path(bccnn_dir, "bCCNN bootstrap analysis.R"),
           c(triangles, bccnn_fit[v], bootstrap[v]),
           validation = variants$validation[v],
           final_fit = variants$final_fit[v])
    )
  }
  tasks <- rbind(
    tasks,
    task(masking,
         3,
         d,
         file.path(bccnn_dir, "bCCNN masking fit.R"),
         c(triangles, keras),
         n_runs = n_masking,
         pattern = "^bccnn_masking_fit_s[0-9]+[.]rds$",
         max_runs = max_runs$bccnn_masking),
    task(paste0(masking, ".analysis"),
         3,
         d,
         file.path(bccnn_dir, "bCCNN masking analysis.R"),
         c(triangles, masking))
  )
  ## the training times of the fits of stages 1 and 3
  fitted <- tasks$id[tasks$dataset == d & tasks$script %in% fit_scripts]
  timings <- paste0(d, ".timings.stage3")
  tasks <- rbind(tasks, task(timings, 3, d, timings_script, fitted))

  ## stages 4 to 7: the NN chain ladder under the dummy coding (grids 4,
  ## searches 5) and under the numeric coding (6, 7). The analysis script
  ## runs again after each grid; its three tasks of a coding rewrite the
  ## same tables, so each waits for the one before
  for (k in names(codings)) {
    stage <- if (k == "nncl") 4 else 6
    analysis <- paste0(d, ".", k, ".main.analysis")
    for (g in c("grid", "cl_grid")) {
      grid <- paste0(d, ".", k, ".", g)
      tasks <- rbind(tasks,
                     task(grid,
                          stage,
                          d,
                          nncl_fit_script,
                          c(cells, keras),
                          args = g,
                          profile = codings[[k]]$profile,
                          n_runs = codings[[k]]$n_runs[[g]],
                          pattern = codings[[k]]$pattern[[g]],
                          max_runs = max_runs$nncl),
                     task(paste0(grid, ".analysis"),
                          stage,
                          d,
                          nncl_analysis_script,
                          c(cells, grid, analysis),
                          profile = codings[[k]]$profile))
      analysis <- paste0(grid, ".analysis")
      ## the first queue of this grid is done: the status again
      if (d == datasets[1] && k == "nncl") {
        status <- paste0("status.", k, ".", g)
        tasks <- rbind(tasks,
                       task(status,
                            stage,
                            d,
                            status_script,
                            c(grid, status_before),
                            args = status))
        status_before <- status
      }
    }
    for (m in modes) {
      tasks <- rbind(tasks,
                     task(paste0(d, ".", k, ".search.", m),
                          stage + 1,
                          d,
                          nncl_search_script,
                          c(cells, keras),
                          args = m,
                          profile = codings[[k]]$profile))
    }
  }
  ## the two codings compared: main runs and both grids of both codings
  both <- paste0(d,
                 ".",
                 rep(names(codings), each = 3),
                 ".",
                 c("main", "grid", "cl_grid"))
  tasks <- rbind(tasks,
                 task(paste0(d, ".nncl.age_coding"),
                      6,
                      d,
                      file.path(nncl_dir,
                                "NN chain ladder SynthETIC age coding.R"),
                      c(cells, both)))

  ## stage 8: the bCCNN grid; its rule "fixed" reads the steps off the main
  ## fit under the rolling origin with the refit
  grid <- paste0(d, ".bccnn.grid")
  tasks <- rbind(
    tasks,
    task(grid,
         8,
         d,
         file.path(bccnn_dir, "bCCNN grid fit.R"),
         c(triangles, bccnn_fit[variants$name == "rolling_origin_refit"],
           keras),
         n_runs = n_grid,
         pattern = "^bccnn_grid_fit_.*[.]rds$",
         max_runs = max_runs$bccnn_grid),
    task(paste0(grid, ".analysis"),
         8,
         d,
         file.path(bccnn_dir, "bCCNN grid analysis.R"),
         c(triangles, grid))
  )
  if (d == datasets[1]) {
    status <- "status.bccnn.grid"
    tasks <- rbind(tasks,
                   task(status,
                        8,
                        d,
                        status_script,
                        c(grid, status_before),
                        args = status))
    status_before <- status
  }

  ## stage 9: the training times of every fit of the data set
  fitted <- tasks$id[tasks$dataset == d & tasks$script %in% fit_scripts]
  tasks <- rbind(tasks,
                 task(paste0(d, ".timings.final"),
                      9,
                      d,
                      timings_script,
                      c(fitted, timings)))
}

##########################################
#########  benchmark and status
##########################################

## stage 2: one run of every queue of the later stages, by a task with the
## run files of that queue (so the run counts for it later) that is done
## with the first one; a queue waits for its benchmark, so that the two
## never share the runs. Then the estimate of the whole run; the status of
## stage 9 is the last task of the run: it waits for every other one
later <- which(tasks$kind == "queue" & tasks$stage > 2)
benchmark <- tasks[later, ]
benchmark$id <- paste0(benchmark$id, ".benchmark")
benchmark$stage <- 2
benchmark$sessions <- benchmark$max_runs <- benchmark$n_runs <- 1
tasks$needs[later] <- paste(tasks$needs[later], benchmark$id, sep = ";")
tasks <- rbind(tasks,
               benchmark,
               task("status.benchmark",
                    2,
                    datasets[1],
                    status_script,
                    benchmark$id,
                    args = "status.benchmark"))
tasks <- rbind(tasks,
               task("status.final",
                    9,
                    datasets[1],
                    status_script,
                    tasks$id,
                    args = "status.final"))
tasks <- tasks[order(tasks$stage), ]

##########################################
#########  write the table
##########################################

table(stage = tasks$stage, kind = tasks$kind)
## the runs of the queues (those of the benchmark are among them)
real <- tasks$kind == "queue" & tasks$stage != 2
c("tasks" = nrow(tasks),
  "queues" = sum(real),
  "runs" = sum(tasks$n_runs[real]))
dir.create(state, recursive = TRUE, showWarnings = FALSE)
fwrite(tasks, file.path(state, "tasks.csv"))

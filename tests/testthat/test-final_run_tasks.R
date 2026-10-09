##########################################
#########  checks of the task table of the final run
#########  (analysis/06_final-run/final run tasks.R) against the contract of
#########  the launcher (launch.ps1) and the scripts of its tasks
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(data.table)
source(here::here("R", "nn_models.R"))
source(here::here("R", "nn_chain_ladder.R"))
source(here::here("tests", "testthat", "final_run_files.R"))

yml <- here::here("config.yml")
run_root <- gsub("\\\\", "/", tempfile("run_root"))
datasets <- c("baseline", "si_calendar", "long_reporting")
columns <- c("id", "stage", "dataset", "unit", "profile", "validation",
             "final_fit", "script", "args", "kind", "sessions", "max_runs",
             "n_runs", "run_dir", "pattern", "needs")

## the table of a run as the launcher has it written: the script in an R
## session of its own with RUN_ROOT and, for the smoke test,
## R_CONFIG_ACTIVE=quick; every field as text, as the launcher reads it.
## parts: FINAL_RUN_PARTS, the parts of a run on two computers (-Parts)
task_table <- function(profile, parts = NA) {
  withr::local_envvar(RUN_ROOT = run_root,
                      R_CONFIG_ACTIVE = profile,
                      FINAL_RUN_PARTS = parts,
                      DATASET = NA,
                      UNIT = NA,
                      VALIDATION = NA,
                      FINAL_FIT = NA,
                      RUN_SLOT = NA,
                      RUN_MAX = NA)
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    shQuote(here::here("analysis", "06_final-run",
                                       "final run tasks.R")),
                    stdout = tempfile(),
                    stderr = tempfile())
  stopifnot(status == 0)
  state <- file.path(run_root, "final-run")
  if (!is.na(profile)) state <- file.path(state, profile)
  tasks <- fread(file.path(state, "tasks.csv"),
                 colClasses = "character",
                 data.table = FALSE)
  tasks[is.na(tasks)] <- ""
  tasks
}
tables <- list(default = task_table(NA), quick = task_table("quick"))

## config.yml as the R session of a task reads it: under the profile of the
## task or, if it has none, of the run, with DATASET, VALIDATION and
## FINAL_FIT of the task
session_cfg <- function(task, run_profile) {
  unset <- function(x) if (x == "") NA else x
  withr::local_envvar(DATASET = task$dataset,
                      VALIDATION = unset(task$validation),
                      FINAL_FIT = unset(task$final_fit),
                      RUN_ROOT = NA,
                      RAW_DIR = NA)
  config::get(file = yml,
              config = if (task$profile == "") run_profile else task$profile)
}

## the files every task of a table reads, writes and claims
## (final_run_files()), below the folders RUN_ROOT and RAW
files <- lapply(setNames(nm = names(tables)), function(run_profile) {
  tasks <- tables[[run_profile]]
  lapply(setNames(seq_len(nrow(tasks)), tasks$id), function(k) {
    final_run_files(basename(tasks$script[k]),
                    strsplit(tasks$args[k], " ")[[1]],
                    session_cfg(tasks[k, ], run_profile),
                    "RUN_ROOT",
                    "RAW")
  })
})

## the tasks a task waits for, directly or through the tasks it needs
needs_of <- function(tasks) setNames(strsplit(tasks$needs, ";"), tasks$id)
all_needs <- function(needs, id) {
  found <- needs[[id]]
  repeat {
    more <- unique(c(found, unlist(needs[found])))
    if (length(more) == length(found)) return(found)
    found <- more
  }
}

test_that("the table has the columns and the values of the contract", {
  for (tasks in tables) {
    expect_named(tasks, columns)
    expect_match(tasks$id, "^[A-Za-z0-9._-]+$")
    expect_equal(anyDuplicated(tasks$id), 0)
    expect_true(all(file.exists(here::here(tasks$script))))
    expect_true(all(tasks$stage %in% 0:9))
    expect_false(is.unsorted(as.numeric(tasks$stage)))
    expect_true(all(tasks$kind %in% c("single", "queue")))
    queue <- tasks$kind == "queue"
    n_runs <- as.numeric(tasks$n_runs[queue])
    sessions <- as.numeric(tasks$sessions[queue])
    expect_true(all(n_runs >= 1 & sessions >= 1 & sessions <= n_runs))
    expect_true(all(as.numeric(tasks$max_runs[queue]) >= 1))
    expect_true(all(tasks$run_dir[queue] != "" & tasks$pattern[queue] != ""))
    expect_true(all(tasks[!queue, c("sessions", "max_runs", "n_runs",
                                    "run_dir", "pattern")] == ""))
  }
})

test_that("the tasks are those of the three SynthETIC data sets, in order", {
  for (tasks in tables) {
    expect_setequal(tasks$dataset, datasets)
    expect_true(all(tasks$unit == ""))
    expect_false(any(grepl("lob|machine",
                           unlist(tasks[c("id", "script", "args")]),
                           ignore.case = TRUE)))
    # within a stage baseline, si_calendar, long_reporting (the status of
    # the whole run stands last in its stage)
    block <- tasks[!startsWith(tasks$id, "status."), ]
    for (s in unique(block$stage)) {
      expect_false(is.unsorted(match(block$dataset[block$stage == s],
                                     datasets)))
    }
    # the same tasks for every data set; the others: the check of Keras
    # and the status of the whole run
    per_dataset <- sapply(datasets, function(d) {
      sum(startsWith(tasks$id, paste0(d, ".")))
    })
    expect_equal(unname(per_dataset), rep((nrow(tasks) - 6) / 3, 3))
    expect_setequal(tasks$id[!sub("[.].*$", "", tasks$id) %in% datasets],
                    c("keras.check", "status.benchmark", "status.nncl.grid",
                      "status.nncl.cl_grid", "status.bccnn.grid",
                      "status.final"))
  }
  expect_equal(tables$default$id, tables$quick$id)
})

test_that("every need is a task of an earlier or the same stage, no cycle", {
  for (tasks in tables) {
    needs <- needs_of(tasks)
    expect_true(all(unlist(needs) %in% tasks$id))
    stage <- setNames(as.numeric(tasks$stage), tasks$id)
    for (id in tasks$id) {
      expect_true(all(stage[needs[[id]]] <= stage[[id]]), info = id)
      # a task that needs itself through its needs could never start
      expect_false(id %in% all_needs(needs, id), info = id)
    }
  }
})

test_that("the rows of the numeric coding carry a profile of config.yml", {
  profiles <- lapply(tables, function(tasks) unique(tasks$profile))
  expect_setequal(profiles$default, c("", "age_numeric"))
  # a quick run leaves out every row whose profile does not begin with quick
  expect_setequal(profiles$quick, c("", "quick_age_numeric"))
  for (p in c("age_numeric", "quick_age_numeric")) {
    expect_equal(config::get("nncl", config = p, file = yml)$synthetic$age,
                 "numeric")
  }
  expect_equal(config::get("paths", config = "quick_age_numeric", file = yml),
               config::get("paths", config = "quick", file = yml))
  for (tasks in tables) {
    numeric <- grepl("[.]nncl_numeric[.]", tasks$id)
    expect_true(all(tasks$profile[numeric] != ""))
    expect_true(all(tasks$profile[!numeric] == ""))
    # the tasks of the dummy coding, but for the partition figure, the
    # comparison of the two codings and the status after its first grids
    dummy <- grep("[.]nncl[.]", tasks$id, value = TRUE)
    once <- c(paste0(rep(datasets, each = 2),
                     c(".nncl.partition", ".nncl.age_coding")),
              "status.nncl.grid",
              "status.nncl.cl_grid")
    expect_setequal(sub("nncl_numeric", "nncl", tasks$id[numeric]),
                    setdiff(dummy, once))
  }
})

test_that("the run files of a queue are those of its pattern, n_runs of them", {
  for (p in names(tables)) {
    tasks <- tables[[p]]
    queue <- which(tasks$kind == "queue")
    for (d in unique(tasks$run_dir[queue])) {
      # every file of the folder: run files, files saved with a run or
      # without a claim, and the lock and temporary file of a run
      in_dir <- function(f) basename(f[dirname(f) == file.path("RUN_ROOT", d)])
      folder <- unique(in_dir(unlist(files[[p]])))
      for (k in queue[tasks$run_dir[queue] == d]) {
        runs <- basename(files[[p]][[k]]$runs)
        pattern <- tasks$pattern[k]
        if (endsWith(tasks$id[k], ".benchmark")) runs <- runs[1]
        expect_length(runs, as.numeric(tasks$n_runs[k]))
        if (!endsWith(tasks$id[k], ".benchmark")) {
          others <- c(folder, paste0(runs[1], c(".lock", ".tmp", ".partial")))
          expect_setequal(grep(pattern, others, value = TRUE, perl = TRUE),
                          runs)
        }
        # anchored, in the syntax .NET and R share: no POSIX class
        expect_match(pattern, "^\\^[A-Za-z0-9_|().*+\\[\\]-]+\\$$", perl = TRUE)
        expect_false(grepl("[:", pattern, fixed = TRUE))
      }
    }
  }
  # the numbers of the default profile: 6 main runs, two grids of 1,200 runs
  # under each coding, 20 bootstrap chunks per variant, 20 masking seeds
  # and a bCCNN grid of 2,880 runs, on each of three data sets
  tasks <- tables$default
  real <- tasks$kind == "queue" & tasks$stage != 2
  expect_equal(sum(as.numeric(tasks$n_runs[real])),
               3 * (2 * (6 + 1200 + 1200) + 3 * 20 + 20 + 2880))
})

test_that("the patterns match the same files in .NET (the launcher)", {
  powershell <- Sys.which("powershell")
  skip_if(powershell == "", "no Windows PowerShell")
  script <- tempfile(fileext = ".ps1")
  writeLines(c("param($names, $patterns)",
               "$n = @(Get-Content -Path $names)",
               "foreach ($p in @(Get-Content -Path $patterns)) {",
               "  $c = 0",
               "  foreach ($x in $n) { if ($x -cmatch $p) { $c += 1 } }",
               "  $c",
               "}"),
             script)
  for (p in names(tables)) {
    tasks <- tables[[p]]
    queue <- tasks$kind == "queue" & tasks$dataset == "baseline" &
      !endsWith(tasks$id, ".benchmark")
    folder <- unique(basename(unlist(files[[p]][tasks$dataset == "baseline"])))
    folder <- c(folder, paste0(folder, ".lock"), paste0(folder, ".tmp"))
    name_file <- tempfile()
    pattern_file <- tempfile()
    writeLines(folder, name_file)
    writeLines(tasks$pattern[queue], pattern_file)
    counts <- system2(powershell,
                      c("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                        shQuote(script), shQuote(name_file),
                        shQuote(pattern_file)),
                      stdout = TRUE)
    expect_equal(as.numeric(counts), as.numeric(tasks$n_runs[queue]))
  }
})

test_that("a task waits for the tasks that write the files it reads", {
  for (p in names(tables)) {
    tasks <- tables[[p]]
    needs <- needs_of(tasks)
    written <- lapply(files[[p]], function(f) c(f$writes, f$runs, f$with))
    for (id in tasks$id) {
      before <- unlist(written[all_needs(needs, id)])
      expect_true(all(files[[p]][[id]]$reads %in% before), info = id)
    }
    # the analysis of a queue reads its runs: it waits for the queue
    analysis <- grep("[.]analysis$", tasks$id, value = TRUE)
    for (id in analysis) {
      expect_true(sub("[.]analysis$", "", id) %in% needs[[id]], info = id)
    }
    # the cells script writes the same files under both codings: the
    # numeric coding after the dummy coding, every other script of the NN
    # chain ladder after both
    nncl <- grepl("NN chain ladder", tasks$script)
    cells <- grepl("cells[.]R$", tasks$script)
    for (id in tasks$id[nncl & !cells]) {
      d <- tasks$dataset[tasks$id == id]
      expect_true(all(paste0(d, c(".nncl.cells", ".nncl_numeric.cells")) %in%
                        all_needs(needs, id)),
                  info = id)
    }
    # every network is fitted after the check of Keras
    keras <- grepl("^analysis/0[34].*(fit|search)[.]R$", tasks$script)
    expect_true(all(sapply(needs[keras], function(n) "keras.check" %in% n)))
    # the training times of a data set after every fit of it
    for (d in datasets) {
      fits <- tasks$id[keras & tasks$dataset == d & tasks$stage != 2]
      expect_true(all(fits %in% needs[[paste0(d, ".timings.final")]]))
    }
  }
})

test_that("tasks that write the same outputs never run at once", {
  for (tasks in tables) {
    needs <- needs_of(tasks)
    single <- tasks[tasks$kind == "single", ]
    same <- do.call(paste, single[c("dataset", "profile", "validation",
                                    "final_fit", "script", "args")])
    for (s in unique(same[duplicated(same)])) {
      ids <- single$id[same == s]
      for (k in seq_along(ids)[-1]) {
        expect_true(ids[k - 1] %in% all_needs(needs, ids[k]), info = ids[k])
      }
    }
  }
})

test_that("the status tasks follow each other and end the run", {
  for (tasks in tables) {
    needs <- needs_of(tasks)
    status <- tasks[basename(tasks$script) == "final run status.R", ]
    expect_equal(status$id,
                 c("status.benchmark", "status.nncl.grid",
                   "status.nncl.cl_grid", "status.bccnn.grid",
                   "status.final"))
    # the script counts the task named in its argument as done
    expect_equal(status$args, status$id)
    expect_equal(status$stage, c("2", "4", "4", "8", "9"))
    # they write the same files: each waits for the one before
    for (k in seq_along(status$id)[-1]) {
      expect_true(status$id[k - 1] %in% needs[[status$id[k]]])
    }
    # the last task of the run waits for every other one
    expect_equal(tasks$id[nrow(tasks)], "status.final")
    expect_setequal(needs[["status.final"]], setdiff(tasks$id, "status.final"))
    # after the first queue of a grid: the status stands before the next
    # queue of its stage, which would take every slot
    queues <- c(status.nncl.grid = "baseline.nncl.grid",
                status.nncl.cl_grid = "baseline.nncl.cl_grid",
                status.bccnn.grid = "baseline.bccnn.grid")
    for (id in names(queues)) {
      expect_true(queues[[id]] %in% needs[[id]])
      rows <- match(c(queues[[id]], id), tasks$id)
      expect_lt(rows[1], rows[2])
      expect_false(any(tasks$kind[(rows[1] + 1):rows[2]] == "queue"))
    }
  }
})

test_that("the benchmark rows mirror the queues of the later stages", {
  for (tasks in tables) {
    needs <- needs_of(tasks)
    later <- tasks[tasks$kind == "queue" & as.numeric(tasks$stage) > 2, ]
    benchmark <- tasks[tasks$stage == 2 & tasks$kind == "queue", ]
    expect_setequal(benchmark$id, paste0(later$id, ".benchmark"))
    later <- later[match(benchmark$id, paste0(later$id, ".benchmark")), ]
    same <- c("dataset", "unit", "profile", "validation", "final_fit",
              "script", "args", "kind", "run_dir", "pattern")
    rownames(benchmark) <- rownames(later) <- NULL
    expect_equal(benchmark[same], later[same])
    # done with one run, fitted by one session that takes one run
    expect_true(all(benchmark[c("sessions", "max_runs", "n_runs")] == "1"))
    for (k in seq_len(nrow(later))) {
      # the queue waits for its benchmark and for what the benchmark needs
      expect_setequal(needs[[later$id[k]]],
                      c(needs[[benchmark$id[k]]], benchmark$id[k]))
    }
    expect_setequal(needs[["status.benchmark"]], benchmark$id)
    # no other task of stage 2, and no benchmark of the queues of stage 1
    expect_equal(sum(tasks$stage == 2), nrow(benchmark) + 1)
  }
})

test_that("the fit scripts name their run files as final_run_files() does", {
  # the lines of the fit scripts that build the names of the run files; if
  # one changes, final_run_files.R and the patterns of the table follow
  has_line <- function(script, line) {
    lines <- gsub(" +", " ", trimws(readLines(here::here("analysis", script))))
    any(grepl(line, paste(lines, collapse = " "), fixed = TRUE))
  }
  nncl <- "04_nn-chain-ladder/trackA_wuthrich2018/"
  expect_true(has_line("03_bCCNN/bCCNN fit.R",
                       "paste0(\"bccnn_fit_\", variant, \".rds\")"))
  expect_true(has_line("03_bCCNN/bCCNN bootstrap fit.R",
                       paste("paste0(\"bccnn_bootstrap_\", variant, \"_c\",",
                             "seq_along(chunks), \".rds\")")))
  expect_true(has_line("03_bCCNN/bCCNN masking fit.R",
                       "paste0(\"bccnn_masking_fit_s\", s, \".rds\")"))
  expect_true(has_line("03_bCCNN/bCCNN grid fit.R",
                       "paste0(\"bccnn_grid_fit_\", run_name, \".rds\")"))
  expect_true(has_line("03_bCCNN/bCCNN hyperparameter search.R",
                       paste("file.path(paths$processed,",
                             "\"bccnn_tuning_search.rds\")")))
  expect_true(has_line(paste0(nncl, "NN chain ladder SynthETIC fit.R"),
                       "paste0(tag, \"_fit_\", run_name, \".rds\")"))
  expect_true(has_line(paste0(nncl, "NN chain ladder SynthETIC fit.R"),
                       "paste0(tag, \"_fit_s4_balance.rds\")"))
  expect_true(has_line(paste0(nncl, "NN chain ladder SynthETIC ",
                              "hyperparameter search.R"),
                       "paste0(tag, \"_fit_\", run_names, \".rds\")"))
})

test_that("the table of a rehearsal is the real one with the stand-in", {
  # final_run_stand_in_tasks.R as the launcher runs it (-TasksScript), the
  # final table with the runs of its grids divided by 10
  root <- gsub("\\\\", "/", tempfile("rehearsal_root"))
  withr::local_envvar(RUN_ROOT = root,
                      STAND_IN_SCALE = "10",
                      R_CONFIG_ACTIVE = NA,
                      FINAL_RUN_PARTS = NA,
                      DATASET = NA,
                      UNIT = NA,
                      VALIDATION = NA,
                      FINAL_FIT = NA,
                      RUN_SLOT = NA,
                      RUN_MAX = NA)
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    shQuote(here::here("tests", "testthat",
                                       "final_run_stand_in_tasks.R")),
                    stdout = tempfile(),
                    stderr = tempfile())
  expect_equal(status, 0)
  # read.csv: fread keeps the doubled quotes of a field as they are
  read_table <- function(file) {
    x <- read.csv(file.path(root, "final-run", file),
                  colClasses = "character")
    x[is.na(x)] <- ""
    x
  }
  real <- read_table("tasks_real.csv")
  copy <- read_table("tasks.csv")
  expect_equal(real, tables$default)
  same <- setdiff(columns, c("script", "args", "sessions", "n_runs"))
  expect_equal(copy[same], real[same])
  # the status script runs as it is; every other task is the stand-in,
  # given the file name of its script and the arguments of the task
  status_rows <- basename(real$script) == "final run status.R"
  expect_equal(copy[status_rows, ], real[status_rows, ])
  expect_true(all(copy$script[!status_rows] ==
                    "tests/testthat/final_run_stand_in.R"))
  expect_true(file.exists(here::here("tests", "testthat",
                                     "final_run_stand_in.R")))
  expect_equal(copy$args[!status_rows],
               trimws(paste0("\"", basename(real$script[!status_rows]), "\" ",
                             real$args[!status_rows])))
  # a tenth of the runs of the grids, every other queue in full
  grid <- real$kind == "queue" & real$stage != "2" &
    (grepl("grid fit", real$script) | real$args %in% c("grid", "cl_grid"))
  expect_equal(sum(grid), 3 * 5)
  expect_equal(as.numeric(copy$n_runs[grid]),
               as.numeric(real$n_runs[grid]) / 10)
  expect_equal(copy$n_runs[!grid], real$n_runs[!grid])
  queue <- copy$kind == "queue"
  expect_true(all(as.numeric(copy$sessions[queue]) <=
                    as.numeric(copy$n_runs[queue])))
})

##########################################
#########  a run on two computers: the tables of some parts
##########################################

## FINAL_RUN_PARTS as the README gives it: the bCCNN without its search and
## grid on the VM, the grids and searches of the NN chain ladder on the HPC,
## the bCCNN search and grid later
selections <- c(vm = "data+bccnn_main+bootstrap+masking",
                hpc = "nncl_grid+nncl_search",
                later = "bccnn_search+bccnn_grid")
part_tables <- lapply(selections, function(s) task_table(NA, s))
fit_scripts <- "(fit|hyperparameter search)[.]R$"
## the id of a task that carries the parts (the status after the benchmark
## stage, the last tasks) without them: its id in the whole table
whole_id <- function(id) sub("([.](final|benchmark))[.].*$", "\\1", id)
## the rows of a table without their row names
plain <- function(x) {
  rownames(x) <- NULL
  x
}

test_that("a table of some parts has their tasks as the whole table", {
  whole <- tables$default
  for (s in names(part_tables)) {
    tasks <- part_tables[[s]]
    expect_named(tasks, columns)
    expect_match(tasks$id, "^[A-Za-z0-9._-]+$")
    expect_equal(anyDuplicated(tasks$id), 0)
    # rows of the whole table, in its order
    rows <- match(whole_id(tasks$id), whole$id)
    expect_false(anyNA(rows))
    expect_false(is.unsorted(rows))
    # the status after the benchmark stage and the last tasks carry the
    # parts: a launch with other parts, or with all, runs them again
    last <- tasks$stage == "9" | startsWith(tasks$id, "status.benchmark")
    carried <- paste0(".", gsub("+", "-", selections[[s]], fixed = TRUE))
    expect_equal(tasks$id[last], paste0(whole$id[rows[last]], carried))
    expect_equal(tasks$id[!last], whole$id[rows[!last]])
    expect_equal(sum(last), 5)
    expect_equal(tasks$id[nrow(tasks)], paste0("status.final", carried))
    # a task of a part: every field as in the whole table, so it brings
    # all it needs; the status and the training times follow what is there
    run <- grepl("final run (status|timings)[.]R$", tasks$script)
    expect_equal(plain(tasks[!run, ]), plain(whole[rows[!run], ]))
    same <- setdiff(columns, c("id", "args", "needs"))
    expect_equal(plain(tasks[run, same]), plain(whole[rows[run], same]))
    needs <- needs_of(tasks)
    expect_true(all(unlist(needs) %in% tasks$id))
    needs_whole <- lapply(needs_of(whole), function(n) {
      tasks$id[match(n, whole_id(tasks$id))]
    })
    status <- tasks$id[basename(tasks$script) == "final run status.R"]
    expect_equal(tasks$args[match(status, tasks$id)], status)
    for (id in tasks$id[run]) {
      kept <- needs_whole[[whole_id(id)]]
      kept <- kept[!is.na(kept)]
      before <- status[seq_len(match(id, status, nomatch = 1) - 1)]
      expect_setequal(needs[[id]], union(kept, tail(before, 1)))
      expect_gt(length(setdiff(needs[[id]], tasks$id[run])), 0)
    }
    expect_setequal(needs[[tasks$id[nrow(tasks)]]],
                    tasks$id[-nrow(tasks)])
  }
})

test_that("in a table of some parts a task finds the files it reads", {
  for (s in names(part_tables)) {
    tasks <- part_tables[[s]]
    needs <- needs_of(tasks)
    part_files <- lapply(setNames(seq_len(nrow(tasks)), tasks$id), function(k) {
      final_run_files(basename(tasks$script[k]),
                      strsplit(tasks$args[k], " ")[[1]],
                      session_cfg(tasks[k, ], "default"),
                      "RUN_ROOT",
                      "RAW")
    })
    written <- lapply(part_files, function(f) c(f$writes, f$runs, f$with))
    for (id in tasks$id) {
      before <- unlist(written[all_needs(needs, id)])
      expect_true(all(part_files[[id]]$reads %in% before), info = id)
    }
  }
})

test_that("the parts of the two computers fit every network once", {
  whole <- tables$default
  fits <- lapply(part_tables, function(tasks) {
    tasks$id[grepl(fit_scripts, tasks$script) & tasks$stage != "2"]
  })
  # no network on both computers; with the bCCNN search and grid, which
  # start from the main fit of the VM, every network of the whole table
  expect_length(intersect(fits$vm, fits$hpc), 0)
  expect_setequal(unlist(fits),
                  whole$id[grepl(fit_scripts, whole$script) &
                             whole$stage != "2"])
  expect_setequal(intersect(fits$vm, fits$later),
                  paste0(datasets, ".bccnn.fit.rolling_origin_refit"))
  # the HPC: the two grids and three searches of both codings, with the
  # main runs their tables read, and nothing of the bCCNN
  hpc <- part_tables$hpc
  expect_false(any(grepl("bCCNN|Mack|ODP", hpc$script)))
  expect_setequal(sub("^[a-z_]+[.](nncl[a-z_]*)[.](.*)$", "\\2",
                      fits$hpc),
                  c("main", "grid", "cl_grid",
                    paste0("search.", c("cl_start", "paper", "early_stop"))))
  real <- hpc$kind == "queue" & hpc$stage != "2"
  expect_equal(sum(as.numeric(hpc$n_runs[real])),
               3 * 2 * (6 + 1200 + 1200))
  expect_true(all(paste0(datasets, ".nncl.age_coding") %in% hpc$id))
  # the VM: the three variants, their bootstraps, the masking study, the
  # preparation in full, and nothing of the NN chain ladder but its cells
  vm <- part_tables$vm
  expect_setequal(vm$id[vm$stage == "0"], whole$id[whole$stage == "0"])
  expect_setequal(basename(vm$script[grepl("NN chain ladder", vm$script)]),
                  "NN chain ladder SynthETIC cells.R")
  real <- vm$kind == "queue" & vm$stage != "2"
  expect_equal(sum(as.numeric(vm$n_runs[real])), 3 * (3 * 20 + 20))
})

test_that("one coding of the NN chain ladder: its grids and searches only", {
  whole <- tables$default
  one_coding <- function(coding, parts = "nncl_grid+nncl_search") {
    withr::local_envvar(FINAL_RUN_CODING = coding)
    task_table(NA, parts)
  }
  numeric <- one_coding("numeric")
  dummy <- one_coding("dummy")
  # the tasks of stages 4 to 7 are of the chosen coding; the main runs of
  # stage 1 and the cells of stage 0 of both codings, as the whole table
  for (tasks in list(numeric, dummy)) {
    later <- tasks[as.numeric(tasks$stage) %in% 4:7, ]
    expect_gt(nrow(later), 0)
    expect_true(all(grepl(if (identical(tasks, numeric)) "[.]nncl_numeric[.]"
                          else "[.]nncl[.]", later$id)))
    expect_false(any(grepl("age_coding", tasks$id)))
    expect_true(all(paste0(rep(datasets, each = 2),
                           c(".nncl.cells", ".nncl_numeric.cells")) %in%
                      tasks$id))
    # every row as in the whole table, but the carried ids
    rows <- match(whole_id(tasks$id), whole$id)
    expect_false(anyNA(rows))
    run <- grepl("final run (status|timings)[.]R$", tasks$script)
    expect_equal(plain(tasks[!run, ]), plain(whole[rows[!run], ]))
  }
  expect_equal(numeric$id[nrow(numeric)],
               "status.final.nncl_grid-nncl_search.numeric")
  expect_equal(dummy$id[nrow(dummy)],
               "status.final.nncl_grid-nncl_search.dummy")
  # the two codings together are the table of both, but for the comparison
  # of the codings and the status after the first grids of the dummy coding
  both <- part_tables$hpc
  expect_setequal(c(whole_id(numeric$id), whole_id(dummy$id)),
                  setdiff(whole_id(both$id),
                          c(paste0(datasets, ".nncl.age_coding"))))
  # the runs: one coding's two grids and its main runs
  real <- numeric$kind == "queue" & numeric$stage != "2"
  expect_equal(sum(as.numeric(numeric$n_runs[real])), 3 * (6 + 1200 + 1200))
  expect_equal(one_coding("both"), both)
  expect_equal(one_coding(""), both)
  # a coding that is none: no table
  withr::local_envvar(RUN_ROOT = run_root,
                      R_CONFIG_ACTIVE = NA,
                      FINAL_RUN_PARTS = NA,
                      FINAL_RUN_CODING = "ordinal")
  table_file <- file.path(run_root, "final-run", "tasks.csv")
  unlink(table_file)
  log <- tempfile()
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    shQuote(here::here("analysis", "06_final-run",
                                       "final run tasks.R")),
                    stdout = log,
                    stderr = log)
  expect_false(status == 0)
  expect_match(paste(readLines(log), collapse = " "),
               "names no coding of Age of Claimant: ordinal")
  expect_false(file.exists(table_file))
})

test_that("the parts are read by name, group and separator", {
  whole <- tables$default
  # not set, all, or every part by name: the whole table
  expect_equal(task_table(NA, "all"), whole)
  expect_equal(task_table(NA, "main+bccnn+nncl"), whole)
  # a group is its parts; commas, blanks and capitals are read, the order
  # is that of the table
  expect_equal(task_table(NA, "Masking, bccnn_main  data;bootstrap"),
               part_tables$vm)
  nncl <- task_table(NA, "nncl")
  expect_equal(nncl, task_table(NA, "nncl_search+nncl_grid+nncl_main"))
  # nncl_grid brings the main runs but not the partition figure of nncl_main
  expect_setequal(setdiff(whole_id(nncl$id), whole_id(part_tables$hpc$id)),
                  paste0(datasets, ".nncl.partition"))
  # the quick table of the smoke test has the same tasks
  expect_equal(task_table("quick", selections[["hpc"]])$id,
               part_tables$hpc$id)
  # a name that is no part: no table
  withr::local_envvar(RUN_ROOT = run_root,
                      R_CONFIG_ACTIVE = NA,
                      FINAL_RUN_PARTS = "nncl+bcnn")
  table_file <- file.path(run_root, "final-run", "tasks.csv")
  unlink(table_file)
  log <- tempfile()
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    shQuote(here::here("analysis", "06_final-run",
                                       "final run tasks.R")),
                    stdout = log,
                    stderr = log)
  expect_false(status == 0)
  expect_match(paste(readLines(log), collapse = " "),
               "names no part of the final run: bcnn")
  expect_false(file.exists(table_file))
})

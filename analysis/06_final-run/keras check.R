##########################################
#########  final run: check of Keras on this computer
#########  run by setup_vm.ps1 and as a task of the final run; own design
##########################################

## the R and the Python side of the fits: prints the versions, trains a small
## network for 3 steps, and stops if the Python of this session is not the
## one the launcher named (RETICULATE_PYTHON) or if Python or one of its
## packages is not the version of requirements.txt (the laptop's)
source(here::here("analysis", "00_setup.R"))
library(keras3)

##########################################
#########  versions
##########################################

## requirements.txt: the line "# python <version>" and one line
## "package==version" per Python package
req <- readLines(here::here("requirements.txt"))
python_pinned <- sub("^# python ", "",
                     grep("^# python [0-9]", req, value = TRUE))
req <- trimws(sub("#.*", "", req))
req <- req[req != ""]
versions <- data.frame(package = sub("==.*", "", req),
                       pinned = sub(".*==", "", req))

## what Python reports: its own version and every installed package
## (importlib.metadata of Python's standard library), kept with the logs.
## These are the first Python calls of the session: reticulate starts Python
sys <- reticulate::import("sys")
python <- sub(" .*", "", sys$version)
python_exe <- reticulate::py_exe()
installed <- unlist(reticulate::py_eval(paste0(
  "sorted(d.metadata['Name'] + '==' + d.version for d in ",
  "__import__('importlib.metadata').metadata.distributions())"
)))
writeLines(c(paste("# python", python, python_exe), installed),
           file.path(paths$logs, "python_packages.txt"))
## the R packages of the fits, with keras3 loaded: no fit session of the
## final run writes sessionInfo.txt (analysis/00_setup.R, RUN_SLOT)
writeLines(capture.output(sessionInfo()),
           file.path(paths$logs, "r_packages.txt"))

## the names of Python packages compare in lower case, "-" for "_" and "."
py_name <- function(x) gsub("[-_.]+", "-", tolower(x))
installed_version <- sub(".*==", "", installed)
names(installed_version) <- py_name(sub("==.*", "", installed))
versions$installed <- unname(installed_version[py_name(versions$package)])

c("R" = R.version.string,
  "keras3" = as.character(packageVersion("keras3")),
  "tensorflow (R package)" = as.character(packageVersion("tensorflow")),
  "reticulate" = as.character(packageVersion("reticulate")),
  "Python" = python,
  "Python pinned" = python_pinned,
  "Python program" = python_exe,
  "RETICULATE_PYTHON" = Sys.getenv("RETICULATE_PYTHON"),
  "Keras backend" = config_backend())
reticulate::py_config()
versions
## installed without a line in requirements.txt
setdiff(names(installed_version), py_name(versions$package))

##########################################
#########  a small network
##########################################

## two dense layers on random numbers, 3 full-batch steps, with the calls of
## the fit functions (R/nn_models.R)
clear_session()
set_random_seed(cfg$seed)
x <- matrix(rnorm(200), ncol = 4)
y <- matrix(rnorm(50), ncol = 1)
features <- layer_input(shape = c(4), name = "features")
response <- features %>%
  layer_dense(units = 8, activation = "tanh", name = "hidden1") %>%
  layer_dense(units = 1, name = "response")
model <- keras_model(inputs = features, outputs = response)
model %>% compile(loss = "mse",
                  optimizer = optimizer_rmsprop(learning_rate = 0.001))
history <- model %>% fit(x, y,
                         epochs = 3L,
                         batch_size = nrow(x),
                         verbose = 0,
                         view_metrics = FALSE)
loss <- history$metrics$loss
round(loss, 4)
stopifnot("the small network did not train for 3 steps" =
            length(loss) == 3 && all(is.finite(loss)))

##########################################
#########  check against the launcher and requirements.txt
##########################################

## the fits of the final run are to use the Python environment the launcher
## names (launch.ps1, contract 10.) with the Python packages of the laptop:
## stop if this session has another Python or other versions
python_named <- Sys.getenv("RETICULATE_PYTHON", python_exe)
programs <- tolower(normalizePath(c(python_exe, python_named),
                                  winslash = "/", mustWork = FALSE))
stopifnot(
  "Python is not the program named in RETICULATE_PYTHON" =
    programs[1] == programs[2],
  "Python is not the version of requirements.txt" =
    startsWith(python, paste0(python_pinned, ".")),
  "Python packages differ from requirements.txt (see the table above)" =
    all(versions$installed == versions$pinned)
)
cat("keras check passed: Python", python, "at", python_exe, "with",
    nrow(versions), "packages as in requirements.txt\n")

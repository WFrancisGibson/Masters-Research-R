#!/bin/bash
##########################################
#########  final run: setup of the HPC (Stellenbosch HPC1 and HPC2)
#########  run once on the login node; own design, the counterpart of
#########  setup_vm.ps1
##########################################

## after the clone, from the project root on the login node (it needs the
## internet: CRAN and the Python package index):
##   bash analysis/06_final-run/setup_hpc.sh
## It can be run again: every step looks first at what is there. It builds
## the R packages of renv.lock from their sources (an hour or more the
## first time), so start it in a screen or tmux session if there is one,
## or keep the connection open.
## Variables, before the command (R_MODULE=app/R/4.5.1 bash ...):
##   R_MODULE     the R module of the cluster (default app/R/4.5.1; see
##                module avail app/R)
##   MAKE_JOBS    compilers at once while the R packages are built (4)
##   SKIP_TESTS   1: no unit tests
## It does not submit the job; the next steps are printed at the end.

R_MODULE="${R_MODULE:-app/R/4.5.1}"
MAKE_JOBS="${MAKE_JOBS:-4}"
SKIP_TESTS="${SKIP_TESTS:-0}"

##########################################
#########  functions
##########################################

## the heading of a step
step() {
  echo ""
  echo "== $1"
}

## runs a command; a step that fails stops the setup
run() {
  echo "   > $*"
  "$@"
  local code=$?
  if [ ${code} -ne 0 ]; then
    echo ""
    echo "FAILED (exit code ${code}). The setup stops here: mend this step"
    echo "and run setup_hpc.sh again."
    exit 1
  fi
}

##########################################
#########  this computer, R
##########################################

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}" || exit 1

step "this computer"
echo "   $(hostname), $(grep -m 1 PRETTY_NAME /etc/os-release 2> /dev/null |
  cut -d= -f2 | tr -d '"')"
echo "   C library: $(ldd --version 2> /dev/null | head -n 1)"
echo "   processor:$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2)"
AVX=0
if grep -q -w avx /proc/cpuinfo; then AVX=1; fi
echo "   AVX (TensorFlow needs it): ${AVX}"
echo "   disk quota of the home folder:"
(quota -s 2> /dev/null || df -h "${HOME}") | sed 's/^/     /'

## the module command of a login shell is not always there in a script
step "R: module load ${R_MODULE}"
if ! type module > /dev/null 2>&1; then
  for file in /etc/profile.d/modules.sh /usr/share/Modules/init/bash \
    /etc/profile.d/lmod.sh; do
    if [ -r "${file}" ]; then . "${file}"; fi
  done
fi
module load "${R_MODULE}"
if ! command -v Rscript > /dev/null; then
  echo "No Rscript after: module load ${R_MODULE}"
  echo "See the R modules with: module avail app/R ; then"
  echo "  R_MODULE=<module> bash analysis/06_final-run/setup_hpc.sh"
  echo "(and give the same module to the job: qsub -v R_MODULE=<module>)."
  exit 1
fi
echo "   $(Rscript -e 'cat(R.version.string)'): $(command -v Rscript)"
echo "   (the laptop has R 4.6.1; the package versions are those of"
echo "   renv.lock, and the simulated claims are compared with the"
echo "   laptop's by the fingerprint task of the run)"

##########################################
#########  R packages, unit tests
##########################################

## the packages of renv.lock (the versions of the laptop) go into the user
## library; renv is not activated in the project, so the scripts run as on
## the laptop. On Linux they are built from their sources
step "R packages of renv.lock into the user library (long the first time)"
export RENV_CONFIG_CACHE_ENABLED=FALSE
export RENV_CONFIG_SANDBOX_ENABLED=FALSE
export MAKEFLAGS="-j${MAKE_JOBS}"
run Rscript -e "dir.create(Sys.getenv('R_LIBS_USER'), recursive = TRUE, showWarnings = FALSE)"
run Rscript -e "if (!requireNamespace('renv', quietly = TRUE)) install.packages('renv', repos = 'https://cloud.r-project.org')"
run Rscript -e "renv::restore(lockfile = 'renv.lock', library = .libPaths()[1], prompt = FALSE)"

## the scripts save their figures as PNG files (ggsave)
step "R can write a PNG figure"
run Rscript -e "f <- tempfile(fileext = '.png'); ggplot2::ggsave(f, ggplot2::ggplot(data.frame(x = 1:2, y = 1:2), ggplot2::aes(x, y)) + ggplot2::geom_line(), width = 4, height = 3); stopifnot(file.size(f) > 0); cat('ok\n')"

step "unit tests (no Keras)"
if [ "${SKIP_TESTS}" = "1" ]; then
  echo "   SKIP_TESTS=1: left out"
else
  echo "   (to go on in spite of a failing test: SKIP_TESTS=1 bash ...)"
  run Rscript tests/testthat.R
fi

##########################################
#########  Python environment, the launcher, Keras
##########################################

## the Python of the fits is built here once, from requirements.txt (the
## complete package list of the laptop), in its own folder beside the
## project: env is the environment, python the Python it rests on. The
## launcher names its python to reticulate in every session (launch.py,
## 10.), so no session needs the internet (the nodes of a cluster often
## have none) and no release of a Python package changes the run. It is
## built with uv, the program reticulate itself uses
PYTHON_HOME="$(dirname "${ROOT}")/Masters-Research-R-python"
PYTHON_ENV="${PYTHON_HOME}/env"
PYTHON_EXE="${PYTHON_ENV}/bin/python"
PYTHON_VERSION="$(sed -n 's/^# python \([0-9.]*\).*/\1/p' requirements.txt |
  head -n 1)"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
step "Python ${PYTHON_VERSION} environment of requirements.txt: ${PYTHON_ENV}"
if [ -f "${PYTHON_HOME}/built.txt" ]; then
  echo "   it is there already (to build it again delete ${PYTHON_HOME})"
else
  echo "   > Rscript -e \"cat(reticulate:::uv_binary())\""
  UV="$(Rscript -e "cat(reticulate:::uv_binary())")"
  if [ -z "${UV}" ] || [ ! -x "${UV}" ]; then
    echo ""
    echo "FAILED: reticulate found and downloaded no uv. The setup stops"
    echo "here: mend this step and run setup_hpc.sh again."
    exit 1
  fi
  export UV_PYTHON_INSTALL_DIR="${PYTHON_HOME}/python"
  export UV_PYTHON_PREFERENCE="only-managed"
  mkdir -p "${PYTHON_HOME}"
  if [ ! -x "${PYTHON_EXE}" ]; then
    run "${UV}" venv --python "${PYTHON_VERSION}" "${PYTHON_ENV}"
  fi
  run "${UV}" pip install --python "${PYTHON_EXE}" --link-mode copy \
    --no-cache -r requirements.txt
  echo "built $(date '+%Y-%m-%d %H:%M:%S') with ${UV}" > "${PYTHON_HOME}/built.txt"
fi

## the launcher on this system: Python stands in for Rscript (no R, no
## Keras, about a minute)
step "checks of the launcher (launch_test.py)"
run "${PYTHON_EXE}" "analysis/06_final-run/launch_test.py"

## the first Keras session, with the variables the launcher gives its
## sessions: the versions are compared with requirements.txt and a small
## network is trained for 3 steps. RUN_DIR must not be set: with it keras3
## adds a TensorBoard callback to every fit. The job runs the same check
## as its first task, on the node of the run
RESULTS="$(dirname "${ROOT}")/Masters-Research-R-results"
mkdir -p "${RESULTS}/results"
step "Keras: the Python packages against requirements.txt, a small network"
if [ "${AVX}" = "1" ]; then
  unset RUN_DIR KERAS_PYTHON
  export RETICULATE_PYTHON="${PYTHON_EXE}"
  export RETICULATE_USE_MANAGED_VENV="no"
  export RETICULATE_CHECK_REQUIRED_PACKAGES="false"
  export RUN_ROOT="${RESULTS}/results"
  export OMP_NUM_THREADS=1 TF_NUM_INTRAOP_THREADS=1 TF_NUM_INTEROP_THREADS=1
  export TF_CPP_MIN_LOG_LEVEL=2
  run Rscript "analysis/06_final-run/keras check.R"
else
  echo "   left out: the processor of this login node has no AVX. The job"
  echo "   checks Keras as its first task, on its own node."
fi

##########################################
#########  next steps
##########################################

echo ""
echo "Setup finished. Next, from the project root (${ROOT}):"
echo " 1. A first try, the quick profile only (every script once, small):"
echo "      qsub -v FINAL_RUN_ARGS=\"--profile quick\" -l walltime=12:00:00 analysis/06_final-run/hpc_job.sh"
echo "    then  qstat -u \$USER  and"
echo "      tail -n 20 ${RESULTS}/results/final-run/quick/launch.log"
echo " 2. The final run (the smoke test first, then every task; 48 R"
echo "    sessions on one node, up to 168 hours a job):"
echo "      qsub analysis/06_final-run/hpc_job.sh"
echo "      tail -n 20 ${RESULTS}/results/final-run/launch.log"
echo "    A job that ends before all is done: the same qsub again, it resumes."
echo " 3. Stop: qdel <job id>. Other resources, the results: the top of"
echo "    analysis/06_final-run/hpc_job.sh."

#!/usr/bin/env bash
## sets up a Linux cloud container (Ubuntu, no access to CRAN) for the NN
## chain ladder SynthETIC fit: R 4.5, TensorFlow and most R packages from
## conda-forge (micromamba in /opt/mamba), keras3, SynthETIC and ChainLadder
## from the CRAN mirror on GitHub; then simulates the claims (data/raw is not
## in git). Every step is skipped when done. Afterwards:
##   export PATH=/opt/mamba/envs/r/bin:$PATH
##   export RETICULATE_PYTHON=/opt/mamba/envs/r/bin/python
##   "Claude outputs/nncl-parallel-workers/run_queue.sh" 6
## (6 workers on 4 cores: one worker keeps a core about 75 % busy)
set -euo pipefail
cd "$(dirname "$0")/../.."
export MAMBA_ROOT_PREFIX=/opt/mamba
if [ ! -x /opt/mamba/bin/micromamba ]; then
  mkdir -p /opt/mamba
  curl -sS -o /opt/mamba/mm.tar.bz2 \
    https://conda.anaconda.org/conda-forge/linux-64/micromamba-2.9.0-0.tar.bz2
  tar xjf /opt/mamba/mm.tar.bz2 -C /opt/mamba bin/micromamba
fi
if [ ! -x /opt/mamba/envs/r/bin/Rscript ]; then
  /opt/mamba/bin/micromamba create -y -q -p /opt/mamba/envs/r \
    -c conda-forge --override-channels \
    r-base=4.5 python=3.12 tensorflow-cpu keras \
    r-data.table r-ggplot2 r-scales r-config r-here r-ragg r-reticulate \
    r-tensorflow r-tfruns r-generics r-magrittr r-zeallot r-fastmap r-glue \
    r-cli r-rlang r-dplyr r-r6 r-jsonlite r-withr r-png r-purrr \
    r-rstudioapi r-jpeg r-matrix r-actuar r-lattice r-tweedie r-systemfit \
    r-statmod r-cplm r-mass r-yaml r-rprojroot r-testthat r-remotes
fi
export PATH=/opt/mamba/envs/r/bin:$PATH
mkdir -p /opt/rsrc output/logs
for p in dotty keras3 SynthETIC ChainLadder; do  # dotty: an import of keras3
  if Rscript -e "quit(status = !requireNamespace('$p', quietly = TRUE))"; then
    continue
  fi
  [ -d "/opt/rsrc/$p" ] ||
    git clone -q --depth 1 "https://github.com/cran/$p" "/opt/rsrc/$p"
  R CMD INSTALL --no-docs --no-html "/opt/rsrc/$p"
done
if [ ! -f data/raw/claim-simulation-annual/claims.csv ]; then
  Rscript analysis/00_claim-simulation/short_tailed_claims.R \
    > output/logs/short_tailed_claims.log 2>&1
fi
echo "set up"

#!/usr/bin/env bash
## starts n workers (worker_queue.R) of the NN chain ladder SynthETIC fit
## under the config profile $R_CONFIG_ACTIVE (default age_numeric), detached
## from the shell, one TensorFlow thread each; logs in
## output/logs/nncl_queue_<profile>_<k>.log; usage: run_queue.sh [n]
## (default: the number of cores); stop: pkill -f '^[^ ]*/exec/R .*worker_queue'
set -euo pipefail
cd "$(dirname "$0")/../.."
n="${1:-$(nproc)}"
export R_CONFIG_ACTIVE="${R_CONFIG_ACTIVE:-age_numeric}"
export OMP_NUM_THREADS=1 TF_NUM_INTRAOP_THREADS=1 TF_NUM_INTEROP_THREADS=1
export TF_CPP_MIN_LOG_LEVEL=2
## the R processes of the workers (Rscript runs .../bin/exec/R --file=...)
if pgrep -f '^[^ ]*/exec/R .*worker_queue' > /dev/null; then
  echo "workers are running: stop them first" >&2
  exit 1
fi
## locks of runs a stopped worker did not finish
find data/processed -maxdepth 1 -name "*.rds.lock" -type d -exec rmdir {} +
mkdir -p output/logs
for k in $(seq 1 "$n"); do
  setsid nohup Rscript "Claude outputs/nncl-parallel-workers/worker_queue.R" \
    > "output/logs/nncl_queue_${R_CONFIG_ACTIVE}_${k}.log" 2>&1 < /dev/null &
done
echo "started $n workers (profile $R_CONFIG_ACTIVE)"

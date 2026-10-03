#!/usr/bin/env bash
## starts n worker slots of the NN chain ladder SynthETIC fit under the config
## profile $R_CONFIG_ACTIVE (default age_numeric), detached from the shell,
## one TensorFlow thread each; a slot runs worker_queue.R for m runs at a
## time in a fresh R session (its memory grows with every run) until no run
## is left; logs in output/logs/nncl_queue_<profile>_<k>.log;
## usage: run_queue.sh [n] [m] (default: the number of cores, 8 runs);
## stop: pkill -f '^bash .*worker_slot'; pkill -f '^[^ ]*/exec/R .*worker_queue'
set -euo pipefail
cd "$(dirname "$0")/../.."
n="${1:-$(nproc)}"
m="${2:-8}"
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
w="Claude outputs/nncl-parallel-workers/worker_queue.R"
for k in $(seq 1 "$n"); do
  # status 3: no run left; any other status (done m runs, an error, killed
  # for lack of memory) starts a new session
  setsid nohup bash -c 'while true; do
      Rscript "$1" "$2"; s=$?
      [ "$s" -eq 3 ] && break
      echo "worker_slot: R session ended with status $s, restarting"
    done' worker_slot "$w" "$m" \
    > "output/logs/nncl_queue_${R_CONFIG_ACTIVE}_${k}.log" 2>&1 < /dev/null &
done
echo "started $n worker slots of $m runs (profile $R_CONFIG_ACTIVE)"

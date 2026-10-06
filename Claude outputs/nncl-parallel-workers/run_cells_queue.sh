#!/usr/bin/env bash
## starts n worker slots of the NN chain ladder SynthETIC fit on the laptop's
## cells (worker_cells.R) under the config profile $R_CONFIG_ACTIVE (default
## age_numeric), detached from the shell, one TensorFlow thread each; a slot
## runs worker_cells.R for m runs at a time in a fresh R session (its memory
## grows with every run) until no run is left; $NNCL_SEEDS: the seeds of
## this machine's share, blank separated (default: all seeds);
## logs in output/logs/nncl_cells_<profile>_<k>.log;
## usage: run_cells_queue.sh [n] [m] (default: the number of cores, 8 runs);
## stop: pkill -f '^bash .*worker_slot'; pkill -f '^[^ ]*/exec/R .*worker_cells'
set -euo pipefail
cd "$(dirname "$0")/../.."
n="${1:-$(nproc)}"
m="${2:-8}"
export R_CONFIG_ACTIVE="${R_CONFIG_ACTIVE:-age_numeric}"
export NNCL_SEEDS="${NNCL_SEEDS:-}"
export OMP_NUM_THREADS=1 TF_NUM_INTRAOP_THREADS=1 TF_NUM_INTEROP_THREADS=1
export TF_CPP_MIN_LOG_LEVEL=2
## the R processes of the workers (Rscript runs .../bin/exec/R --file=...)
if pgrep -f '^[^ ]*/exec/R .*worker_cells' > /dev/null; then
  echo "workers are running: stop them first" >&2
  exit 1
fi
## locks of runs a stopped worker did not finish
find data/processed -maxdepth 1 -name "*.rds.lock" -type d -exec rmdir {} +
mkdir -p output/logs
w="Claude outputs/nncl-parallel-workers/worker_cells.R"
for k in $(seq 1 "$n"); do
  # status 3: no run left; status 0: done m runs, a new session takes the
  # next ones; any other status (an error, killed for lack of memory) also
  # starts a new session, but three of them in a row end the slot
  setsid nohup bash -c 'bad=0; while true; do
      Rscript "$1" fit "$2"; s=$?
      [ "$s" -eq 3 ] && break
      if [ "$s" -eq 0 ]; then bad=0; else bad=$((bad + 1)); fi
      echo "worker_slot: R session ended with status $s"
      if [ "$bad" -ge 3 ]; then echo "worker_slot: giving up"; break; fi
    done' worker_slot "$w" "$m" \
    > "output/logs/nncl_cells_${R_CONFIG_ACTIVE}_${k}.log" 2>&1 < /dev/null &
done
echo "started $n worker slots of $m runs (profile $R_CONFIG_ACTIVE," \
  "seeds ${NNCL_SEEDS:-all})"

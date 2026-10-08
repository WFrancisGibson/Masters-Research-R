#!/bin/bash
##########################################
#########  final run: the PBS job of the HPC (Stellenbosch HPC1 and HPC2)
#########  own design, after the cluster's guide
#########  https://www0.sun.ac.za/hpc/index.php?title=HOWTO_submit_jobs
##########################################

## after setup_hpc.sh, from the project root on the login node
## (ssh 26196425@hpc1.sun.ac.za; campus network or VPN):
##   qsub analysis/06_final-run/hpc_job.sh
## The job runs the launcher (launch.py) on one node: first every task under
## the quick profile (the smoke test, which stops the job if a task fails),
## then the final run. A job that ends before all is done (the walltime,
## qdel) is submitted again with the same command and resumes: finished
## runs and tasks are never repeated.
##
## The resources below can be changed on the command line, which wins over
## the #PBS lines:
##   qsub -l select=1:ncpus=64:mem=160GB -l walltime=744:00:00 \
##     analysis/06_final-run/hpc_job.sh
##  ncpus     the R sessions at once (one thread each)
##  mem       about 2.5 GB per session. Asking for more than 96 GB also
##            keeps the job off the 48-core nodes of HPC1 with 96 GB, whose
##            processors (Opteron 6172) have no AVX: TensorFlow does not
##            start there
##  walltime  168 hours is the longest of the queue "week"; up to 744 hours
##            is the queue "month" (fewer cores per user)
## Variables for the job (qsub -v NAME=value,NAME=value):
##  FINAL_RUN_ARGS  further arguments of launch.py, in one text:
##                  qsub -v FINAL_RUN_ARGS="--profile quick" -l walltime=12:00:00 \
##                    analysis/06_final-run/hpc_job.sh
##                  runs the quick profile only (a first try in the queue
##                  "day")
##  R_MODULE        the R module (default app/R/4.5.1), as in setup_hpc.sh
##
## Watch, on the login node:
##   qstat -u $USER
##   tail -n 20 ../Masters-Research-R-results/results/final-run/launch.log
##   (the smoke test: .../final-run/quick/launch.log; the time left, once
##   the benchmark stage is done: .../final-run/status.csv)
## Stop: qdel <job id>. The output of the job itself arrives in the project
## root when it ends (final-run.o<job id>; while it runs: qpeek <job id>).
##
## The results stay under ../Masters-Research-R-results/results (RUN_ROOT),
## in the home folder and not in the scratch space of the node: the run
## files are small and few (one per run), and a job that is killed must
## leave them where the next job finds them. Copy them to the laptop when
## the run is done (README of the results: results_readme.md); from the
## laptop, without the Keras models:
##   ssh 26196425@hpc1.sun.ac.za "tar -czf final-run-results.tar.gz --exclude='*.keras' -C Masters-Research-R-results results"
##   scp 26196425@hpc1.sun.ac.za:final-run-results.tar.gz .
##
## The queue "gpu" of HPC1 (user 26196425 is on its list, ticket ISM-66824)
## is not used by this job: the fits run on processors, one thread per R
## session, with the TensorFlow of requirements.txt (the laptop's, without
## the GPU libraries), and a network of a few hundred weights on 20 x 20
## cells gains nothing from a GPU. Its nodes can still be the faster ones.
## What the queue allows and which nodes it has:
##   qstat -Qf gpu
##   pbsnodes -a | grep -E "^comp|ngpus|ncpus|Qlist"
## and the job on such a node, the resources after what these two show
## (never tried):
##   qsub -q gpu -l select=1:ncpus=<n>:mem=<m>GB:ngpus=1 \
##     analysis/06_final-run/hpc_job.sh

#PBS -N final-run
#PBS -l select=1:ncpus=48:mem=120GB
#PBS -l walltime=168:00:00
#PBS -j oe
#PBS -m abe

cd "${PBS_O_WORKDIR:-.}" || exit 3
if [ ! -f "analysis/06_final-run/launch.py" ]; then
  echo "Submit the job from the project root: cd there, then qsub again."
  exit 3
fi
ROOT="$(pwd)"
PYTHON="$(dirname "${ROOT}")/Masters-Research-R-python/env/bin/python"
SLOTS="${NCPUS:-$(nproc)}"

## only this user reads the results and the temporary files
umask 0077

echo "job ${PBS_JOBID:-none} on $(hostname), ${SLOTS} slots, $(date)"
echo "processor: $(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2)"
if ! grep -q -w avx /proc/cpuinfo; then
  echo "The processor of this node has no AVX: TensorFlow cannot start here."
  echo "Ask for a newer node (more memory per node, or name its resources;"
  echo "pestat lists the nodes; help@sun.ac.za knows how to select them)."
  exit 3
fi

## R of the cluster
module load "${R_MODULE:-app/R/4.5.1}"
if ! command -v Rscript > /dev/null; then
  echo "No Rscript after: module load ${R_MODULE:-app/R/4.5.1}"
  exit 3
fi
if [ ! -x "${PYTHON}" ]; then
  echo "The Python environment is not there: ${PYTHON}"
  echo "Run analysis/06_final-run/setup_hpc.sh on the login node first."
  exit 3
fi

## temporary files of the sessions in the scratch space of the node, not in
## /tmp (the cluster's rule); removed when the job ends
SCRATCH="/scratch-small-local/${PBS_JOBID:-final-run-$$}"
if mkdir -p "${SCRATCH}" 2> /dev/null; then
  export TMPDIR="${SCRATCH}"
else
  SCRATCH=""
fi

## the launcher, with the signals of PBS passed on: qdel and the end of the
## walltime send SIGTERM to this script, and the launcher then stops its R
## sessions (PBS kills what is left some seconds later; the next job clears
## the locks of the runs that were cut off)
"${PYTHON}" "analysis/06_final-run/launch.py" --slots "${SLOTS}" \
  ${FINAL_RUN_ARGS:-} &
LAUNCHER=$!
trap 'kill -TERM "${LAUNCHER}" 2> /dev/null' TERM INT HUP
wait "${LAUNCHER}"
CODE=$?
## a signal ends the wait before the launcher has ended: wait again
while kill -0 "${LAUNCHER}" 2> /dev/null; do
  wait "${LAUNCHER}"
  CODE=$?
done

if [ -n "${SCRATCH}" ]; then
  rm -rf "${SCRATCH}"
fi
echo "launcher ended with exit code ${CODE}, $(date)"
echo "(0 all done; 1 tasks failed or blocked; 2 another launcher runs;"
echo " 3 stopped: qsub again to resume)"
exit "${CODE}"

#!/usr/bin/env bash

## Global variables
# The directory of the script
BASE_DIR="$(cd "$( dirname "${BASH_SEURCE[0]}" )" && pwd )"

## Main
# Check system requirements
command -v make >/dev/null 2>&1 || { echo >&2 "'make' has to be installed"; exit 1; }
command -v Rscript >/dev/null 2>&1 || { echo >&2 "'R' has to be installed"; exit 1; }

# Download the benchmarks and build them
echo "Download and build benchmarks"

make -C "${BASE_DIR}/benchmarks" || { echo >&2 "Something went wrong when building the benchmarks"; exit 1; }

# Measure all the necessary data
echo "Run benchmarks"

export BENCH_DIR="${BASE_DIR}/benchmarks/NPB3.3.1/NPB3.3-OMP/bin"

export PERF_DIR="${PERF_DIR:-${BASE_DIR}/perf_data}"
export CSV="${CSV:-${BASE_DIR}/bench_data.csv}"
export RATE_MS=${RATE_MS:-1000}
BENCH_ERROR_LOG=${BENCH_ERROR_LOG:-bench.log}

# Make sure that the system is prepared accordingly
sudo $BASE_DIR/tools/disable_energy_automatisms.sh >$BENCH_ERROR_LOG 2>&1

$BASE_DIR/tools/bench.sh 2>$BENCH_ERROR_LOG || { echo >&2 "Something went wrong when running the benchmarks"; exit 1; }

# Generate the models
echo "Generate models"

export R_LIBS_USER=~/.local/lib64/R/library
mkdir -p ${R_LIBS_USER}
Rscript "${BASE_DIR}/tools/analysis.R" $CSV

#!/usr/bin/env bash

## Global variables
# The directory of the script
BASE_DIR="$(cd "$( dirname "${BASH_SEURCE[0]}" )" && pwd )"

## Main
# Download the benchmarks and build them
make -C "${BASE_DIR}/benchmarks"

# Measure all the necessary data
export BENCH_DIR="${BASE_DIR}/benchmarks/NPB3.3.1/NPB3.3-OMP/bin"

export PERF_DIR="${PERF_DIR:-${BASE_DIR}/perf_data}"
export CSV="${CSV:-${BASE_DIR}/bench_data.csv}"
export RATE_MS=${RATE_MS:-1000}

$BASE_DIR/tools/bench.sh

# Generate the models
Rscript "${BASE_DIR}/tools/analysis.R" $CSV

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

export NPB_DIR="${BASE_DIR}/benchmarks/NPB3.3.1/NPB3.3-OMP/bin"
export ERIS_DIR=${ERIS_DIR:-/root/eris}
export ERIS_CTRL_DIR=${ERIS_CTRL_DIR:-/root/eris-ctrl}

export NPB_DATA_DIR=${NPB_DATA_DIR:-"${BASE_DIR}/npb_data"}
export NPB_CSV=${NPB_CSV:-"${BASE_DIR}/npb_bench.csv"}
export ERIS_DATA_DIR=${ERIS_DATA_DIR:-"${BASE_DIR}/eris_data"}
export ERIS_CSV=${ERIS_CSV:-"${BASE_DIR}/eris_bench.csv"}

export RATE_MS=${RATE_MS:-1000}

NPB_ERROR_LOG=${NPB_ERROR_LOG:-npb.log}
ERIS_ERROR_LOG=${ERIS_ERROR_LOG:-eris.log}

# Make sure that the system is prepared accordingly
sudo $BASE_DIR/tools/disable_energy_automatisms.sh

# Run the benchmarks
$BASE_DIR/tools/bench_npb.sh 2>$NPB_ERROR_LOG || { echo >&2 "Something went wrong when running the NPB benchmarks"; exit 1; }
$BASE_DIR/tools/bench_eris.sh 2>$ERIS_ERROR_LOG || { echo >&2 "Something went wrong when running the ERIS benchmarks"; exit 1; }

# Generate the models
echo "Generate models"

export R_LIBS_USER=~/.local/lib64/R/library
mkdir -p ${R_LIBS_USER}
Rscript "${BASE_DIR}/tools/analysis.R" $NPB_CSV $ERIS_CSV

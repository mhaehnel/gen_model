#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/msr_tool.sh

ensure MSR_POWER_CTL:1=0
ensure MSR_POWER_CTL:19=1
ensure MSR_POWER_CTL:20=1

printRegs


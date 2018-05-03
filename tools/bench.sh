#!/usr/bin/env bash

## Global Variables
# Number of different frequencies that should be tested
FREQ_STEPS=${FREQ_STEPS:-6}

# Number of different cpu counts that should be tested
CPU_STEPS=${CPU_STEPS:-2}

# Which technique should be used to generate the tested frequencies
# Possible values are:
# 'distance' (tries to even out distance between frequencies)
# 'stepwise' (tries to even out distance between steps)
FREQ_STEP_MODE=${FREQ_STEP_MODE:-distance}

# The rate at which perf should report the counter values (measurement granularity)
RATE_MS=${RATE_MS:-500}

# The logfile for the output of elab
ELAB_LOG=${ELAB_LOG:-/dev/null}

# The directory where the intermediate output files of perf should be saved
PERF_DIR=${PERF_DIR:-perf_csv}

# The file where the final CSV output should be saved to
CSV=${CSV:-bench.csv}

# The directories where the script and the benchmark files are located
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}"  )" && pwd )"
BENCH_DIR=${BENCH_DIR:-"$BASE_DIR/NPB3.3.1/NPB3.3-OMP/bin"}

# The additional events that we must count
INSTR_EVENT=${E_INSTR:-instructions}
CYCLE_EVENT=${E_CYCLE:-cpu-cycles}
CYCLE_REF_EVENT=${E_CYCLE_REF:-ref-cycles}
BRANCH_EVENT=${E_BRANCH:-cpu/event=0xC4,umask=0x0/u}
CACHE_EVENT=${E_CACHE:-cache-references}
MEMORY_EVENT=${E_MEMORY:-cache-misses}
AVX_EVENT=${E_AVX:-cpu/event=0xC7,umask=0x3C/u}

## Helper functions
# Command to reverse arrays
arr_reverse() { declare ARR="$1[@]"; declare -ga $1="( `printf '%s\n' "${!ARR}" | tac` )"; }


## Main

# Check requirements for this script to work
command -v elab >/dev/null 2>&1 || { echo >&2 "'elab' has to be installed"; exit 1; }
command -v perf >/dev/null 2>&1 || { echo >&2 "'perf' has to be installed"; exit 1; }
perf list | grep "power/energy-cores" >/dev/null 2>&1 || { echo >&2 "need perf support to read RAPL counters"; exit 1; }

if [ $(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver) != "acpi-cpufreq" ]; then
    if [ $(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver) == "intel_pstate" ]; then
        cat >&2 << EOF
Currently running intel_pstate cpu scaling driver! Need to use the acpi-cpufreq cpu scaling driver!
Possible fixes:
  - disable intel_pstate driver via commandline (intel_pstate=disable)
EOF
    else
        echo "Running a not-supported cpu scaling driver! Need to use acpi-cpufreq cpu scaling driver!"
    fi
    exit 1
fi

# Setup the script's internals
min_freq=$(< /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq)
max_freq=$(< /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
all_freqs=( $(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies) )
cpu_gov=$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
nr_cpus=$(grep "cpu cores" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/ //g')
nr_hts=$(grep "siblings" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/ //g')

[ $FREQ_STEPS -ge 2 ] || { echo >&2 "Must use at least 2 frequency steps (current: FREQ_STEPS=$FREQ_STEPS)"; exit 1; }
[ $FREQ_STEPS -le ${#all_freqs[@]} ] || { echo >&2 "Must use less frequency steps than available frequencies (current: FREQ_STEPS=$FREQ_STEPS, frequencies=${#all_freqs[@]})"; exit 1; }
[ $CPU_STEPS -ge 2 ] || { echo >&2 "Must use at least 2 CPU steps (current: CPU_STEPS=$CPU_STEPS)"; exit 1; }
[ $CPU_STEPS -le $nr_cpus ] || { echo >&2 "Must use less CPU steps than available CPUs (current: CPU_STEPS=$CPU_STEPS, CPUs=$nr_cpus)"; exit 1; }

# Check that we have enough permissions to make system-wide perf measurements.
# To be able to do this we need CAP_SYS_ADMIN or perf need to be setup properly.
if [ $EUID != 0 ]; then
    # Not running as root is OK if perf_paranoid is set to -1
    if [ $(< /proc/sys/kernel/perf_event_paranoid) -ne -1 ]; then
        cat >&2 << EOF
Need to be able to monitor system-wide perf events!
Possible fixes:
  - run script as root
  - echo -1 > /proc/sys/kernel/perf_event_paranoid to allow all users to monitor system-wide pref events
EOF
        exit 1;
    fi
fi

arr_reverse all_freqs

declare -a freqs
if [ $FREQ_STEP_MODE = stepwise ]
then
    #Find values in FREQ_STEP distance between indices
    declare -a indices="(
        $(
            bc -l <<< "for (i=0; i < ${#all_freqs[@]}; i+=(${#all_freqs[@]}-1)/(${FREQ_STEPS}-1)) i" | 
            xargs printf "%.0f\n"
         ) )"
    for i in ${indices[@]}; do freqs+=("${all_freqs[$i]}"); done
elif [ $FREQ_STEP_MODE = distance ]
then
    freq_step=$((($max_freq - $min_freq)/($FREQ_STEPS - 1)))
    freq=$min_freq
    freqs=( $min_freq )
    if [ $freq_step -gt 0 ]; then
        for i in $(seq 1 $(($FREQ_STEPS - 2))); do
            freq=$(($freq + $freq_step))
            #Find closest existing freq ...
            prev=${all_freqs[0]}
            prev_dist=$(($prev-$freq))
            for f in ${all_freqs[@]:1}; do
                cur=$f
                cur_dist=$(( $cur-$freq ))
                if [ ${cur_dist#-} -gt ${prev_dist#-} ] #Are we getting farther away?
                then
                    freqs+=( $prev )
                    break
                fi
                prev=$cur
                prev_dist=$cur_dist
            done
            if [ $prev -eq ${all_freqs[-1]} ] 
            then
                freqs+=( $prev )
            fi
        done
    fi
    freqs+=( $max_freq )
else
    echo >&2 "Unknown FREQ_STEP_MODE ($FREQ_STEP_MODE)"; exit 1
fi

cpu_step=$(($nr_cpus/$CPU_STEPS))
cpu=1
cpus="1"
if [ $cpu_step -gt 0 ]; then
    for i in $(seq 1 $(($CPU_STEPS - 2))); do
        cpu=$(($cpu + $cpu_step))
        cpus="$cpus $cpu"
    done
fi
cpus="$cpus $nr_cpus"

cat << EOF
Detected system configuration:
CPUs: $nr_cpus ($nr_hts HTs)
Frequencies: $min_freq-$max_freq (@${cpu_gov}) {${all_freqs[@]}}

Using the following steps:
CPUs ($CPU_STEPS steps): $cpus
Frequencies ($FREQ_STEPS steps): ${freqs[@]}

Measurement rate: $RATE_MS ms
EOF

read -en1 -p "Continue? [Y/n] " answer
case $answer in
    N|n)
        exit 0
        ;;
    Y|y|'')
        ;;
    *)
        echo "Huh? Aborting";
        exit 1
        ;;
esac

# Fully abort the script upon CTRL-C
trap "echo Aborting!; exit 0;" SIGINT SIGTERM

mkdir -p $PERF_DIR

exec 3<> $ELAB_LOG
elab ht enable >&3
elab frequency userspace >&3

echo -ne "\nStart benchmarking\n"
for bench in bt.A cg.B dc.A ep.B ft.C is.C lu.B mg.C sp.B ua.A; do
    echo -n "$bench: "

    bin="$BENCH_DIR/${bench}.x"

    for ht in enable disable; do
        if [ $ht == enable ]; then
            echo -n "H"
        fi

        for cpu in $cpus; do
            echo -n " $cpu"

            for freq in ${freqs[@]}; do
                echo -n "@$(($freq/1000))"

                elab frequency $(($freq/1000)) >&3

                perf_counter_out_tmp="$(mktemp)"
                perf_counter_out="$PERF_DIR/${bench}.${ht}.${cpu}.${freq}.$(date +%Y_%m_%d-%H_%M_%S).ctr.csv"
                perf_energy_out="$PERF_DIR/${bench}.${ht}.${cpu}.${freq}.$(date +%Y_%m_%d-%H_%M_%S).energy.csv"

                if [ $ht == disable ]; then
                    taskset_cpus="0-$(($cpu-1))"
                    c=$cpu
                else
                    taskset_cpus="0-$(($cpu-1)),$nr_cpus-$(($nr_cpus+$cpu-1))"
                    c=$(($cpu*2))
                fi

                if [ $ht == disable ]; then
                    elab ht disable >&3
                fi

                taskset -c $taskset_cpus \
                    perf stat -a -e power/energy-cores/,power/energy-ram/,power/energy-pkg/ -I $RATE_MS -x \; -o "$perf_energy_out" \
                    perf stat -e $INSTR_EVENT,$CYCLE_EVENT,$CYCLE_REF_EVENT,$BRANCH_EVENT,$CACHE_EVENT,$MEMORY_EVENT,$AVX_EVENT -I $RATE_MS -x \; -o "$perf_counter_out_tmp" \
                    $bin >/dev/null

                if [ $ht == disable ]; then
                    elab ht enable >&3
                fi

                mv "$perf_counter_out_tmp" "$perf_counter_out"

                # rename the events to predefined names
                sed -i "s#${INSTR_EVENT}#instructions#g" $perf_counter_out
                sed -i "s#${CYCLE_EVENT}#cpu-cycles#g" $perf_counter_out
                sed -i "s#${CYCLE_REF_EVENT}#cpu-cycles-ref#g" $perf_counter_out
                sed -i "s#${BRANCH_EVENT}#branch-events#g" $perf_counter_out
                sed -i "s#${CACHE_EVENT}#cache-events#g" $perf_counter_out
                sed -i "s#${MEMORY_EVENT}#memory-events#g" $perf_counter_out
                sed -i "s#${AVX_EVENT}#avx-events#g" $perf_counter_out

                # We are done with the benchmark -- parse the perf output file
                $BASE_DIR/parse_csv.py $bench $ht $c $freq $perf_counter_out $perf_energy_out -o $CSV --append
            done
        done
    done
    echo -ne "\n"
done

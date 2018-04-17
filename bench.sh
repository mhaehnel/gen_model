#!/usr/bin/env bash

# Global Variables
FREQ_STEPS=${FREQ_STEPS:-6}
CPU_STEPS=${CPU_STEPS:-2}

#Either 
# 'distance' (tries to even out distance between frequencies)
# 'stepwise' (tries to even out distance between steps)
FREQ_STEP_MODE=${FREQ_STEP_MODE:-distance}

BINDIR=${BIN_DIR:-"NPB3.3.1/NPB3.3-OMP/bin"}

RATE_MS=${RATE_MS:-500}


# Check requirements for this script to work
#command -v elab >/dev/null 2>&1 || { echo >&2 "'elab' has to be installed"; exit 1; }
command -v perf >/dev/null 2>&1 || { echo >&2 "'perf' has to be installed"; exit 1; }
perf list | grep "power/energy-cores" >/dev/null 2>&1 || { echo >&2 "need perf support to read RAPL counters"; exit 1; }

#Command to reverse arrays
arr_reverse() { declare ARR="$1[@]"; declare -ga $1="( `printf '%s\n' "${!ARR}" | tac` )"; }
 
# Setup the script's internals
min_freq=$(< /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq)
max_freq=$(< /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
all_freqs=( $(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies) )
cpu_gov=$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
nr_cpus=$(grep "cpu cores" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/ //g')
nr_hts=$(grep "siblings" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/ //g')

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

echo -ne "\nStart benchmarking\n"
for bench in bt.A cg.B dc.A ep.B ft.C is.C lu.B mg.C sp.B ua.A; do
    echo -n "$bench: "

    bin="$BINDIR/${bench}.x"
    perfout=$(mktemp ${bench}.XXXX.csv)

    for ht in enable disable; do
        if [ $ht == enable ]; then
            echo -n "H"
        fi

        elab ht $ht

        for cpu in $cpus; do
            echo -n " $cpu"

            for freq in ${freqs[@]}; do
                echo -n "@$(($freq/1000))"

                elab frequency $(($freq/1000))

                if [ $ht == disable ]; then
                    taskset_cpus="0-$(($cpu-1))"
                else
                    taskset_cpus="0-$(($cpu-1)),$nr_cpus-$(($nr_cpus+$cpu-1))"
                fi

                taskset -c $taskset_cpus perf stat -e cpu-cycles,instructions,avx_insts.all,cache-misses,cache-references,energy-cores,energy-ram,energy-pkg -I $RATE_MS -x \; -o $perfout $bin >/dev/null
            done
        done
    done
    echo -ne "\n"
done

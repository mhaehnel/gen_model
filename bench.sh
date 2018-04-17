#!/usr/bin/env bash

# Global Variables
FREQ_STEPS=6
CPU_STEPS=2

BINDIR="NPB3.3.1/NPB3.3-OMP/bin"

RATE_MS=500


# Check requirements for this script to work
#command -v elab >/dev/null 2>&1 || { echo >&2 "'elab' has to be installed"; exit 1; }
command -v perf >/dev/null 2>&1 || { echo >&2 "'perf' has to be installed"; exit 1; }
perf list | grep "power/energy-cores" >/dev/null 2>&1 || { echo >&2 "need perf support to read RAPL counters"; exit 1; }

# Setup the script's internals
min_freq=$(< /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq)
max_freq=$(< /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
cpu_gov=$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
nr_cpus=$(grep "cpu cores" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/ //g')
nr_hts=$(grep "siblings" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/ //g')

freq_step=$((($max_freq - $min_freq)/($FREQ_STEPS - 1)))
freq=$min_freq
freqs="$min_freq"
if [ $freq_step -gt 0 ]; then
    for i in $(seq 1 $(($FREQ_STEPS - 2))); do
        freq=$(($freq + $freq_step))
        freqs="$freqs $((($freq / 10000) * 10000))"
    done
fi
freqs="$freqs $max_freq"

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
Frequencies: $min_freq-$max_freq (@${cpu_gov})

Using the following steps:
CPUs ($CPU_STEPS steps): $cpus
Frequencies ($FREQ_STEPS steps): $freqs

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

            for freq in $freqs; do
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

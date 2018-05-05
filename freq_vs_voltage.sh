#!/usr/bin/env bash
#Generates a CSV with the voltage for every frequency
#Sadly this is dependent on load :/

( echo "Frequency,Voltage"
  for f in `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies`; do
	elab frequency $(($f/1000)) >/dev/null
	sleep 2
    echo "$(elab frequency | cut -f4 -d\ ),$(sensors | grep Vcore | cut -f2 -d+ | cut -f1 -d\ )"
  done 
) | tee freq_voltage.csv

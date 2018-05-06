#!/usr/bin/env bash
#Generates a CSV with the voltage for every frequency
#Sadly this is dependent on load :/

echo "Frequency_req,Frequency_act,Voltage"
for f in `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies`; do
	elab frequency $(($f/1000)) >/dev/null
	sleep 2
    echo "$(($(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed)/1000)),$(($(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)/1000)),$(< /sys/class/hwmon/hwmon2/in0_input)"
done 

#!/usr/bin/env python3
import hardware
from eris import Eris

#TODO: These parameters should rather come from the hardware model in the future
print("Generating Pareto frontier for parameters ...")
for freq in range(800000,3600000,200000):
    for cores in range(1,5,1):
        for ht in [0,1]:
            cpus = (ht+1)*cores
            #Benchmark names should come from sw model
            for c in ["deduplication-scan","deduplication-indexed","tatp"]:
                params = Eris(cpus).benchmarks(c)
                ipc = hardware.IPC(ht=ht,memory_heaviness=params["memory_heaviness"](),avx_heaviness=params["avx_heaviness"](),compute_heaviness=params["compute_heaviness"](),cache_heaviness=params["cache_heaviness"](),cpus=cpus,freq=freq)
                p_pkg = hardware.P_PKG(memory_heaviness=params["memory_heaviness"](),IPC=ipc,freq=freq,avx_heaviness=params["avx_heaviness"](),compute_heaviness=params["compute_heaviness"](),cpus=cpus)
                print({"bench":c,"freq": freq,"cpus":cpus, "ht":ht, "cores":cores,"ipc":ipc,"p_pkg": p_pkg})

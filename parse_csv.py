#!/usr/bin/env python3

import sys

if len(sys.argv) != 6:
    print("usage: {} BENCH HT CPUS FREQ PERFCSV".format(sys.argv[0]))
    sys.exit(1)

bench = sys.argv[1]
ht = sys.argv[2]
cpus = sys.argv[3]
freq = sys.argv[4]
perfcsv = sys.argv[5]

with open(perfcsv) as perffile:
    lines = perffile.readlines()

values = []
last_ts = None

for l in lines:
    l = l.strip()

    if l.startswith("#"):
        # Skip the first line
        continue

    if  len(l) == 0:
        # Skip empty lines
        continue

    eles = l.split(";")
    ts = float(eles[0].strip())
    name = eles[3]
    value = eles[1].strip()

    if last_ts == None:
        values.append({ "ts" : ts, "t_diff" : ts })
    elif ts != last_ts:
        values.append({ "ts" : ts, "t_diff" : ts - last_ts })

    last_ts = ts
    values[-1][name] = value

counters = values[0].keys()
print(";".join(["bench", "ht", "cpus", "freq"] + list(counters)))

for val in values:
    items = [bench, ht, cpus, freq]
    for c in counters:
        items.append(str(val[c]))

    print(";".join(items))


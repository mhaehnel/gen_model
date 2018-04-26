#!/usr/bin/env python3

import sys
import os.path
import argparse


def output_headers(headers, sep, outfile):
    print(sep.join(headers), file=outfile)

def output_row(values, headers, sep, outfile):
    vals = []
    for h in headers:
        if h in values:
            vals.append(str(values[h]))
        else:
            vals.append('')

    print(sep.join(vals), file=outfile)

class MatchError(RuntimeError):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

def find_perf_counter(values, last_best, current_ts, max_diff, force_next=False):
    # Check if the one we used last time is still close enough
    if not force_next and abs(values[last_best]["ts"] - current_ts) < max_diff:
        return last_best

    # Otherwise search starting from the last one another value that fits better
    for i in range(last_best+1, len(values)):
        if abs(values[i]["ts"] - current_ts) < max_diff:
            return i

    raise MatchError("Can't find performance counter match for energy value: {}".format(current_ts))


parser = argparse.ArgumentParser()
parser.add_argument("bench", action="store", help="the benchmark name")
parser.add_argument("ht", action="store", help="the hyperthreading mode")
parser.add_argument("cpus", action="store", help="the number of cpus used")
parser.add_argument("freq", action="store", help="the frequency used")
parser.add_argument("ctrcsv", action="store", help="the perf csv-like file containing the counters")
parser.add_argument("energycsv", action="store", help="the perf csv-like file containing the energy")
parser.add_argument("-o", "--outfile", action="store", default=None, help="save csv output to this file")
parser.add_argument("--sep", action="store", default=";", help="use this separator (default: ;)")
parser.add_argument("--append", action="store_true", default=False, help="append if the output file already exists")

args = parser.parse_args()

bench = args.bench
ht = args.ht
cpus = args.cpus
freq = args.freq
ctr_csv = args.ctrcsv
energy_csv = args.energycsv

outfile = args.outfile
sep = args.sep
append = args.append

try:
    with open(ctr_csv) as perffile:
        ctr_lines = perffile.read().splitlines()
except IOError:
    print("Can't open counter perf csv-file", file=sys.stderr)
    sys.exit(1)

try:
    with open(energy_csv) as perffile:
        energy_lines = perffile.read().splitlines()
except IOError:
    print("Can't open energy perf csv-file", file=sys.stderr)
    sys.exit(1)


# Parse the data from the perf csv-files
values = []
last_ts = None
err_names = []
# First read in the performance counter values
for l in ctr_lines:
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
        values.append({ "ts" : ts, "t_diff" : ts, "bench" : bench, "ht" : ht, "cpus" : cpus, "freq" : freq })
        last_ts = ts
    elif ts != last_ts:
        if err_names:
            print("WARNING: uncounted value for {} in {} at time {} -- Skipping record".format(err_names,ctr_csv,last_ts),file=sys.stderr)
            err_names = []
            values = values[:-1]
        values.append({ "ts" : ts, "t_diff" : ts - last_ts, "bench" : bench, "ht" : ht, "cpus" : cpus, "freq" : freq })
        last_ts = ts
    if value == "<not counted>":
        err_names.append(name)

    values[-1][name] = value

# Next read in the RAPL counter values and try to match them with the performance counters
MAX_DIFF = 0.02      # The maximum difference in the time stamps to still be counted equal (seconds)
last_val = 0

for l in energy_lines:
    if l.startswith("#"):
        # Skip the first line
        continue

    if len(l) == 0:
        # Skip empty lines
        continue

    eles = l.split(";")
    ts = float(eles[0].strip())
    name = eles[3]
    value = float(eles[1].strip())

    try:
        last_val = find_perf_counter(values, last_val, ts, MAX_DIFF)
    except MatchError as e:
        print("WARNING: " + str(e), file=sys.stderr)
        continue

    if name in values[last_val]:
        # Try if the next performance counter value might fit as well
        try:
            last_val = find_perf_counter(values, last_val, ts, MAX_DIFF, True)
        except MatchError as e:
            print("WARNING: summing up duplicate energy value at time {} (energy timestamp: {})".format(values[last_val]["ts"], ts), file=sys.stderr)
            values[last_val][name] += value
    else:
        values[last_val][name] = value


# Done parsing, create the output
columns = list(values[0].keys())
needs_header = True
out = sys.stdout

if outfile:
    if append and os.path.isfile(outfile):
        try:
            out = open(outfile)
            header = out.readline().rstrip('\n')

            if len(header) != 0:
                columns = header.split(sep)
                needs_header = False

            out.close()

            out = open(outfile, "a")
        except IOError:
            print("Can't open output file for append")
            sys.exit(1)
    else:
        try:
            out = open(outfile, "w")
        except IOError:
            print("Can't open output file")
            sys.exit(1)

# Create the output
if needs_header:
    output_headers(columns, sep, out)
for vals in values:
    output_row(vals, columns, sep, out)

if outfile:
    out.close()

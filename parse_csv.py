#!/usr/bin/env python3

import sys
import os.path
import argparse


def output_headers(headers, sep, outfile):
    print(sep.join(headers), file=outfile)

def output_row(values, headers, sep, outfile):
    print(sep.join([str(values[h]) for h in headers]), file=outfile)


parser = argparse.ArgumentParser()
parser.add_argument("bench", action="store", help="the benchmark name")
parser.add_argument("ht", action="store", help="the hyperthreading mode")
parser.add_argument("cpus", action="store", help="the number of cpus used")
parser.add_argument("freq", action="store", help="the frequency used")
parser.add_argument("csv", action="store", help="the perf csv-like file")
parser.add_argument("-o", "--outfile", action="store", default=None, help="save csv output to this file")
parser.add_argument("--sep", action="store", default=";", help="use this separator (default: ;)")
parser.add_argument("--append", action="store_true", default=False, help="append if the output file already exists")

args = parser.parse_args()

bench = args.bench
ht = args.ht
cpus = args.cpus
freq = args.freq
perfcsv = args.csv

outfile = args.outfile
sep = args.sep
append = args.append

try:
    with open(perfcsv) as perffile:
        lines = perffile.read().splitlines()
except IOError:
    print("Can't open perf csv-file", file=sys.stderr)
    sys.exit(1)

# Parse the data from the perf csv-file
values = []
last_ts = None

for l in lines:
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
        values.append({ "ts" : ts, "t_diff" : ts - last_ts, "bench" : bench, "ht" : ht, "cpus" : cpus, "freq" : freq })
        last_ts = ts

    values[-1][name] = value


columns = ["bench", "ht", "cpus", "freq"] + list(values[0].keys())
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

#!/usr/bin/env python3

import csv, sys, argparse

parser = argparse.ArgumentParser(description='Extract pareto front');
parser.add_argument('-f',required=True)
parser.add_argument('fields', metavar='fields', nargs='+')
args = parser.parse_args()

if (len(args.fields) < 2):
    print("Need at least two fields to build paretofront!");
    sys.exit(-1)

if any([x[0] not in ['>','<'] for x in args.fields]):
    print("Fields must indicate minimization (<) or maximization (>) before name")
    sys.exit(-2)

def better_aspect(row1,row2,aspect):
    if aspect[0] == '>':
        return float(row1[aspect[1:]]) >= float(row2[aspect[1:]])
    return float(row1[aspect[1:]]) <= float(row2[aspect[1:]])

better = lambda row1,row2 : all([better_aspect(row1,row2,aspect) for aspect in args.fields])

with open(args.f, newline='') as f:
    reader = csv.DictReader(f)
    data = [row for row in reader]
    pareto = list()
    print(','.join(data[0].keys()))
    for r in data:
        for d in data:
            if d != r and better(d,r): break;
        else:
            print(','.join(r.values()))

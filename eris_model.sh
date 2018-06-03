#ERIS_MERGE=Y PREFILTER="select * from bench where t_diff>0.05" BENCHES_EXCLUDE=is.C,dc.A Rscript tools/analysis.R bench.csv eris.csv
./eris_test.py
for b in deduplication-scan deduplication-indexed tatp; do
	tools/pareto.py -f csv/modeled_${b}.csv '<p_pkg' '>tps' >csv/modeled_pareto_${b}.csv
done
gnuplot -e "set datafile separator ';'; set terminal dumb ansi size $(tput cols),$(tput lines);
	plot 'csv/modeled_pareto_deduplication-scan.csv' using \"tps\":\"p_pkg\" t 'dedup-scan',
	     'csv/modeled_pareto_deduplication-indexed.csv' using \"tps\":\"p_pkg\" t 'dedup-indexed',
	     'csv/modeled_pareto_tatp.csv' using \"tps\":\"p_pkg\" t 'tatp'"

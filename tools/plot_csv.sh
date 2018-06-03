#Argument is CSV File

FILE=$1
shift
FILTERS=( "$@" )

printf "X Axis:\n==============\n"
select x_value in $(head -1 ${FILE} | tr ',' '\n'); do [ -z $REPLY ] || break; done
printf "Y Axis:\n==============\n"
select y_value in $(head -1 ${FILE} | tr ',' '\n'); do [ -z $REPLY ] || break; done

while true; do
	echo -n "Specify filter or <RETURN> if done >" 
	IFS=$'\n' read add_filter
	[ -z $add_filter ] && break
	FILTERS+=( $add_filter )
done

if [ $x_value == \"\" ]; then
	plot_cmd="${y_value}"
else
	plot_cmd="${x_value}:${y_value}"
fi

#Build filters
if [ ${#FILTERS[@]} -eq 0 ]; then
	filter=""
else
	filter="/"
	for f in "${FILTERS[@]}"; do
		filter="${filter}${f}/ && /"
	done
	filter="${filter}/"
fi

[ "#$filter" == "#" ] || echo "Filtering for: $filter"
echo "Plotting: ${plot_cmd}"

(
	head -1 ${FILE} | sed -e s/\"//g;
	[ "#$filter" == "#" ] && tail +2 $FILE || awk "$filter" $FILE
) | gnuplot -e "set datafile separator comma; set terminal dumb size 170,40; plot '<cat' using ${plot_cmd}"

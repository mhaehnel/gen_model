#!/bin/bash

declare -A MSR_POWER_CTL=(
	[NAME]=MSR_POWER_CTL [ADDR]=0x1FC [DESC]="Power Control Register" [DOMAIN]=Core [MODE]=RW
	[BIT1]="C1E Enable" [DOMAIN1]=Package
	[BIT19]="Disable Race To Halt Optimization"
	[BIT20]="Disable Energy Efficiency Optimization"
)

declare -A IA32_MISC_ENABLE=(
	[NAME]=IA32_MISC_ENABLE [ADDR]=0x1A0 [DESC]="Enable Misc. Processor Features" [DOMAIN]=Thread [MODE]=RW
	[BIT0]="Fast-Strings Enable"
	[BIT7]="Performance Monitoring Available" [MODE7]=RO
	[BIT11]="Branch Trace Storage Unavailable" [MODE11]=RO
	[BIT12]="Processor Event Based Sampling Unavailable" [MODE12]=RO
	[BIT16]="Enhanced Intel SpeedStep Technology Enable" [DOMAIN16]=Package
	[BIT18]="Enable Monitor FSM"
	[BIT22]="Limit CPUID Maxval"
	[BIT23]="xTPR Message Disable"
	[BIT34]="XD Bit DIsable"
	[BIT38]="Turbo Mode Disable" [DOMAIN38]=Package
)

declare -A IA32_HWP_REQUEST=(
	[NAME]=IA32_HWP_REQUEST [ADDR]=0x774 [DESC]="HWP Request Control" [DOMAIN]=Thread [MODE]=RW
	[BIT0-7]="Minimum Performance"
	[BIT8-15]="Maximum Performance"
	[BIT16-23]="Desired Performance"
	[BIT24-31]="Energy Performance Preference"
	[BIT32-41]="Activity Window"
	[BIT42]="Package Control"
	[BIT59]="Activity Window Valid"
	[BIT60]="EPP Valid"
	[BIT61]="Desired Valid"
	[BIT62]="Minimum Valid"
	[BIT63]="Maximum Valid"
)

#UNUSED
declare -A IA32_HWP_REQUEST_PKG=(
	[NAME]=IA32_HWP_REQUEST_PKG [ADDR]=0x772 [DESC]="HWP Package Request Control" [DOMAIN]=Thread [MODE]=RW
	[BIT0-7]="Minimum Performance"
	[BIT8-15]="Maximum Performance"
	[BIT16-23]="Desired Performance"
	[BIT24-31]="Energy Performance Preference"
	[BIT32-41]="Activity Window"
)

declare -A IA32_HWP_CAPABILITIES=(
	[NAME]=IA32_HWP_CAPABILITIES [ADDR]=0x771 [DESC]="HWP Performance Range Enumeration" [DOMAIN]=Thread [MODE]=RO
	[BIT0-7]="Highest Performance"
	[BIT8-15]="Guaranteed Performance"
	[BIT16-23]="Most Efficient Performance"
	[BIT24-31]="Lowest Performance"
)

#TODO: Mode is R/W1Once
declare -A IA32_PM_ENABLE=(
	[NAME]=IA32_PM_ENABLE [ADDR]=0x770 [DESC]="Enable/Disable HWP" [DOMAIN]=Package [MODE]=RW
	[BIT0]="HWP Enabled"
)

declare -A IA32_HWP_STATUS=(
	[NAME]=IA32_HWP_STATUS [ADDR]=0x777 [DESC]="Log bits for HWP" [DOMAIN]=Thread [MODE]=RW
	[BIT0]="Guaranteed Performance Change"
	[BIT2]="Excursion to Minimum"
)

declare -a MSRS=( MSR_POWER_CTL IA32_MISC_ENABLE IA32_PM_ENABLE IA32_HWP_CAPABILITIES IA32_HWP_REQUEST IA32_HWP_STATUS)

CPUNODES=$(find /dev/cpu -mindepth 1 -type d | sort)
declare -a THREADS=() CORES=() PACKAGES=()

for i in ${CPUNODES[@]}; do
	THREADS+=(${i##*/})
done

for i in ${THREADS[@]}; do
	[[ $(< /sys/devices/system/cpu/cpu${i}/topology/thread_siblings_list) =~ ^$i ]] && CORES+=($i)
done

for i in ${THREADS[@]}; do
	[[ $(< /sys/devices/system/cpu/cpu${i}/topology/core_siblings_list) =~ ^$i ]] && PACKAGES+=($i)
done

if [ ! -z $DEBUG ]; then
	echo "Threads: ${THREADS[@]}"
	echo "Cores: ${CORES[@]}"
	echo "Packages: ${PACKAGES[@]}"
fi

#Generate MSR Map ...
declare -A MSR_NAME=()
for i in ${MSRS[@]}; do
	declare -n ptr="$i"
	MSR_NAME[${ptr[NAME]}]=$i
done

declare -A MSR_ADDR=()
for i in ${MSRS[@]}; do
	declare -n ptr="$i"
	MSR_ADDR[${ptr[ADDR]}]=$i
done

declare -A COLOR=( [Green]="\e[32m" [Red]="\e[31m" [Default]="\e[39m" [Yellow]="\e[33m" [White]="\e[97m" [Cyan]="\e[36m")

#Comamnds
list() {
	for i in ${MSRS[@]}; do
		declare -n ptr="$i"
		printf "${ptr[NAME]}[${ptr[ADDR]}] -- ${ptr[DESC]}\n"
		for k in $( echo ${!ptr[@]} | grep -oP '\bBIT[0-9]+(-[BIT0-9]+)?( |$)' | cut -c4- | sort -n) ; do
			if [[ $k =~ ^[0-9]+$ ]]; then
				printf "        [%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})\n" $k
			else
				printf "        [%02d-%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})\n" ${k%-*} ${k#*-}
			fi
		done
	done
}

#$1 = MSR, $2 = Bit,
getValue() {
	getMSR $1
	getDomain $2
	[ ! -z $DEBUG ] && echo "Reading ${MSR[NAME]} Bit $2 (Domain: $DOMAIN)"
	readMSRs
	extractBits $2
	for i in ${!BITS[@]}; do
		printf "Thread %02d: ${BITS[$i]}\n" $i
	done
}

printRegs() {
	printf "%0${MAXLEN}s${COLOR[Yellow]}" ""
	(IFS="|$IFS"; printf " CPU%02s " "${THREADS[@]}")
	printf "${COLOR[Default]}\n"
	for i in ${MSRS[@]}; do
		declare -n ptr="$i"
		printf "${COLOR[White]}${ptr[NAME]}[${ptr[ADDR]}] -- ${ptr[DESC]}${COLOR[Default]}\n"
		readCPU_MSRs ${ptr[ADDR]}
		for k in $( echo ${!ptr[@]} | grep -oP '\bBIT[0-9]+(-[BIT0-9]+)?( |$)' | cut -c4- | sort -n) ; do
			if [[ $k =~ ^[0-9]+$ ]]; then
				printf "        [%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})" $k
				CURLEN=$(printf "        [%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})" $k | wc -c)
				printf "%0$(($MAXLEN-$CURLEN))s" ""
			else
				printf "        [%02d-%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})" ${k%-*} ${k#*-}
				CURLEN=$(printf "        [%02d-%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})" ${k%-*} ${k#*-} | wc -c)
				printf "%0$(($MAXLEN-$CURLEN))s" ""
			fi

			for p in ${THREADS[@]}; do
				VLEN=$( bc -l <<< "scale=0; (l(2^(${k#*-}-${k%-*}))/l(10)+1.5)/1" )
				extractBits ${k%-*} $((${k#*-} - ${k%-*} +1 ))
				[[ ${BITS[$p]} = 0 ]] && printf "${COLOR[Red]}" || printf "${COLOR[Green]}"
				printf " %0${VLEN}d%0$((6-${VLEN}))s${COLOR[Default]}" ${BITS[$p]}
			done
			printf "\n"
		done
	done
}

#Arguments REG:BIT=VALUE
ensure() {
	if [[ ! $1 =~ ^[^:]+:[^=]+=[0-9]+(-[0-9]+)?$ ]]; then
		echo "$1 is invalid ensure instruction"
		exit 1
	fi
	BIT=${1#*:}
	BIT=${BIT%=*}
	BITCOUNT=$(( ${BIT#*-} - ${BIT%-*} +1 ))
	VAL=${1#*=}
	getMSR ${1%%:*}
	getDomain ${BIT}
	readMSRs
	extractBits ${BIT%-*} $BITCOUNT
	UPD=()
	[ $VAL -eq 0 ] && COL=${COLOR[Red]} || COL=${COLOR[Green]}
	if [ -z $SILENT ]; then
		printf "Ensuring MSR ${COLOR[Yellow]}${MSR[NAME]}${COLOR[Default]}"
		printf " bit ${COLOR[Cyan]}\"${MSR[BIT$BIT]}\"${COLOR[Default]}"
		printf " has Value ${COL}${VAL}${COLOR[Default]}\n"
	fi
	for m in ${!BITS[@]}; do
		if [[ ${BITS[$m]} -ne ${VAL} ]]; then
			#Reset old bits ...
			NEWVAL=$(( ${VALS[$m]} & ~(( (1 << $BITCOUNT) -1 ) << ${BIT%-*}) ))
			[ ! -z $DEBUG ] && echo "Clearing bits MSR ${MSR[ADDR]} on CPU $m from Value ${VALS[$m]} to $NEWVAL (BITCOUNT=$BITCOUNT, SHIFT=${BIT%-*})"
			#Patch in new bits ...
			NEWVAL=$(( ${NEWVAL} | ( ${VAL} << ${BIT%-*}) ))
			[ ! -z $DEBUG ] && echo "Writing MSR ${MSR[ADDR]} on CPU $m from Value ${VALS[$m]} to $NEWVAL"
			wrmsr  -p $m ${MSR[ADDR]} $NEWVAL
			UPD+=($m)
		fi
	done
	if [[ -z $SILENT && ${#UPD} -gt 0 ]]; then
		printf "    => ${COLOR[White]}Updated"
		printf " on ${DOMAIN}s ${UPD[*]}${COLOR[Default]}\n"
	fi
}

help() {
	echo "Tool to manipulate and dump MSRs"
	echo "Available commands:"
	echo "    list  -- lists supported MSRs"
	echo "    print -- print all supported bits for each CPU"
	echo "    help  -- this help"
}



#Helpers
#Read MSR $1 for all Threads
readCPU_MSRs() {
	declare -gA VALS=()
	for p in ${THREADS[@]}; do
		VALS[$p]=$(rdmsr -d -p $p $1)
	done
}

#Read MSRs specified by MSR for all distinct domains in DOMAIN
readMSRs() {
	declare -n cur="${DOMAIN^^}S"
	declare -gA VALS=()
	for p in ${cur[@]}; do
		VALS[$p]=$(rdmsr -d -p $p ${MSR[ADDR]})
	done
}

#Extracts bits $1 from $VALS and puts them in BITS
extractBits() {
	declare -gA BITS=()
	for p in ${!VALS[@]}; do
#		echo "(${VALS[$p]} >> $1) & ((1 << ${2:-1}) -1)"
		BITS[$p]=$(( (${VALS[$p]} >> $1) & ((1 << ${2:-1}) -1) ))
	done
}

#1 = Identifier, Returns msr structure in MSR
getMSR() {
	if [[ $1 =~ 0x[0-9A-Fa-f]* ]]; then
		#Try to find this msr
		if [[ "#{MSR_ADDR[$1]}" = "#" ]]; then
			echo "Unknown MSR $1"; exit 1;
		fi
		declare -ng MSR="${MSR_ADDR[$1]}"
	else
		#Try to get from symbolic name ...
		if [[ "#${MSR_NAME[$1]}" = "#" ]]; then
			echo "Unknown MSR $1"; exit 1;
		fi
		declare -ng MSR="${MSR_NAME[$1]}"
	fi
}

#1 = Bit, uses currently selected MSR, Domain = domain
getDomain() {
	if [[ "#${MSR[DOMAIN$1]}" = "#" ]]; then
		if [[ "#${MSR[DOMAIN]}" = "#" ]]; then
			echo "Error in MSR definition for ${MSR[NAME]}"
			exit 2
		fi
		DOMAIN=${MSR[DOMAIN]}
	else
		DOMAIN=${MSR[DOMAIN$1]}
	fi
}

maxlen() {
	MAXLEN=$(for i in ${MSRS[@]}; do
		declare -n ptr="$i"
		for k in $( echo ${!ptr[@]} | grep -oP '\bBIT[0-9]*( |$)' | cut -c4- | sort -n) ; do
			if [[ $k =~ ^[0-9]+$ ]]; then
				printf "        [%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})\n" $k
			else
				printf "        [%02d-%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})\n" ${k%-*} ${k#*-}
			fi
		done
	done | wc -L)
}
maxlen

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then #Are we being sourced?
	case $1 in
		help|-h|--help) help ;;
		list) list ;;
		print) printRegs ;;
		get) shift; getValue "$@" ;;
		"") echo -e "Missing argument\n"; help ;;
		*) echo -e "Unknown argument $1\n"; help ;;
	esac
fi

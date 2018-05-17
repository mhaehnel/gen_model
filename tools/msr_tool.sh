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

declare -a MSRS=( MSR_POWER_CTL IA32_MISC_ENABLE )

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
		for k in $( echo ${!ptr[@]} | grep -oP '\bBIT[0-9]*( |$)' | cut -c4- | sort -n) ; do
			printf "        [%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})\n" $k
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
		for k in $( echo ${!ptr[@]} | grep -oP '\bBIT[0-9]*( |$)' | cut -c4- | sort -n) ; do
			printf "        [%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})" $k
			CURLEN=$(printf "        [%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})" $k | wc -c)
			printf "%0$(($MAXLEN-$CURLEN))s" ""
			for p in ${THREADS[@]}; do
				V=$(( (${VALS[$p]} >> $k) & 1 ))
				[[ $V = 0 ]] && printf "${COLOR[Red]}" || printf "${COLOR[Green]}"
				printf "   %01d   ${COLOR[Default]}" $V
			done
			printf "\n"
		done
	done
}

#Arguments REG:BIT=VALUE
ensure() {
	if [[ ! $1 =~ ^[^:]*:[^=]*=[0-9]*$ ]]; then
		echo "$1 is invalid ensure instruction"
		exit 1
	fi
	BIT=${1#*:}
	BIT=${BIT%=*}
	VAL=${1#*=}
	getMSR ${1%%:*}
	getDomain ${BIT}
	readMSRs
	extractBits ${BIT}
	UPD=()
	[ $VAL -eq 0 ] && COL=${COLOR[Red]} || COL=${COLOR[Green]}
	if [ -z $SILENT ]; then
		printf "Ensuring MSR ${COLOR[Yellow]}${MSR[NAME]}${COLOR[Default]}"
		printf " bit ${COLOR[Cyan]}\"${MSR[BIT$BIT]}\"${COLOR[Default]}"
		printf " has Value ${COL}${VAL}${COLOR[Default]}\n"
	fi
	for m in ${!BITS[@]}; do
		if [[ ${BITS[$m]} -ne ${1#*=} ]]; then
			if [ ${1#*=} -eq 0 ]; then
				NEWVAL=$(( ${VALS[$m]} & ~(1 << ${BIT}) ))
			else
				NEWVAL=$(( ${VALS[$m]} ^ (1 << ${BIT}) ))
			fi
			[ ! -z $DEBUG ] && echo "Writing MSR ${MSR[ADDR]} on CPU $m from Value ${VALS[$m]} to $NEWVAL"
			wrmsr  -p $m ${MSR[ADDR]} $NEWVAL
			UPD+=($m)
		fi
	done
	if [[ -z $SILENT && ${#UPD} -gt 0 ]]; then
		printf "    => ${COLOR[White]}Updated"
		printf " on ${DOMAIN}s ${UPD[*]}\n"
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
		BITS[$p]=$(( (${VALS[$p]} >> $1) & 1 ))
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
			printf "\t\t  [%02d]: ${ptr[BIT$k]} (${ptr[MODE$k]:-${ptr[MODE]}})\n" $k
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

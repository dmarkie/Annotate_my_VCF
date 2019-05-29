#################################################################################################
# some useful functions from Sam's baserefs.sh

#####################
# Return a string with a new item on the end
# Items are separated by a char or space
#####################
function appendList {
        oldList="${1}"
        newItem="${2}"
        itemJoiner=$([ "${3}" == "" ] && echo -ne " " || echo -ne "${3}")       # If blank, use space.
        if [ "$newItem" != "" ]; then
                if [ "$oldList" == "" ]; then
                        # Initial Entry
                        printf "%s" "$newItem"
                else
                        # Additional Entry
                        printf "%s%s%s" "$oldList" "$itemJoiner" "$newItem"
                fi
        else
                printf "%s" "$oldList"
        fi
}
export -f appendList

###################
# Outputs a dependency if one exists.
###################
function depCheck {
	#(echo "depCheck: $0 \"${@}\"" | tee -a ~/depCheck.txt 1>&2)
	local jobList=$(jobsExist "$1")
	[ "$jobList" != "" ] && echo -ne "--dependency afterok:${jobList}"
}
export -f depCheck

####################
# Returns true if the list of jobs passed are running or waiting to run, otherwise false
####################
function jobsExist {
	local jobList=""
	local IFS=':'
	for item in $@
	do
		if squeue -j $item | grep "$item" &>/dev/null
		then
			jobList=$(appendList "$jobList" $item ":")
		fi
	done
	echo "$jobList"
}
export -f jobsExist

###################
# Visual ticker
###################
function tickOver {
	case "$TICKER" in
		"|") TICKER="/" ;;
		"/") TICKER="-" ;;
		"-") TICKER="\\" ;;
		*) TICKER="|" ;;
	esac
	
	>&2 printf "%s\b" "$TICKER"
}
export -f tickOver

#######################
# Condenses list of numbers to ranges
#
# 1,2,3,4,7,8,9,12,13,14 -> 1-3,4,7-9,12-14
#######################
function condenseList {
	echo "${@}," | \
		sed "s/,/\n/g" | \
		while read num
		do
		if [[ -z $first ]]
		then
			first=$num
			last=$num
			continue
		fi
		if [[ num -ne $((last + 1)) ]]
		then
			if [[ first -eq last ]]
			then
				echo $first
			else
				echo $first-$last
			fi
			first=$num
			last=$num
		else
			: $((last++))
		fi
	done | paste -sd ","
}
export -f condenseList

#####################
# Expand comma separated list of ranges to individual elements
#
# 1,3-5,8,10-12 -> 1,3,4,5,8,10,11,12
#####################
function expandList {
	for f in ${1//,/ }; do
		if [[ $f =~ - ]]; then
			a+=( $(seq ${f%-*} 1 ${f#*-}) )
		else
			a+=( $f )
		fi  
	done
	
	a=${a[*]}
	a=${a// /,}
	
	echo $a
}
export -f expandList

######################
# Return the string with the split char replaced by a space
######################
function splitByChar {
	input=${1}
	char=${2}
	
	if [ "$char" != "" ]; then
		echo -ne "$input" | sed -e "s/${char}/ /g"
	else
		echo -ne "FAIL"
		(>&2 echo -ne "FAILURE:\t splitByChar [${1}] [${2}]\n\tNo character to replace. You forget to quote your input?\n")
	fi
}
export -f splitByChar

######################
# Find matching task elements in a parent and child array.
# Set the child array task element to be dependent on the matching parent task element.
######################
function tieTaskDeps {
	childArray=$(expandList ${1})
	childJobID=${2}
	parentArray=$(expandList ${3})
	parentJobID=${4}
	
	if [ "$childArray" != "" ] && [ "$parentArray" != "" ]; then
		# Both arrays contain something.
		# Cycle through child array elements
		for i in $(splitByChar "$childArray" ","); do
			elementMatched=0
			# Cycle through parent array elements.
			for j in $(splitByChar "$parentArray" ","); do
				if [ "$i" == "$j" ]; then
					# Matching element found. Tie child element to parent element.
#					printf " T[%s->%s] " "${childJobID}_$i" "${parentJobID}_$j"
					scontrol update JobId=${childJobID}_$i Dependency=afterok:${parentJobID}_$j
					elementMatched=1
				fi
			done
			if [ $elementMatched -eq 0 ]; then
				# No matching element found in parent array.
				# Release child element from entire parent array.
				scontrol update JobId=${childJobID}_$i Dependency=
			fi
			tickOver
		done
	fi
}
export -f tieTaskDeps

##########################################################################


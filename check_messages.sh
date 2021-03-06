#!/bin/bash
####################################################################################################################################################
# Name: check_messages.sh
#
# Purp: Count any occurrences at the bottom of /var/log/messages file of the search string values supplied in array "SEARCH_ARRAY".
#
#       According to the specifiactions we are only looking 10 minutes back in time, so a 'grep | tail' is performed to limit performance impact
#
#       a WARNING message will be returned if the count is >= -w <int> && < -c <int> value
#       a CRITICAL message is returned if the count >= -c <int> value
#
# Deps: ${FLATOUT} hidden file to temporary store results. Every run the existing file is removed first
#
# syntax: ./check_messages.sh -w <int> -c <int>
#
# returns:
# - Warning  message
#   WARNING: 2 relevant errors found in messages.log within last 10 minutes:  kernel.*error: 1,  kernel.*deadlock: 0,  kernel.*cifs: 1
#   <OR>
# - Critical message
#   CRITICAL: 30 relevant errors found in messages.log within last 10 minutes:  kernel.*error: 10,  kernel.*deadlock: 10,  kernel.*cifs: 10
#   <OR>
# - Ok message
#   OK: No relevant errors found in messages.log within last 10 minutes.
#
# (PH), 2018-04-04
#
# Changelog:
# (PH), 2018-04-10: errors found => error(s) found & added ${MMDD} in timevars
# (PH), 2018-04-11: removed "SEARCH_ARRAY[0]='kernel.*error'": caused too many criticals 
################################################################################################################################################

# Get the arguments
while [[ $# > 0 ]]; do
  argument="$1"
  case "$argument" in
     -w|--warn)
      warn_rc="$2"
      shift
      ;;
     -c|--crit)
      crit_rc="$2"
      shift
      ;;
    -h|--help)
      helper="help"
      ;;
    -v|--version)
      version="version"
      shift
      ;;
    *)
      ;;
  esac
  shift
done

# Display version and exit when -v|--version is selected
if [[ "$version" == "version" ]]; then
  echo "check_messages v1.0.0"
  echo
  exit 0
fi

# Display help and exit when -h|--help is selected
if [[ "$helper" == "help" ]]; then
  echo
  echo "check_messages help"
  echo
  echo "Usage:"
  echo "  check_messages -w <warn_val> -c <crit_val> "
  echo
  echo "                 -h, --help this help text"
  echo
  exit 0
fi

if [ -z "$warn_rc" ] || [ -z "$crit_rc" ]; then
  # Check is variables for the check are all filled in
  if [ -z "$warn_rc" ]; then
    echo "No warning count specified";
    echo " "
  fi
  if [ -z "$crit_rc" ]; then
    echo "No critical count specified";
    echo " "
  fi
  echo "For more information type: check_messages -h"
  exit 3
fi

##################
function get_index {
##################
  SEARCH_IND=-1
  for i in "${!SEARCH_ARRAY[@]}"; do
    if [[ "${SEARCH_ARRAY[$i]}" = "$1" ]]; then
      SEARCH_IND=${i}
      break
   fi
  done
  echo ${SEARCH_IND}
}

###########################################
# INIT
###########################################
# Standard Exit Codes for Nagios
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

# FLATIN='/home/beheer/messages.log'
FLATIN='/var/log/messages'
FLATOUT='/tmp/.err.messages.tmp'

FOUND_TOT=0

if [[ ! -f ${FLATIN} ]]; then
  echo "UNKNOWN: Inputfile ${FLATIN} does not exist !"
  exit ${UNKNOWN}
fi

if [[ ! -d `dirname ${FLATOUT}` ]]; then
  echo "UNKNONW: temporay path does not exist !"
  exit ${UNKNOWN}
fi

# Remove old flatout file
# ===============================
if [[ -f ${FLATOUT} ]]; then
  rm -f ${FLATOUT}
fi

# Initialize timevars
# ===============================
MINS=10
#jan/feb/apr etc...
MMM=$(echo `date +%b`)
DD=$(echo `date +%e`)
if [[ ${DD} -lt  10 ]]; then
  #jan  9
  MMMDD="${MMM}  ${DD}"
else
  #jan 10
  MMMDD="${MMM} ${DD}"
fi
#jan  9 16:12:00
TIME_START="${MMMDD} $(echo `date +%H:%M:00 --date "-${MINS} min"`)"
#jan  9 16:22:00
TIME_END="${MMMDD} $(echo `date +%H:%M:00`)"

# SearchCriteria
# ===============================
declare -a SEARCH_ARRAY
SEARCH_ARRAY[0]='kernel.*deadlock'
SEARCH_ARRAY[1]='kernel.*cifs'

# Corresponding HIT array ( must have at least the same size as SEARCH_ARRAY ! )
HIT_ARRAY=(0 0 0)

############################################
# Part 1: tail grep on messages; we need the
#         last 10 minutes anyway
############################################
SEARCH_LEN=${#SEARCH_ARRAY[@]}
# For each searchline in SEARCH_ARRAY
for (( SEARCH_INDEX=0; SEARCH_INDEX<${SEARCH_LEN}; SEARCH_INDEX++ ));
do
  `grep -i ${SEARCH_ARRAY[$SEARCH_INDEX]} ${FLATIN} | tail | sed -e 's/$/ ~'${SEARCH_ARRAY[$SEARCH_INDEX]}'/' >> ${FLATOUT}`
done

############################################
# Part 2: read flatout to determine line age
############################################
while read LINE; do
  # If timestamp in messagefile record is between *NOW and *NOW - 10 minutes DO:
  # ----------------------------------------------------------------------------
  if [[ ${LINE} > ${TIME_START} && ${LINE} < ${TIME_END} || ${LINE} =~ ${TIME_END} ]];
  then
    FOUND_TOT=$((FOUND_TOT + 1))
    SEARCH_ITEM=`echo ${LINE} | cut -d'~' -f2`
    SEARCH_INDEX=$(get_index ${SEARCH_ITEM})
    HIT_ARRAY[${SEARCH_INDEX}]=$((HIT_ARRAY[${SEARCH_INDEX}] + 1))
  fi
done < ${FLATOUT}

############################################
# Final:
############################################

# Dynamically compose returnmessage....
# --------------------------------------------------------------------------------
RETURN_MSG="relevant error(s) found in `basename ${FLATIN}` within last ${MINS} minutes"
COMMA=","

if [[ ${FOUND_TOT} -lt $warn_rc ]];
then
 echo "OK: No ${RETURN_MSG}"
 exit ${OK}
else
  RETURN_MSG="${RETURN_MSG}:"
  for i in "${!SEARCH_ARRAY[@]}"; do
     DIF=$((${#SEARCH_ARRAY[@]}-$i))
     if [[ ${DIF} = 1 ]]; then
      COMMA=""
    fi
    RETURN_MSG="${RETURN_MSG} ${SEARCH_ARRAY[${i}]}: ${HIT_ARRAY[${i}]}${COMMA} "
  done

  if [[ ${FOUND_TOT} -ge $warn_rc && ${FOUND_TOT} -lt $crit_rc ]];then
    echo "WARNING: ${FOUND_TOT} ${RETURN_MSG}"
    exit ${WARNING}
  else
    echo "CRITICAL: ${FOUND_TOT} ${RETURN_MSG}"
    exit ${CRITICAL}
  fi
fi

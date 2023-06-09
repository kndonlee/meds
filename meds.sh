#!/usr/bin/env bash

sleep_time=20
take_soon_time=1800
version=1.11

cd "$(dirname "$0")"

RESET='\e[0m'       # Text Reset
BOLD="$(tput bold)";

# Regular Colors
BLACK='\e[0;30m'        # Black
RED='\e[0;31m'          # Red
GREEN='\e[0;32m'        # Green
YELLOW='\e[0;33m'       # Yellow
BLUE='\e[0;34m'         # Blue
PURPLE='\e[0;35m'       # Purple
CYAN='\e[0;36m'         # Cyan
WHITE='\e[0;37m'        # White

BLUE_BG='\e[0;44m'       # Blue
YELLOW_BG='\e[0;43m'       # Blue

# Bold Colors
BBLACK='\e[1;30m'        # Black
BRED='\e[1;31m'          # Red
BGREEN='\e[1;32m'        # Green
BYELLOW='\e[1;33m'       # Yellow
BBLUE='\e[1;34m'         # Blue
BPURPLE='\e[1;35m'       # Purple
BCYAN='\e[1;36m'         # Cyan
BWHITE='\e[1;37m'        # White


[[ -f chatid ]] && chatid=$(cat chatid)
[[ -z $chatid ]] && chatid="chat574232935236064109"

QUERY="SELECT
    message.is_from_me,
    chat.chat_identifier,
    datetime (message.date / 1000000000 + strftime (\"%s\", \"2001-01-01\"), \"unixepoch\", \"localtime\") AS message_date,
    message.date / 1000000000 + strftime (\"%s\", \"2001-01-01\") AS message_epoch,
    strftime (\"%s\", \"now\") AS now_epoch,
    message.text
FROM
    chat
    JOIN chat_message_join ON chat. \"ROWID\" = chat_message_join.chat_id
    JOIN message ON chat_message_join.message_id = message. \"ROWID\"
WHERE
     chat.chat_identifier LIKE \"${chatid}\"
     AND (now_epoch-message_epoch) <= 86400
ORDER BY
    message_date ASC"

    #strftime ("%s", "now", "localtime") AS now_epoch,
     #AND (now_epoch-message_epoch) <= 86400
#    message.text

     #message_epoch > (strftime ("%s", "now", "-1 days"))

# Replace with the actual path to your chat.db file if different
DB_PATH="${HOME}/Library/Messages/chat.db"

# Check if the SQLite3 command-line tool is installed
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Error: sqlite3 command-line tool is not installed."
  exit 1
fi

function all_messages {
  sqlite3 "${DB_PATH}" "${QUERY}"
}


# 1|chat574232935236064109|2023-03-24 19:33:30|1679708010|1679742726|Edited to “7:31:50 PM MDT
# 
# 3/4 Baclofen
# 500mg Taurine
# 250mg Calcium
# 21mg Iron”
# 1|chat574232935236064109|2023-03-24 22:24:19|1679718259|1679742726|10:24:12 PM MDT
# 
# Lyrica
# .25mg Xanax
# 7.5mg Morphine (ER)

: ${DEBUG:=false}
function debug {
  $DEBUG && 
    echo "DEBUG: $@" 1>&2
}

function readable_time {
  local epoch="$1"
  #TZ=MDT date -r "$epoch" | awk {'print $4'}  
  #echo date -r "$epoch" "+%I:%M %p"
  read time meridiem < <(date -r "$epoch" "+%I:%M %p")

  [[ $meridiem =~ P ]] &&
    echo -e "$time ${PURPLE}${meridiem}${RESET}" ||
    echo -e "$time ${YELLOW}${meridiem}${RESET}"

}

# 12:29:56 AM MDT
# 1:07:24 AM MDT
# 7:11:11 PM MDT
# 3:10:21 PM MDT
# 10:06:18 PM MDT
# 11:36:11 PM MDT
# 8:24p
# 9p
# 9:20a
# 10p
# 12:54p
# 6:30p
# 8:45p
# 9:13p
# 10:37a
# 3:40p

function crack_time {
  local time="$1"

  debug "cracking time: $time"

  if [[ $time =~ ^([0-9]+:[0-9]+:[0-9]+)\ AM\ MDT ]]; then
    new_epoch=$(date -j -f "%H:%M:%S"  "${BASH_REMATCH[1]}" "+%s")
  elif [[ $time =~ ^([0-9]+:[0-9]+:[0-9]+)\ PM\ MDT ]]; then
    new_epoch=$(date -j -f "%H:%M:%S"  "${BASH_REMATCH[1]}" "+%s")
    new_epoch=$((message_epoch+43200))
  elif [[ $time =~ ^([0-9]+:[0-9]+:[0-9]+) ]]; then
    new_epoch=$(date -j -f "%H:%M:%S"  "${BASH_REMATCH[1]}" "+%s")
  elif [[ $time =~ ^([0-9]+:[0-9]+)[aA] ]]; then
    new_epoch=$(date -j -f "%H:%M:%S"  "${BASH_REMATCH[1]}:00" "+%s")
  elif [[ $time =~ ^([0-9]+:[0-9]+)[pP] ]]; then
    new_epoch=$(date -j -f "%H:%M:%S"  "${BASH_REMATCH[1]}:00" "+%s")
    new_epoch=$((message_epoch+43200))
  elif [[ $time =~ ^([0-9]+)[aA] ]]; then
    new_epoch=$(date -j -f "%H:%M:%S"  "${BASH_REMATCH[1]}:00:00" "+%s")
  elif [[ $time =~ ^([0-9]+)[pP] ]]; then
    new_epoch=$(date -j -f "%H:%M:%S"  "${BASH_REMATCH[1]}:00:00" "+%s")
    new_epoch=$((message_epoch+43200))
  else
    echo "could not crack time: $time"
  fi
    
  #message_epoch="$new_epoch" 

  epoch_diff=$((message_epoch-new_epoch))
  if ! [[ ${epoch_diff#-} -gt 60000 ]]; then
    debug overriding epoch with time from message
    message_epoch="$new_epoch" 
  fi
}

function crack_time {
  echo > /dev/null
}

function crack_header {
  local line="$1"

  read message_epoch current_epoch message < <(echo "$line" | awk -F\| '{print $4, $5, $6}')
 
  if [[ $message =~ MDT ]]; then
    parsed_time=$(echo $message | egrep -o "[0-9]+:[0-9]+:[0-9]+ [AP].*")
    crack_time "$parsed_time"
  elif [[ $message =~ [0-9]+:[0-9]+[aApP] ]]; then
    parsed_time=$(echo $message | egrep -o "[0-9]+:[0-9]+[aApP]")
    crack_time "$parsed_time"
  elif [[ $message =~ [0-9]+[aApP] ]]; then
    parsed_time=$(echo $message | egrep -o "[0-9]+[aApP]")
    crack_time "$parsed_time"
  else
    debug "did not parse $message"
  fi
}

function format_for_log {
  local epoch="$1"
  local msg="$2"

  out_time="$(readable_time "$epoch" | tr '[:upper:]' '[:lower:]' | sed -e 's/ //' -e 's/am/a/' -e 's/pm/p/')"
  out_msg="$(echo "$msg" | sed -e 's/ /_/g')"

  [[ $out_time =~ p ]] &&
    echo -e "${PURPLE}${out_time}${RESET}${BLACK}-${RESET}${out_msg}" ||
    echo -e "${YELLOW}${out_time}${RESET}${BLACK}-${RESET}${out_msg}"
}

#last_morphine
#last_baclofen
#last_esgic
#last_lyrica
#last_xanax
#
#last_taurine
#last_calcium
#last_msm
#last_iron
function process_messages {
  for i in morphine baclofen esgic lyrica xanax taurine calcium msm iron magnesium nac vitamind; do
    unset "${i}_log"
  done

  while read line; do
    [[ $line =~ ^\s*$ ]] && continue
  
    debug "line: $line"
    [[ $line =~ $chatid ]] && crack_header "$line"
    debug "epoch: $message_epoch current_epoch: $current_epoch"
    
    [[ $line =~ $chatid ]] && line="$(echo $line | awk -F\| {'print $6'} | sed -e 's/\[””]//g')"
  
    echo "$line" | grep -v : | grep -qi morph       && last_morphine=$message_epoch    && morphine_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi baclo       && last_baclofen=$message_epoch    && baclofen_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi esgic       && last_esgic=$message_epoch       && esgic_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi lyrica      && last_lyrica=$message_epoch      && lyrica_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi xanax       && last_xanax=$message_epoch       && xanax_log+="$(format_for_log $message_epoch "$line")\n"
    
    echo "$line" | grep -v : | grep -qi taur        && last_taurine=$message_epoch     && taurine_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi calc        && last_calcium=$message_epoch     && calcium_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi msm         && last_msm=$message_epoch         && msm_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi iron        && last_iron=$message_epoch        && iron_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi magne       && last_magnesium=$message_epoch   && magnesium_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi nac         && last_nac=$message_epoch         && nac_log+="$(format_for_log $message_epoch "$line")\n"
    echo "$line" | grep -v : | grep -qi vitamin\ d  && last_vitamind=$message_epoch    && vitamind_log+="$(format_for_log $message_epoch "$line")\n"
  
  done < <(all_messages)
}

function out {
  local drug="$1"
  local last_taken_epoch="$2"
  local due_every="$3"
  local due_every_s="$(($3 * 3600))"
  local current_epoch="$current_epoch"
  local optional="$4"
  [[ -z $optional ]] && optional=false

  elapsed_secs=$((last_taken_epoch-current_epoch))
  elapsed_secs="${elapsed_secs#-}"
  elapsed_hours=$((elapsed_secs/3600))
  elapsed_mins=$(($((elapsed_secs%3600))/60))

  debug ----------
  debug "drug: $drug"
  debug "last epoch: $last_taken_epoch"
  debug "current epoch: $current_epoch"
  debug "due every: $due_every hrs"
  debug "elapsed: $elapsed_secs seconds"
  debug "elapsedh: $elapsed_hours hour"
  debug "elapsedm: $elapsed_mins min"

#       7200           3600
  if [[ $due_every_s -lt $elapsed_secs ]]; then
    if ${optional}; then
      #due="${BYELLOW}${BLUE_BG}Optl${RESET}"
      due="${YELLOW_BG}${BBLUE}${YELLOW_BG}optl${RESET}"
      due="${YELLOW_BG}${BGREEN}optl${RESET}"
      due="${BLUE_BG}${BWHITE}Optl${RESET}"
    else
      due="${BRED}TAKE${RESET}"
    fi
  elif [[ $due_every_s -gt $elapsed_secs ]]; then
    due="${BGREEN}wait${RESET}"

    if [[ $((${due_every_s}-${elapsed_secs})) -lt $take_soon_time ]]; then
      due="${BYELLOW}SOON${RESET}"
    fi
  else
    due="${BRED}WTF_DONALD${RESET}"
  fi

  if [[ $elapsed_secs -gt 86400 ]]; then
    elapsed="24+hrs"
  else
    elapsed="$(printf "%02d:%02d" "${elapsed_hours#-}" "${elapsed_mins#-}")"
  fi

  echo -e "$(printf "%-12s" $drug) last:${CYAN}$(readable_time "$last_taken_epoch")${RESET}   Elapsed:${CYAN}${elapsed}${RESET}  Due:$due  Every:${CYAN}$due_every hrs${RESET}"

}


function echo_blank {
  echo  "-------------------------- "
}

function echo_blank2 {
  echo  "                           "
}

while true; do
  process_messages

  clear
  echo -e "${BYELLOW}Last update:${BPURPLE}$(date) ${BYELLOW}version:${BPURPLE}${version} ${BYELLOW}Host:${BPURPLE}$HOSTNAME${RESET}"
  echo
  out morphine_bt "$last_morphine" 4  true
  out morphine    "$last_morphine" 8
  out baclofen    "$last_baclofen" 4
  out esgic       "$last_esgic"    4  true
  out lyrica      "$last_lyrica"   12
  out xanax       "$last_xanax"    12
  echo
  out taurine     "$last_taurine"   3 
  out calcium     "$last_calcium"   3
  out msm         "$last_msm"       3
  out iron        "$last_iron"      3
  out magnesium   "$last_magnesium" 6
  out nac         "$last_nac"       24
  out vitamind    "$last_vitamind"  24

  col_width=61

  set1=$(for i in morphine baclofen esgic lyrica; do
    eval "$(echo -n "echo -ne \"\$${i}_log\"")" | while read line; do
      line_length=$(echo -e "$line" | wc -c)
      spaces_to_add=$((col_width-line_length))

      echo -ne "$line"
      for i in $(seq 1 $spaces_to_add); do
        echo -ne " "
      done
      echo
    done
    echo_blank
  done)

  set2=$(for i in xanax taurine calcium msm; do
    eval "$(echo -n "echo -ne \"\$${i}_log\"")" | while read line; do
      line_length=$(echo -e "$line" | wc -c)
      spaces_to_add=$((col_width-line_length))

      echo -ne "$line"
      for i in $(seq 1 $spaces_to_add); do
        echo -ne " "
      done
      echo
    done
    echo_blank
  done)

  set3=$(for i in iron magnesium nac vitamind; do
    eval "$(echo -n "echo -ne \"\$${i}_log\"")" | while read line; do
      line_length=$(echo -e "$line" | wc -c)
      spaces_to_add=$((col_width-line_length))

      echo -ne "$line"
      for i in $(seq 1 $spaces_to_add); do
        echo -ne " "
      done
      echo
    done
    echo_blank
  done)

  max_lines=0
  set1_lines=$(echo -e "$set1" | wc -l); [[ $set1_lines -gt max_lines ]] && max_lines=$set1_lines
  set2_lines=$(echo -e "$set2" | wc -l); [[ $set2_lines -gt max_lines ]] && max_lines=$set2_lines
  set3_lines=$(echo -e "$set3" | wc -l); [[ $set3_lines -gt max_lines ]] && max_lines=$set3_lines

  if [[ $max_lines -gt $set1_lines ]]; then
    lines_to_add=$((max_lines-set1_lines))
    set1=$(echo -e "$set1"; for i in $(seq 1 $lines_to_add); do echo_blank2; done)
  fi

  if [[ $max_lines -gt $set2_lines ]]; then
    lines_to_add=$((max_lines-set2_lines))
    set2=$(echo -e "$set2"; for i in $(seq 1 $lines_to_add); do echo_blank2; done)
  fi

  echo
  echo -e "${BYELLOW}Log${RESET}"
  paste -d' ' <(echo -e "$set1") <(echo -e "$set2") <(echo -e "$set3")

#  paste <(echo -e "$set1") <(echo -e "$set2") <(echo -e "$set3") | while read col1 col2 col3; do
#    echo -e "$col1"
#    echo -e "$col2"
#    echo -e "$col3"
#  done | xargs printf "_%-30s_   _%-30s_   _%-30s_\n"

# $morphine_log
# $baclofen_log
# $esgic_log
# $lyrica_log
# $xanax_log
#
# $taurine_log
# $calcium_log
# $msm_log
# $iron_log
# $magnesium_log
# $nac_log

  sleep $sleep_time
done

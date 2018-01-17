#!/usr/bin/env bash
# _reminderbot ~ Subroutines/Commands
# Copyright (c) 2017 David Kim
# This program is licensed under the "MIT License".
# Date of inception: 1/14/17

read nick chan msg      # Assign the 3 arguments to nick, chan and msg.

IFS=''                  # internal field separator; variable which defines the char(s)
                        # used to separate a pattern into tokens for some operations
                        # (i.e. space, tab, newline)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BOT_NICK="$(grep -P "BOT_NICK=.*" ${DIR}/_reminderbot.sh | cut -d '=' -f 2- | tr -d '"')"

if [ "${chan}" = "${BOT_NICK}" ] ; then chan="${nick}" ; fi

###############################################  Subroutines Begin  ###############################################

function has { $(echo "${1}" | grep -P "${2}" > /dev/null) ; }

function say { echo "PRIVMSG ${1} :${2}" ; }

function send {
    while read -r line; do                          # -r flag prevents backslash chars from acting as escape chars.
      currdate=$(date +%s%N)                         # Get the current date in nanoseconds (UNIX/POSIX/epoch time) since 1970-01-01 00:00:00 UTC (UNIX epoch).
      if [ "${prevdate}" = "${currdate}" ] ; then  # If 0.5 seconds hasn't elapsed since the last loop iteration, sleep. (i.e. force 0.5 sec send intervals).
        sleep $(bc -l <<< "(${prevdate} - ${currdate}) / ${nanos}")
        currdate=$(date +%s%N)
      fi
      prevdate=${currdate}+${interval}
      echo "-> ${1}"
      echo "${line}" >> ${BOT_NICK}.io
    done <<< "${1}"
}

# Add a cronjob.

function cronjobSubroutine {
    payload=${1}
    days=$(echo ${payload} | sed -r 's/([0-9]*d)([0-9]*h)([0-9]*m).*/\1/')
    hours=$(echo ${payload} | sed -r 's/([0-9]*d)([0-9]*h)([0-9]*m).*/\2/')
    minutes=$(echo ${payload} | sed -r 's/([0-9]*d)([0-9]*h)([0-9]*m).*/\3/')
    task=$(echo ${payload} | sed -r 's/([0-9]*d)([0-9]*h)([0-9]*m)//' | sed 's/^[ ]*//' | sed 's/[ ]*$//')
    # say ${chan} "${days} ${hours} ${minutes}"
    # say ${chan} "${task}"

    if [ ! ${days} ] && [ ! ${hours} ] && [ ! ${minutes} ] || [ $(echo ${days}${hours}${minutes} | sed 's/[ 0-9dhm]*//') ]; then
        say ${chan} "Sorry, I couldn't setup your reminder"
        return 1
    fi

    if [ ! ${days} ] ; then days='0d' ; fi
    if [ ! ${hours} ] ; then hours='0h' ; fi
    if [ ! ${minutes} ] ; then minutes='0m' ; fi

    ce_time=$(date +%s)                                                     # current epoch time
    days=$(echo ${days} | sed -r 's/d//')
    hours=$(echo ${hours} | sed -r 's/h//')
    minutes=$(echo ${minutes} | sed -r 's/m//')
    e_time=$(( ${days}*24*60*60 + ${hours}*60*60 + ${minutes}*60 + ${ce_time} ))         # convert #d#h#m ==> epoch time
                                                                            # (d * 24 * 60 * 60) + (h * 60 * 60) + (m * 60)

    s_time=$(date -d @${e_time} +%M%H%d%m)                                            # convert epoch time ==> standard time
    min=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\1/')
    hour=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\2/')
    day=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\3/')
    month=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\4/')
    say ${chan} "${nick}: You will be reminded @ $(date -d @${e_time})"
    uuid=$(uuidgen)
    (crontab -l ; echo "${min} ${hour} ${day} ${month} * echo ${uuid}: $(date), ${chan}, ${task} >> /home/dkim/sandbox/_reminderbot/tasks/tmp") | crontab -

    # min hour day month day-of-week
}

# This subroutine displays documentation for _reminderbot's functionalities.

function helpSubroutine {
    say ${chan} "${nick}: I will remind you of stuff! READ: I am not liable for your forgetfulness."
    say ${chan} 'usage: "remind me in #d#h#m ..." such as 3d4h6m for 3 days, 4 hours, 6 minutes'
    # say ${chan} 'usage: remind me in #d#h#m ...'
}

################################################  Subroutines End  ################################################

# Ω≈ç√∫˜µ≤≥÷åß∂ƒ©˙∆˚¬…ææœ∑´®†¥¨ˆøπ“‘¡™£¢∞••¶•ªº–≠«‘“«`
# ─━│┃┄┅┆┇┈┉┊┋┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟┠┡┢┣┤┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿╀╁╂╃╄╅╆╇╈╉╊╋╌╍╎╏
# ═║╒╓╔╕╖╗╘╙╚╛╜╝╞╟╠╡╢╣╤╥╦╧╨╩╪╫╬╭╮╯╰╱╲╳╴╵╶╷╸╹╺╻╼╽╾╿

################################################  Commands Begin  #################################################

# Help Command.

if has "${msg}" "^!_reminderbot$" || has "${msg}" "^_reminderbot: help$" ; then
    helpSubroutine

# Alive.

elif has "${msg}" "^!alive(\?)?$" || has "${msg}" "^_reminderbot: alive(\?)?$" ; then
    say ${chan} "running!"

# Source.

elif has "${msg}" "^_reminderbot: source$" ; then
    say ${chan} "Try -> https://github.com/kimdj/_reminderbot -OR- /u/dkim/_reminderbot"

# Add a cronjob.

elif has "${msg}" "^remind me in " ; then
    payload=$(echo ${msg} | sed -r 's/^remind me in //')
    cronjobSubroutine "${payload}"

# # Get the list of all channels. [A]

# elif has "${msg}" "^!channels -p$" || has "${msg}" "^!channels --privmsg$" ; then
#     allChannelSubroutine ${nick}

# # Handle incoming msg from self (_reminderbot => _reminderbot).

# elif has "${msg}" "^!signal_allchan " && [[ ${nick} = "_reminderbot" ]] ; then
#     signalSubroutine ${msg}

# # Get a nick's channels (nick/chan => _reminderbot).

# elif has "${msg}" "^!channels " ; then                    # !channels MattDaemon  -OR-  !channels -p MattDaemon
#     target=$(echo ${msg} | sed -r 's/^!channels //')         # MattDaemon  -OR-  -p MattDaemon
#     if [[ ${target} == *-p* ]] || [[ ${target} == *--privmsg* ]] ; then
#         target=$(echo ${target} | sed -r 's/ *--privmsg//' | sed -r 's/ *-p//' | xargs)
#         channelSubroutine ${nick} ${target} 'p'              # channelSubroutine _sharp MattDaemon p
#     else
#         channelSubroutine ${chan} ${target}                  # channelSubroutine #bingobobby MattDaemon
#     fi

# # Handle incoming msg from self (_reminderbot => _reminderbot).

# elif has "${msg}" "^!signal " && [[ ${nick} = "_reminderbot" ]] ; then
#     signalSubroutine ${msg}

# Have _reminderbot send an IRC command to the IRC server.

elif has "${msg}" "^_reminderbot: injectcmd " && [[ ${nick} = "_sharp" ]] ; then
    cmd=$(echo ${msg} | sed -r 's/^_reminderbot: injectcmd //')
    send "${cmd}"

# Have _reminderbot send a message.

elif has "${msg}" "^_reminderbot: sendcmd " && [[ ${nick} = "_sharp" ]] ; then
    buffer=$(echo ${msg} | sed -re 's/^_reminderbot: sendcmd //')
    dest=$(echo ${buffer} | sed -e "s| .*||")
    message=$(echo ${buffer} | cut -d " " -f2-)
    say ${dest} "${message}"

fi

#################################################  Commands End  ##################################################

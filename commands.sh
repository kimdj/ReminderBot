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

# This subroutine checks whether the time input is in the correct format.

function checkFormatSubroutine {
    payload=${1}

    if [ -z $(echo ${payload} | sed -r 's|[0-9]?[0-9]{1}:[0-9]{2}[a|p]m||' | sed -r 's|[0-9]?[0-9]{1}:?[0-9]{2}||' | sed -r 's|[0-9]?[0-9]{1}[a|p]m||') ] ; then
        say ${chan} 'time format OK'
        return 0
    else
        say ${chan} 'time format FAIL'
        return 1
    fi
}

# This subroutine parses a time input value and sets variables accordingly (e.g. ${h}, ${m}).

function timeSubroutine {
say ${chan} "entering timeSubroutine"
say ${chan} "payload: ${1}"
    payload=${1}                                                                    # 12:00am  12:00pm  0000  2400  00:00  24:00  3pm
    checkFormatSubroutine "${payload}"
    if [[ $? -eq 1 ]] ; then return 1 ; fi                                          # If format is incorrect, immediately return.

    h=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}).*|\1|')                        # Strip the hours, minutes, and am/pm.
    m=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}):?([0-9]{2}).*|\2|')
    if [[ "${m}" == "${payload}" ]] ; then m='00' ; fi                              # Case: 3pm ==> 00 min default
    am_pm=$(echo ${payload} | sed -r 's|.*([a|p]m).*|\1|')
    if [[ "${am_pm}" == "${payload}" ]] ; then am_pm='am' ; fi                      # Case: 3:00 ==> am default

    if [ "${h}" -gt "23" ] && [ "${m}" -gt "0" ] ; then
        say ${chan} 'time is out-of-bounds'
        return 1
    fi

    if [ "${am_pm}" == "pm" ] ; then                                                # Standardize to military time.
        h=$(expr ${h} + 12)
    elif [ "${h}" == "12" ] && [ "${am_pm}" == "am" ] ; then
        h='00'
    fi
    say ${chan} "${h}${m}"
}

# This subroutine parses a date input value and sets variables accordingly (e.g. ${day_of_month}, ${month}, ${day_of_week}).

function daySubroutine {
say ${chan} "entering daySubroutine"
say ${chan} "daySubroutine payload: ${1}"
    payload=${1}

    if [ "${payload^^}" == "SUNDAY" ] ||
       [ "${payload^^}" == "MONDAY" ] ||
       [ "${payload^^}" == "TUESDAY" ] ||
       [ "${payload^^}" == "WEDNESDAY" ] ||
       [ "${payload^^}" == "THURSDAY" ] ||
       [ "${payload^^}" == "FRIDAY" ] ||
       [ "${payload^^}" == "SATURDAY" ] ||
       [ "${payload^^}" == "SUN" ] ||
       [ "${payload^^}" == "MON" ] ||
       [ "${payload^^}" == "TUE" ] ||
       [ "${payload^^}" == "WED" ] ||
       [ "${payload^^}" == "THU" ] ||
       [ "${payload^^}" == "FRI" ] ||
       [ "${payload^^}" == "SAT" ] ; then
        day_of_month='*'
        month='*'
        day_of_week=$(echo ${payload,,} | sed -r 's|([a-z]{3}).*|\1|')              # SuNdAy ==> sun
        return 0
    elif [ -z "$(echo ${payload} | sed -r 's|[0-9]?[0-9]{1}[\/-][0-9]?[0-9]{1}[\/-][0-9]?[0-9]{1}||')" ] ; then   # 1/1/1, 12-12-12
        month_t=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}).*|\1|')
        day_t=$(echo ${payload} | sed -r 's|[0-9]?[0-9]{1}[\/-]([0-9]?[0-9]{1}).*|\1|')
        year_t=$(echo ${payload} | sed -r 's|[0-9]?[0-9]{1}[\/-][0-9]?[0-9]{1}[\/-]([0-9]?[0-9]{1}).*|\1|')

        say ${chan} "=========================> ${month_t}"
        say ${chan} "=========================> ${day_t}"
        say ${chan} "=========================> ${year_t}"

        if [ "${day_t}" -gt "$(date -d "${month_t}/1 + 1 month - 1 day" "+%d")" ] ; then      # if day is out-of-bounds (i.e. specified day exceeds the last day of a given month)
            return 1
        fi

        day_of_month=$(echo ${day_t})
        month=$(echo ${month_t})
        day_of_week='*'
    else
        return 1
    fi
}

# This subroutine parses scheduling data within a message payload and generates a cronjob entry.

function parseSubroutine {
    payload=${1}
    echo "payload: ${payload}"

    at=$(echo ${payload} | sed -r 's|(.*)(at [0-9][0-9apm:]*)(.*)|\2|')
    if [[ "${at}" == "${payload}" ]] ; then at=$(echo ${payload} | sed -r 's|.*||') ; fi

    on_d=$(echo ${payload} | sed -r 's|.*(on [0-9mondaytueswhrfi][0-9\/mondaytueswhrfi-]*).*|\1|')
    if [[ "${on_d}" == "${payload}" ]] ; then on_d=$(echo ${payload} | sed -r 's|.*||') ; fi

    this_d=$(echo ${payload} | sed -r 's|.*(this [mondaytueswhrfi]*).*|\1|')
    if [[ "${this_d}" == "${payload}" ]] ; then this_d=$(echo ${payload} | sed -r 's|.*||') ; fi

    next_d=$(echo ${payload} | sed -r 's|.*(next [mondaytueswhrfi]*).*|\1|')
    if [[ "${next_d}" == "${payload}" ]] ; then next_d=$(echo ${payload} | sed -r 's|.*||') ; fi

    payload=$(echo ${payload} | sed -r 's|(.*)(at [0-9][0-9apm:]* )(.*)|\1\3|')
    payload=$(echo ${payload} | sed -r 's|(.*)(on [0-9mondaytueswhrfi][0-9\/mondaytueswhrfi-]* )(.*)|\1\3|')
    payload=$(echo ${payload} | sed -r 's|(.*)(this [mondaytueswhrfi]*)(.*)|\1\3|')
    task=$(echo ${payload} | sed -r 's|(.*)(next [mondaytueswhrfi]*)(.*)|\1\3|' | sed -r 's|^[ ]*||' | sed -r 's|[ ]*$||')

    # say ${chan} "  task: ${task}"
    # say ${chan} "    at: ${at}"
    # say ${chan} "  on_d: ${on_d}"
    # say ${chan} "this_d: ${this_d}"
    # say ${chan} "next_d: ${next_d}"
    # say ${chan} " "

    at=$(echo ${at} | sed -r 's|.*at [^0-9]*(.*)|\1|')
    on_d=$(echo ${on_d} | sed -r 's|.*on (.*)|\1|')
    this_d=$(echo ${this_d} | sed -r 's|.*this (.*)|\1|')
    next_d=$(echo ${next_d} | sed -r 's|.*next (.*)|\1|')

    # say ${chan} "    at ==> ${at}"
    # say ${chan} "  on_d ==> ${on_d}"
    # say ${chan} "this_d ==> ${this_d}"
    # say ${chan} "next_d ==> ${next_d}"


#   Example of cronjob definition:
#   .---------------- minute (0 - 59)
#   |  .------------- hour (0 - 23)
#   |  |  .---------- day of month (1 - 31)
#   |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
#   |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
#   |  |  |  |  |
#   *  *  *  *  * user-name  command to be executed


    if [ -n "${on_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: on sunday at 3:00pm
            say ${chan} '11111'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            say ${chan} "cronjob: ${cronjob}"
        else                                                        # Case: on monday
            say ${chan} '22222'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            say ${chan} "cronjob: ${cronjob}"
        fi
    elif [ -n "${this_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: this tuesday at 4:00am
            say ${chan} '33333'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            say ${chan} "cronjob: ${cronjob}"
        else                                                        # Case: this wednesday
            say ${chan} '44444'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            say ${chan} "cronjob: ${cronjob}"
        fi
    elif [ -n "${next_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: next thursday at 5:00pm
            say ${chan} '55555'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            echo "cronjob: ${cronjob}"
        else                                                        # Case: next friday
            say ${chan} '66666'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            say ${chan} "cronjob: ${cronjob}"
        fi
    elif [ -n "${at}" ] ; then                                      # Case: at 10:00am
        echo '77777'
        timeSubroutine "${at}"

        current_time=$(date +%H%M)
        if [ "${h}${m}" -lt "${current_time}" ] ; then
            day=$(date -d '+1 day' +%d)
        else
            day=$(date +%d)
        fi
        month=$(date +%m)

        cronjob=$(echo "${m} ${h} ${day} ${month} * ")
        say ${chan} "cronjob: ${cronjob}"
    else                                                            # missing values
        say ${chan} 'missing values'
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
        # send error msg
        return 1
    fi

    say ${chan} "END REACHED; SUCCESS!"
}

# Add a cronjob.

function cronjobSubroutine {
    payload=${1}

    if [ ! $(echo ${payload} | sed -r 's|^(in ([0-9]+[dhm]{1})+).*|\1|') == "${payload}" ] ; then                      # in 1d2h3m do something ==> in 1d2h3m
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
    else
        parseSubroutine "${payload}"
    fi
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

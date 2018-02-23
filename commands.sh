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

###################################################  Settings  ####################################################

DIR_PATH="${DIR}"                                       # Path to _reminderbot.
CURRENT_YEAR='18'
REM_MAX_LEN='200'                                       # Set the maximum length of a reminder/task.  A reminder that exceeds this length becomes truncated.
MAX_REM='2000'                                          # Set the maximum number of reminders allowed (or maximum number of cronjobs).
AUTHORIZED='_sharp MattDaemon'                          # List of users authorized to execute bot commands (e.g. injectcmd, sendcmd).
if [ "$(uuidgen 2> /dev/null ; echo $?)" -eq "127" ] ; then          # Generate a UUID (Universal Unique Identifier), which is used to catalog a reminder/cronjob.
    UUIDGEN="$(cat /proc/sys/kernel/random/uuid)"
else
    UUIDGEN="$(uuidgen)"
fi
DEBUG='#'                                               # Comment to display debug msgs.
                                                        # Or, uncomment to hide debug msgs.
DEBUG_CHAN='_sharp'                                     # Destination for debug msgs.

###############################################  Subroutines Begin  ###############################################

function has { $(echo "${1}" | grep -P "${2}" > /dev/null) ; }

function say { echo "PRIVMSG ${1} :${2}" ; }

function send {
    while read -r line ; do                                 # -r flag prevents backslash chars from acting as escape chars.
        currdate=$(date +%s%N)                              # Get the current date in nanoseconds (UNIX/POSIX/epoch time) since 1970-01-01 00:00:00 UTC (UNIX epoch).
        if [ "${prevdate}" = "${currdate}" ] ; then         # If 0.5 seconds hasn't elapsed since the last loop iteration, sleep. (i.e. force 0.5 sec send intervals).
            sleep $(bc -l <<< "(${prevdate} - ${currdate}) / ${nanos}")
            currdate=$(date +%s%N)
        fi
        prevdate=${currdate}+${interval}
        echo "-> ${1}"
        echo "${line}" >> ${BOT_NICK}.io
    done <<< "${1}"
}

# This subroutine parses a time input value and sets variables accordingly (e.g. ${h}, ${m}).

function timeSubroutine {
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering timeSubroutine" 2> /dev/null
    payload_timeSubroutine=${1}                                                                 # 0-23, 100-159 .. 2300-2359, 00:00-00:59 .. 23:00-23:59, 1am-12am, 1pm-12pm

    h="$(echo "${payload_timeSubroutine}" | { read t ; date -d ${t} +%H ; })"
    if [[ "$(echo $?)" -eq "1" ]] ; then return 1 ; fi                                          # If format is incorrect, return immediately.
    m="$(echo "${payload_timeSubroutine}" | { read t ; date -d ${t} +%M ; })"
    if [[ "$(echo $?)" -eq "1" ]] ; then return 1 ; fi

    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: timeSubroutine ==> ${h}${m}" 2> /dev/null
}

# This subroutine parses a date input value and sets variables accordingly.
# (e.g. ${day_of_month} ${month} ${day_of_week}).

function daySubroutine {
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering daySubroutine" 2> /dev/null
    payload="${1}"

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
    elif [ -z "$(echo ${payload} | sed -r 's|[0-9]{4}[\/-][0-1]?[0-9]{1}[\/-][0-3]?[0-9]{1}||')" ] ; then     # Verify that input value is of the form: 2018/1/1, or 2018-12-12
        year_t=$(echo ${payload} | sed -r 's|([0-9]{4}).*|\1|')
        month_t=$(echo ${payload} | sed -r 's|[0-9]{4}[\/-]([0-1]?[0-9]{1}).*|\1|')
        day_t=$(echo ${payload} | sed -r 's|[0-9]{4}[\/-][0-1]?[0-9]{1}[\/-]([0-3]?[0-9]{1}).*|\1|')

        if [ "${day_t}" -gt "$(date -d "${month_t}/1 + 1 month - 1 day" "+%d")" ] ; then return 1 ; fi      # If day is out-of-bounds, return immediately.
                                                                                                            # (i.e. specified day exceeds the last day of a given month)

        if [ "${month_t}" -gt "12" ] ; then return 1 ; fi                     # If month is out-of-bounds, return immediately.

        if [ "${year_t}" -lt "${CURRENT_YEAR}" ] ; then return 1 ; fi         # If year is out-of-bounds, return immediately.

        day_of_month=$(echo ${day_t})                                         # Finally, set variables.
        month=$(echo ${month_t})
        day_of_week='*'
    elif [ -z "$(echo ${payload} | sed -r 's|[0-1]?[0-9]{1}[\/-][0-3]?[0-9]{1}[\/-][0-9]?[0-9]{1}||')" ] ; then     # Verify that input value is of the form: 1/1/1, or 12-12-12
        month_t=$(echo ${payload} | sed -r 's|([0-1]?[0-9]{1}).*|\1|')
        day_t=$(echo ${payload} | sed -r 's|[0-1]?[0-9]{1}[\/-]([0-3]?[0-9]{1}).*|\1|')
        year_t=$(echo ${payload} | sed -r 's|[0-1]?[0-9]{1}[\/-][0-3]?[0-9]{1}[\/-]([0-9]?[0-9]{1}).*|\1|')

        if [ "${day_t}" -gt "$(date -d "${month_t}/1 + 1 month - 1 day" "+%d")" ] ; then return 1 ; fi      # If day is out-of-bounds, return immediately.
                                                                                                            # (i.e. specified day exceeds the last day of a given month)

        if [ "${month_t}" -gt "12" ] ; then return 1 ; fi                     # If month is out-of-bounds, return immediately.

        if [ "${year_t}" -lt "${CURRENT_YEAR}" ] ; then return 1 ; fi         # If year is out-of-bounds, return immediately.

        day_of_month=$(echo ${day_t})                                         # Finally, set variables.
        month=$(echo ${month_t})
        day_of_week='*'
    else
        return 1
    fi

    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: daySubroutine ==> ${day_of_month} ${month} ${day_of_week}" 2> /dev/null
}

# This subroutine parses reminder scheduling information within a message payload and generates a cronjob entry.

function parseSubroutine {
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering parseSubroutine" 2> /dev/null
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: payload ==> ${payload}" 2> /dev/null
    payload="${1}"                                          # at 3pm to do something, blah
    payload=" ${payload}"                                 #  at 3pm to do something, blah    <==    ADD WHITESPACE (necessary for parsing).

    at=$(echo ${payload,,} | sed -r 's|.*( )(at [0-9][0-9apm:]*)( ).*|\1\2|')                                 # Populate ${at}.  (a particular time)
    if [[ "${at}" == "${payload,,}" ]] ; then at='' ; fi

    on_d=$(echo ${payload,,} | sed -r 's|.*( )(on [0-9mondaytueswhrfi][0-9\/mondaytueswhrfi-]*)( ).*|\1\2|')  # Populate ${on_d}.  (on a particular day)
    if [[ "${on_d}" == "${payload,,}" ]] ; then on_d='' ; fi

    this_d=$(echo ${payload,,} | sed -r 's|.*( )(this [mondaytueswhrfi]*)( ).*|\1\2|')                        # Populate ${this_d}.  (this monday)
    if [[ "${this_d}" == "${payload,,}" ]] ; then this_d='' ; fi

    next_d=$(echo ${payload,,} | sed -r 's|.*( )(next [mondaytueswhrfi]*)( ).*|\1\2|')                        # Populate ${next_d}.  (next friday...)
    if [[ "${next_d}" == "${payload,,}" ]] ; then next_d='' ; fi

    payload=$(echo ${payload,,} | sed -r 's|(.*)( at [0-9][0-9apm:]*)( .*)|\1\3|')                                  # Get ${task} by removing at phrase from ${payload}
    payload=$(echo ${payload,,} | sed -r 's|(.*)( on [0-9mondaytueswhrfi][0-9\/mondaytueswhrfi-]*)( .*)|\1\3|')     # ... remove on [day of week], [8-8-18], [8/8/18]
    payload=$(echo ${payload,,} | sed -r 's|(.*)( this [mondaytueswhrfi]*)( )(.*)|\1\3\4|')                         # ... remove this [day of week]
    task=$(echo ${payload,,} | sed -r 's|(.*)( next [mondaytueswhrfi]*)( )(.*)|\1\3\4|' | sed -r 's|^[ ]*||' | sed -r 's|[ ]*$||')  # ... remove next [day of week].

    at=$(echo ${at} | sed -r 's|.*at [^0-9]*(.*)|\1|')                                              # at 3:00pm ==> 3:00pm
    on_d=$(echo ${on_d} | sed -r 's|.*on (.*)|\1|')                                                 # on sunday ==> sunday
    this_d=$(echo ${this_d} | sed -r 's|.*this (.*)|\1|')                                           # this fri ==> fri
    next_d=$(echo ${next_d} | sed -r 's|.*next (.*)|\1|')                                           # next wed ==> wed

    ${DEBUG} say ${DEBUG_CHAN} "    at ==> ${at}" 2> /dev/null
    ${DEBUG} say ${DEBUG_CHAN} "  on_d ==> ${on_d}" 2> /dev/null
    ${DEBUG} say ${DEBUG_CHAN} "this_d ==> ${this_d}" 2> /dev/null
    ${DEBUG} say ${DEBUG_CHAN} "next_d ==> ${next_d}" 2> /dev/null
    ${DEBUG} say ${DEBUG_CHAN} "  task ==> ${task}" 2> /dev/null

    if [ -z "${at}" ] && [ -z "${on_d}" ] && [ -z "${this_d}" ] && [ -z "${next_d}" ] ; then return 1 ; fi          # If no fields exist, return immediately.

    if [ -z "${task}" ] ; then return 1 ; fi                        # If ${task} is empty, return immediately.

    if [ -n "${on_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: on sunday at 3:00pm

            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")       # Create the cronjob entry.

        else                                                        # Case: on monday

            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")       # Create the cronjob entry.

        fi
    elif [ -n "${this_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: this tuesday at 4:00am

            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")       # Create the cronjob entry.

        else                                                        # Case: this wednesday

            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")       # Create the cronjob entry.

        fi
    elif [ -n "${next_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: next thursday at 5:00pm

            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            day_of_month=$(date --date="${day_of_week} +1 week" +%d)                  # Add a week to ${day_of_month} and ${month}, and set ${day_of_week} to *.
            month=$(date --date="${day_of_week} +1 week" +%m)
            day_of_week='*'

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")       # Create the cronjob entry.

        else                                                        # Case: next friday

            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")

        fi
    elif [ -n "${at}" ] ; then                                      # Case: at 10:00am
        timeSubroutine "${at}"
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

        current_time=$(date +%H%M)
        if [ "${h}${m}" -lt "${current_time}" ] ; then day=$(date -d '+1 day' +%d)
        else day=$(date +%d) ; fi
        month=$(date +%m)

        cronjob=$(echo "${m} ${h} ${day} ${month} *")

    else                                                            # missing values
        ${DEBUG} say ${DEBUG_CHAN} 'FATAL ERROR: missing values' 2> /dev/null
        return 1
    fi

    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: parseSubroutine ==> ${cronjob}" 2> /dev/null
}

# This subroutine converts a cronjob entry back to standard form.  (e.g. 0 1 2 3 *  ==>  1:00am on Monday, March 2nd)

function convertCronjobSubroutine {
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering convertCronjobSubroutine" 2> /dev/null
    ${DEBUG} say ${DEBUG_CHAN} "          payload ==> ${payload}" 2> /dev/null
    payload=${1}                          # 0 1 2 3 mon   or   * * * * mon

    m=$(echo ${payload} | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\1|')                # Get the minutes.
    h=$(echo ${payload} | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\2|')                # Get the hours.

    if [ "${h}" == "24" ] ; then h='00' ; fi                                        # Special case: if hour is 24, convert to 00.

    day_of_month=$(echo ${payload} | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\3|')     # Get the day of month.
    month=$(echo ${payload} | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\4|')            # Get the month.

    standard_time="$(date --date="${month}/${day_of_month}/$(date +%y) ${h}:${m}" +%I:%M%p\ on\ %A,\ %B\ %d)"           # Generate time in standard form.  (e.g. 05:00AM on Monday, January 22)
    standard_time="$(echo "${standard_time}" | sed -r 's|^0||' | sed -r 's|AM|am|' | sed -r 's|PM|pm|')"                # Format ${standard_time}.         (e.g. 5:00am on Monday, January 22)
    standard_time="$(echo "${standard_time}" | sed -r 's|0([0-9]{1})$|\1|' | sed -r 's| 1$| 1st|' | sed -r 's| 2$| 2nd|' | sed -r 's| 3$| 3rd|' | sed -r 's| 21$| 21st|' | sed -r 's| 22$| 22nd|' | sed -r 's| 23$| 23rd|' | sed -r 's| 31$| 31st|')"              # (e.g. 5:00am on Monday, January 2nd)
    if [[ ! "${standard_time}" =~ *1st* ]] &&
       [[ ! "${standard_time}" =~ *2nd* ]] &&
       [[ ! "${standard_time}" =~ *3rd* ]] ; then
        standard_time="$(echo "${standard_time}" | sed -r 's|([0-9]{1})$|\1th|')"
    fi

    day_of_week="$(echo "${payload}" | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\5|' | sed -r 's|(.{3}).*|\1|')"            # Get the day of week.

    if [ "${day_of_week}" == '*' ] ; then
        true
    elif [ ! $(echo ${day_of_week} | sed -r 's|sun(day)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|mon(day)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|tue(sday)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|wed(nesday)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|thu(rsday)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|fri(day)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|sat(urday)?||') ] ; then
        standard_time=$(date --date="${day_of_week} ${h}:${m}" +%I:%M%p\ on\ %A,\ %B\ %d | sed -r 's|^0||' | sed -r 's|AM|am|' | sed -r 's|PM|pm|')         # Format ${standard_time}.
        standard_time="$(echo "${standard_time}" | sed -r 's|0([0-9]{1})$|\1|' | sed -r 's| 1$| 1st|' | sed -r 's| 2$| 2nd|' | sed -r 's| 3$| 3rd|' | sed -r 's| 21$| 21st|' | sed -r 's| 22$| 22nd|' | sed -r 's| 23$| 23rd|' | sed -r 's| 31$| 31st|')"
        if [[ ! "${standard_time}" =~ *1st* ]] &&
           [[ ! "${standard_time}" =~ *2nd* ]] &&
           [[ ! "${standard_time}" =~ *3rd* ]] ; then
            standard_time="$(echo "${standard_time}" | sed -r 's|([0-9]{1})$|\1th|')"
        fi
    elif [ "${day_of_week}" -ge 0 -a "${day_of_week}" -le 6 ] ; then
        true
    else
        return 1
    fi

    converted_cronjob="${standard_time}"
    ${DEBUG} say ${DEBUG_CHAN} "converted_cronjob ==> ${converted_cronjob}" 2> /dev/null
}

# This subroutine displays the full cronjob entry for a reminder that's being scheduled.

function debugCronjobSubroutine {
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering debugCronjobSubroutine" 2> /dev/null

    if [ $# -gt 1 ] ; then say ${chan} "          cronjob ==> ${min} ${hour} ${day} ${month} *"
    else say ${chan} "          cronjob ==> ${cronjob}" ; fi

    say ${chan} "             uuid ==> ${uuid}"
    say ${chan} "       time_sched ==> ${time_sched}"
    say ${chan} "             chan ==> ${chan}"
    say ${chan} "             nick ==> ${nick}"
    say ${chan} "        recipient ==> ${recipient}"
    say ${chan} "             task ==> ${task}"
}

# This subroutine notifies a user that a reminder is successfully scheduled.

function notifySubroutine {
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering notifySubroutine" 2> /dev/null

    nick=$(echo "${nick}" | sed -r 's| .*||')
    if [[ "${recipient}" == "${nick}" ]] || [ -z "${recipient}" ]; then
        say ${chan} "${nick}: You will be reminded @ ${converted_cronjob}."
    else
        say ${chan} "${nick}: ${recipient} will be reminded @ ${converted_cronjob}."
    fi
}

# This subroutine verifies whether a cronjob entry refers to a future date.

function checkCronjobSubroutine {
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering checkCronjobSubroutine" 2> /dev/null

    if [ $# -gt 1 ] ; then                                              # Case: arg is ==> ${m} {h} ${day_of_month} ${month} ${day_of_week}
        m="${1}"
        h="${2}"
        day_of_month="${3}"
        month="${4}"
        day_of_week="${5}"
    else                                                                # Case: arg is ==> ${cronjob}
        m="$(echo ${1} | sed -r 's| .*||')"
        h="$(echo ${1} | cut -d' ' -f2- | sed -r 's| .*||')"
        day_of_month="$(echo ${1} | cut -d' ' -f3- | sed -r 's| .*||')"
        month="$(echo ${1} | cut -d' ' -f4- | sed -r 's| .*||')"
        day_of_week="$(echo ${1} | cut -d' ' -f5- | sed -r 's| .*||')"
    fi

    ${DEBUG} say ${DEBUG_CHAN} "     ${m} ${h} ${day_of_month} ${month} ${day_of_week}" 2> /dev/null

    # 3 cases for cronjob entries:
    # 1 1 1 1 1
    # 1 1 1 1 *
    # 1 1 * * 1

    if [[ "${m}" != "*" ]] &&                                                       # NOTE: Condition is counterintuitive
       [[ "${h}" != "*" ]] &&                                                       # e.g. "*" == "*" is TRUE, which in bash is 0.
       [[ "${day_of_month}" != "*" ]] &&                                            # Conversely, "1" == "*" is FALSE, which is 1.
       [[ "${month}" != "*" ]] &&
       [[ "${day_of_week}" != "*" ]] ; then

        ${DEBUG} say ${DEBUG_CHAN} "     Case: 1 1 1 1 1" 2> /dev/null
        t1="$(date -d "${month}/${day_of_month}/${CURRENT_YEAR} ${h}:${m}" +%s)"
        if [ "${t1}" -lt "$(date +%s)" ] ; then return 1 ; fi                       # Compare times in epoch format.

    elif [[ "${m}" != "*" ]] &&
         [[ "${h}" != "*" ]] &&
         [[ "${day_of_month}" != "*" ]] &&
         [[ "${month}" != "*" ]] &&
         [[ "${day_of_week}" == "*" ]] ; then

        ${DEBUG} say ${DEBUG_CHAN} "     Case: 1 1 1 1 *" 2> /dev/null
        t1="$(date -d "${month}/${day_of_month}/${CURRENT_YEAR} ${h}:${m}" +%s)"
        if [ "${t1}" -lt "$(date +%s)" ] ; then return 1 ; fi                       # Compare times in epoch format.

    elif [[ "${m}" != "*" ]] &&
         [[ "${h}" != "*" ]] &&
         [[ "${day_of_month}" == "*" ]] &&
         [[ "${month}" == "*" ]] &&
         [[ "${day_of_week}" != "*" ]] ; then

        ${DEBUG} say ${DEBUG_CHAN} "     Case: 1 1 * * 1" 2> /dev/null
        if [[ "${day_of_week}" = "0" ]] ; then day_of_week='sun'
        elif [[ "${day_of_week}" = "1" ]] ; then day_of_week='mon'
        elif [[ "${day_of_week}" = "2" ]] ; then day_of_week='tue'
        elif [[ "${day_of_week}" = "3" ]] ; then day_of_week='wed'
        elif [[ "${day_of_week}" = "4" ]] ; then day_of_week='thu'
        elif [[ "${day_of_week}" = "5" ]] ; then day_of_week='fri'
        elif [[ "${day_of_week}" = "6" ]] ; then day_of_week='sat' ; fi

        t1="$(date -d "${h}:${m} ${day_of_week}" +%s)"
        if [ "${t1}" -lt "$(date +%s)" ] ; then return 1 ; fi                       # Compare times in epoch format.

    else
        return 1
    fi

    ${DEBUG} say ${DEBUG_CHAN} "     ~~> ${m} ${h} ${day_of_month} ${month} ${day_of_week}" 2> /dev/null
}

#   Example of cronjob definition:        ########################################################################
#   .---------------- minute (0 - 59)
#   |  .------------- hour (0 - 23)
#   |  |  .---------- day of month (1 - 31)
#   |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
#   |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
#   |  |  |  |  |
#   *  *  *  *  * user-name  command to be executed        #######################################################
#
# Example of a cronjob entry for a reminder:
#
# ${min} ${hour} ${day} ${month} * echo "${uuid}: $(date), ${chan}, ${nick}, ${task}" >> ${DIR_PATH}/tasks/tmp
#
# ^------------------------------^ ^-------------------------------------------------------------------------^
#
#    Time to execute the cmd.           Cmd to be executed, which appends a string to a file called tmp.
#                                       uuid ==> Universal Unique Identifier is used to distinguish each reminder.
#                                       chan ==> The channel destination for the reminder.
#                                       nick ==> The nick who initially scheduled the reminder.
#                                       task ==> The actual task, or reminder.
#
# Explanation of how this program works:
#
# A reminder is saved as a cronjob for future execution.
# In _reminderbot.sh, an endless while loop looks for a tmp file in ${DIR_PATH}/tasks.
# As soon as a tmp file is generated by a cronjob execution, _reminderbot.sh runs signalSubroutine
# which sends signal msgs to _reminderbot.  Signal msgs contain information about one or more
# reminders, which includes who scheduled the reminder, the channel the reminder was scheduled in,
# the time of when the reminder was scheduled, and finally, the reminder or the task itself.
# In commands.sh, there is a handler that manages incoming signal msgs and forwards all reminders
# to the appropriate chan/nick.
#
#
# To debug, see above (commands.sh: 30).
#
##################################################################################################################

# This subroutine parses a message for a reminder scheduling information, and adds a cronjob.

function cronjobSubroutine {
    ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering cronjobSubroutine" 2> /dev/null
    payload="${1}"                                                          # Entire message (e.g. on saturday to do something, tomorrow to do the thing).
    ${DEBUG} say ${DEBUG_CHAN} "payload ==> ${payload}" 2> /dev/null

    if [[ "${2}" = "NONE" ]] ; then                                         # ${recipient} is populated when someone sets a reminder for someone else.
        recipient=''
    else
        recipient="${2}"
    fi

    if [[ "$(echo ${payload,,} | sed -r 's|^(tomorrow).*|\1|')" == "tomorrow" ]] || [[ "$(echo ${payload,,} | sed -r 's|^(tmrw).*|\1|')" == "tmrw" ]] ; then    # Case: tomorrow to do something ...
        ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering cronjobSubroutine A" 2> /dev/null

        payload=$(echo ${payload} | sed -r 's|^tomorrow[ ]?||' | sed -r 's|^tmrw[ ]?||')                    # Cut 'tomorrow' or 'tmrw' from ${payload}.
        at=$(echo ${payload} | sed -r 's|(.*)(at [0-9][0-9apm:]*)(.*)|\2|')                                 # 

        if [ "${at}" == "${payload}" ] ; then                               # Case: 'at 300' doesn't exist; default to 9:00am
            t='9:00am'
            timeSubroutine "${t}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
        else
            t=$(echo ${at} | sed -r 's|^at ||')                             # Set ${at}.
            timeSubroutine "${t}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
        fi

        task="$(echo ${payload} | sed -r "s|^${at} ||")"                    # If ${task} is missing, return immediately.
        task="$(echo ${payload} | sed -r "s|^(.{${REM_MAX_LEN}}).*|\1|")"   # Truncate task if necessary.
        if [ -z "${task}" ] ; then return 1 ; fi

        day_of_month=$(date --date="tomorrow" +%d)                          # Get tomorrow's time.
        month=$(date --date="tomorrow" +%m)
        day_of_week=$(date --date="tomorrow" +%w)
        cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")

        if [ -n "${recipient}" ] ; then                                     # Special case: ${nick} created a reminder on behalf of ${recipient}.
            nick=$(echo "${nick} ${recipient}")
        fi

        checkCronjobSubroutine "${cronjob}"
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

        uuid="${UUIDGEN}"
        time_sched="$(date)"
        (crontab -l ; echo "${cronjob} echo \"${uuid}: ${time_sched}, ${chan}, ${nick}, ${task}\" >> ${DIR_PATH}/tasks/tmp") | crontab -       # Create a new cronjob entry.  (NOTE: when a cronjob is executed, ../tmp will be created.  Then, __reminderbot will send contents of tmp to _reminderbot, and remove tmp.)
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

        ${DEBUG} debugCronjobSubroutine "${cronjob}" 2> /dev/null
        convertCronjobSubroutine "${cronjob}"                                               # convertCronjobSubroutine sets ${converted_cronjob}.
        notifySubroutine

    elif [ ! "$(echo ${payload} | sed -r 's|^(in ([0-9]+[dhm]{1})+).*|\1|')" == "${payload}" ] ; then               # Case: in 1d2h3m to do something
        ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering cronjobSubroutine B" 2> /dev/null

        times_array=$(echo ${payload} | sed -r 's|^in ([0-9dhm]*) .*|\1|')                                  # 3d2h1m        
        ${DEBUG} say ${DEBUG_CHAN} "times_array ==> |${times_array}|" 2> /dev/null
        times_array=$(echo ${times_array} | sed -r 's|d|d |g' | sed -r 's|h|h |g' | sed -r 's|m|m |g')              # 3d 2h 1m
        ${DEBUG} say ${DEBUG_CHAN} "times_array ==> |${times_array}|" 2> /dev/null

        ARRAY=()
        while [[ -n "${times_array}" ]] ; do                                                # Append each time to an array.
            segment="$(echo ${times_array} | sed -r 's| .*||')"
            ${DEBUG} say ${DEBUG_CHAN} "adding to times_array ==> ${segment}" 2> /dev/null
            ARRAY+=("${segment}")
            times_array=$(echo ${times_array} | cut -d " "  -f2-)
        done

        for i in "${ARRAY[@]}" ; do                                                         # Populate days, hours, minutes variables.
            if [[ "${i}" == *h* ]] ; then hours=$(echo ${i} | sed -r 's|h||')
            elif [[ "${i}" == *m* ]] ; then minutes=$(echo ${i} | sed -r 's|m||')
            elif [[ "${i}" == *d* ]] ; then days=$(echo ${i} | sed -r 's|d||')
            else
                return 1
            fi
        done

        task="$(echo ${payload} | sed -r 's|^in ([0-9]+[dhm]{1}){1}([0-9]+[dhm]{1})* (.*)|\3|' | sed 's|^[ ]*||' | sed 's|[ ]*$||')"        # Get the task.
        task="$(echo ${task} | fold -w ${REM_MAX_LEN})"   # Truncate task if necessary.
        ${DEBUG} say ${DEBUG_CHAN} "task ==> ${task}" 2> /dev/null
        if [ -z "${task}" ] ; then return 1 ; fi

        if [ -z "${days}" ] && [ -z "${hours}" ] && [ -z "${minutes}" ] ; then return 1 ; fi                                                         # If d,h,m are all missing, return immediately.

        if [ -z "${days}" ] ; then days='0d' ; fi                               # Populate remaining empty variables with default values.
        if [ -z "${hours}" ] ; then hours='0h' ; fi
        if [ -z "${minutes}" ] ; then minutes='0m' ; fi

        days=$(echo ${days} | sed -r 's/d//')
        hours=$(echo ${hours} | sed -r 's/h//')
        minutes=$(echo ${minutes} | sed -r 's/m//')

        ${DEBUG} say ${DEBUG_CHAN} "minutes ==> ${minutes}" 2> /dev/null
        ${DEBUG} say ${DEBUG_CHAN} "hours ==> ${hours}" 2> /dev/null
        ${DEBUG} say ${DEBUG_CHAN} "days ==> ${days}" 2> /dev/null

        if [ "${days}" -gt 365 ] || [ "${hours}" -gt 100 ] || [ "${minutes}" -gt 1440 ] ; then
            say ${chan} "specified time is out-of-bounds"
            return 1
        fi

        ce_time=$(date +%s)                                                                     # Get current epoch time.
        e_time=$(( ${days}*24*60*60 + ${hours}*60*60 + ${minutes}*60 + ${ce_time} ))            # Convert #d#h#m ==> epoch time
                                                                                                # (d * 24 * 60 * 60) + (h * 60 * 60) + (m * 60) + current_epoch_time

        s_time=$(date -d @${e_time} +%M%H%d%m)                                                  # Convert epoch time ==> [min][hour][day][month]
        min=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\1/')
        hour=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\2/')
        day=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\3/')
        month=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\4/')

        if [ -n "${recipient}" ] ; then                                 # Special case: ${nick} created a reminder on behalf of ${recipient}.
            nick=$(echo "${nick} ${recipient}")
        fi

        ${DEBUG} debugCronjobSubroutine "before sched: ${min}" "${hour}" "${day}" "${month}" "*" 2> /dev/null

        checkCronjobSubroutine "${min}" "${hour}" "${day}" "${month}" "*"               # Verify cronjob.
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

        uuid="${UUIDGEN}"
        time_sched="$(date)"
        (crontab -l ; echo "${min} ${hour} ${day} ${month} * echo \"${uuid}: ${time_sched}, ${chan}, ${nick}, ${task}\" >> ${DIR_PATH}/tasks/tmp") | crontab -        # Create a new cronjob entry.
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

        ${DEBUG} debugCronjobSubroutine "after sched: ${min}" "${hour}" "${day}" "${month}" "*" 2> /dev/null

        standard_time="$(date -d @${e_time} +%I:%M%p\ on\ %A,\ %B\ %d | sed -r 's|^0||' | sed -r 's|AM|am|' | sed -r 's|PM|pm|')"                               # 1:00pm on Sunday, February 4.
        standard_time="$(echo "${standard_time}" | sed -r 's|0([0-9]{1})$|\1|' | sed -r 's| 1$| 1st|' | sed -r 's| 2$| 2nd|' | sed -r 's| 3$| 3rd|' | sed -r 's| 21$| 21st|' | sed -r 's| 22$| 22nd|' | sed -r 's| 23$| 23rd|' | sed -r 's| 31$| 31st|')"                 # 01 ==> 1, 1 ==> 1st, etc.
        if [[ ! "${standard_time}" =~ *1st* ]] &&
           [[ ! "${standard_time}" =~ *2nd* ]] &&
           [[ ! "${standard_time}" =~ *3rd* ]] ; then
            standard_time="$(echo "${standard_time}" | sed -r 's|([0-9]{1})$|\1th|')"
        fi

        converted_cronjob="${standard_time}"
        notifySubroutine

    elif [ ! "$(echo ${payload} | perl -pe 's|^(in )([0-9]* \w+ )+(.*)||')" == "${payload}" ] ; then                                        #  in 1 hour do something ==> in 1 hour
        ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering cronjobSubroutine C" 2> /dev/null

        times_array=$(echo ${payload} | sed -r 's|^in (.*( hour[s]? \| hr[s]? \| minute[s]? \| min[s]? \| day[s]? )).*|\1|')                # 1 hour 4 days 12 minutes
        task=$(echo ${payload} | sed -r 's|^in (.*( hour[s]? \| hr[s]? \| minute[s]? \| min[s]? \| day[s]? ))*(.*)|\3|' | sed -r 's|^[ ]*||' | sed -r 's|[ ]*$||')
        if [ -z "${task}" ] ; then return 1 ; fi
        ${DEBUG} say ${DEBUG_CHAN} "      times_array ==> ${times_array}" 2> /dev/null
        ${DEBUG} say ${DEBUG_CHAN} "             task ==> ${task}" 2> /dev/null
        ${DEBUG} say ${DEBUG_CHAN} "------------------------------------------" 2> /dev/null
        ARRAY=()
        while [[ -n "${times_array}" ]] ; do                                                        # Append each time segment to an array.
            time_seg=$(echo "${times_array}" | sed -r 's|^([0-9]*) ([a-zA-Z]*) .*|\1 \2|')          # Get a time segment.  (e.g. 12 minutes)
            ${DEBUG} say ${DEBUG_CHAN} "         time_seg ==> ${time_seg}" 2> /dev/null

            if [ -n "$(echo "${time_seg}" | sed -r 's|^[0-9][0-9]* hour[s]?||')" ] ||               # 15 minutes ==> 15 minutes     return code: 0
               [ -n "$(echo "${time_seg}" | sed -r 's|^[0-9][0-9]* hr[s]?||')" ] ||                 # 15 minutes ==> 15 minutes     return code: 0
               [ -n "$(echo "${time_seg}" | sed -r 's|^[0-9][0-9]* minute[s]?||')" ] ||             # 15 minutes ==>                return code: 1
               [ -n "$(echo "${time_seg}" | sed -r 's|^[0-9][0-9]* min[s]?||')" ] ||                # 15 minutes ==> 15 minutes     return code: 0
               [ -n "$(echo "${time_seg}" | sed -r 's|^[0-9][0-9]* day[s]?||')" ] ; then            # 15 minutes ==> 15 minutes     return code: 0

               ARRAY+=("${time_seg}")                                                               # If ${time_seg} is in the correct format,
                                                                                                    # add it to ${ARRAY}.
            else
                ${DEBUG} say ${DEBUG_CHAN} "      fail time_seg ==> ${time_seg}" 2> /dev/null
                ${DEBUG} say ${DEBUG_CHAN} "FATAL ERROR: cronjobSubroutine C" 2> /dev/null
                return 1                                                                            # If a time segment is not in the correct form (e.g. and 1 hour), return immediately.
            fi

            times_array=$(echo "${times_array}" | cut -d " "  -f3-)                                 # Remove the time segment from ${times_array}.
            times_array="$(echo "${times_array}" | sed -r 's|^and[ ]*||')"                          # Remove any preceding 'and's.
            ${DEBUG} say ${DEBUG_CHAN} "      times_array ==> ${times_array}" 2> /dev/null
            ${DEBUG} say ${DEBUG_CHAN} "------------------------------------------" 2> /dev/null
        done

        for i in "${ARRAY[@]}" ; do                                                                 # Populate days, hours, minutes variables.
            if [[ "${i}" == *hour* ]] || [[ "${i}" == *hr* ]] ; then hours=$(echo ${i} | sed -r 's| .*||')
            elif [[ "${i}" == *minute* ]] || [[ "${i}" == *min* ]] ; then minutes=$(echo ${i} | sed -r 's| .*||')
            elif [[ "${i}" == *day* ]] ; then days=$(echo ${i} | sed -r 's| .*||')
            else
                return 1
            fi
        done

        ${DEBUG} say ${DEBUG_CHAN} "       hours ==> ${hours}" 2> /dev/null
        ${DEBUG} say ${DEBUG_CHAN} "     minutes ==> ${minutes}" 2> /dev/null
        ${DEBUG} say ${DEBUG_CHAN} "        days ==> ${days}" 2> /dev/null

        if [ -z ${days} ] && [ -z ${hours} ] && [ -z ${minutes} ] ; then                            # If d,h,m are missing, return immediately.
            if [ $(echo ${days}${hours}${minutes} | sed 's/[ 0-9dhm]*//') ] ; then return 1 ; fi
        fi

        if [ -z "${days}" ] ; then days='0' ; fi                                                    # Otherwise, populate remaining empty variables with default values.
        if [ -z "${hours}" ] ; then hours='0' ; fi
        if [ -z "${minutes}" ] ; then minutes='0' ; fi

        ce_time=$(date +%s)                                                                         # current epoch time
        e_time=$(( ${days}*24*60*60 + ${hours}*60*60 + ${minutes}*60 + ${ce_time} ))                # convert #d#h#m ==> epoch time
                                                                                                    # (d * 24 * 60 * 60) + (h * 60 * 60) + (m * 60)

        s_time=$(date -d @${e_time} +%M%H%d%m)                                                      # convert epoch time ==> standard time
        min=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\1/')
        hour=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\2/')
        day=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\3/')
        month=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\4/')

        if [ -n "${recipient}" ] ; then                                 # Special case: ${nick} created a reminder on behalf of ${recipient}.
            nick=$(echo "${nick} ${recipient}")
        fi

        checkCronjobSubroutine "${min}" "${hour}" "${day}" "${month}" "*"
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

        uuid="${UUIDGEN}"
        time_sched="$(date)"
        (crontab -l ; echo "${min} ${hour} ${day} ${month} * echo \"${uuid}: ${time_sched}, ${chan}, ${nick}, ${task}\" >> ${DIR_PATH}/tasks/tmp") | crontab -        # Create a new cronjob entry.

        ${DEBUG} debugCronjobSubroutine "${min}" "${hour}" "${day}" "${month}" "*" 2> /dev/null

        standard_time="$(date -d @${e_time} +%I:%M%p\ on\ %A,\ %B\ %d | sed -r 's|^0||' | sed -r 's|AM|am|' | sed -r 's|PM|pm|')"                               # 1:00pm on Sunday, February 4.
        standard_time="$(echo "${standard_time}" | sed -r 's|0([0-9]{1})$|\1|' | sed -r 's| 1$| 1st|' | sed -r 's| 2$| 2nd|' | sed -r 's| 3$| 3rd|' | sed -r 's| 21$| 21st|' | sed -r 's| 22$| 22nd|' | sed -r 's| 23$| 23rd|' | sed -r 's| 31$| 31st|')"                 # 01 ==> 1, 1 ==> 1st, etc.
        if [[ ! "${standard_time}" =~ *1st* ]] &&
           [[ ! "${standard_time}" =~ *2nd* ]] &&
           [[ ! "${standard_time}" =~ *3rd* ]] ; then
            standard_time="$(echo "${standard_time}" | sed -r 's|([0-9]{1})$|\1th|')"
        fi

        converted_cronjob="${standard_time}"
        notifySubroutine

    else                                                                                # on sun at 300, next monday at 3:00pm, this sunday
        ${DEBUG} say ${DEBUG_CHAN} "DEBUG: entering cronjobSubroutine D" 2> /dev/null

        parseSubroutine "${payload}"
        if [ "$(echo $?)" == "1" ] ; then                                               # If parseSubroutine fails, return immediately.
            ${DEBUG} say ${DEBUG_CHAN} "DEBUG: parseSubroutine failed" 2> /dev/null
            return 1
        fi

        if [ -n "${recipient}" ] ; then                                                 # Special case: ${nick} created a reminder on behalf of ${recipient}.
            nick=$(echo "${nick} ${recipient}")
        fi

        checkCronjobSubroutine "${cronjob}"
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

        uuid="${UUIDGEN}"
        time_sched="$(date)"
        (crontab -l ; echo "${cronjob} echo \"${uuid}: ${time_sched}, ${chan}, ${nick}, ${task}\" >> ${DIR_PATH}/tasks/tmp") | crontab -       # Create a new cronjob entry.
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

        ${DEBUG} debugCronjobSubroutine "${cronjob}" 2> /dev/null
        convertCronjobSubroutine "${cronjob}"                                           # convertCronjobSubroutine sets ${converted_cronjob}.
        notifySubroutine
    fi
}

# This subroutine displays documentation for _reminderbot's functionalities.

function helpSubroutine {
    say ${chan} "${nick}: I will remind you of stuff!  DISCLAIMER: I am not liable for your forgetfulness."
    say ${chan} 'usage: remind me in 3d2h1m ... | remind me in 1m2h1d ... | remind me in 1d ...'
    say ${chan} '       remind me in 5 days 4 hours 3 minutes ... | remind me in 2 hrs 3 mins ...'
    say ${chan} '       remind me on sun at 1705 ... | remind me at 3:00pm on 8/8/18 ...'
    say ${chan} '       remind me at 23:59 on 9-9-18 ... | remind me on 3/13/18 at 12pm ...'
    say ${chan} '       remind me tomorrow ... | remind me tmrw at 6 ...'
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

elif has "${msg}" "^!alive(\?)?$" && [[ "${AUTHORIZED}" == *"${nick}"* ]] ; then
    str1='running! '
    str2=$(ps aux | grep ./_reminderbot | head -n 1 | awk '{ print "[%CPU "$3"]", "[%MEM "$4"]", "[VSZ "$5"]" }')
    str3=" [#REM $(crontab -l | tail -n +3 | wc -l)]"
    str4=" [SIZE $(ls -lash | head -n 1 | cut -d ' ' -f2-)]"
    str5=" [TOT_SIZE $(du -sh | cut -f -1)]"
    str="${str1}${str2}${str3}${str4}${str5}"
    say ${chan} "${str}"

elif has "${msg}" "^_reminderbot: alive(\?)?$" ; then
    str1='running! '
    str2=$(ps aux | grep ./_reminderbot | head -n 1 | awk '{ print "[%CPU "$3"]", "[%MEM "$4"]", "[VSZ "$5"]" }')
    str3=" [#REM $(crontab -l | tail -n +3 | wc -l)]"
    str4=" [SIZE $(ls -lash | head -n 1 | cut -d ' ' -f2-)]"
    str5=" [TOT_SIZE $(du -sh | cut -f -1)]"
    str="${str1}${str2}${str3}${str4}${str5}"
    say ${chan} "${str}"

# Source.

elif has "${msg}" "^_reminderbot: source$" ; then
    say ${chan} "Try -> https://github.com/kimdj/_reminderbot -OR- ${DIR_PATH}"

# Handle a reminder request.

elif has "${msg}" "^remind me " ; then
    cronjob_len=$(crontab -l | wc -l)                                                                       # Get the current number of cronjobs.
    if [ "${cronjob_len}" -gt "${MAX_REM}" ] ; then                                                         # Max reminders.
        say ${chan} "YAY!!! You have officially reached the self-imposed maximum number of reminders (i.e. MAX=${MAX_REM})."
        say ${chan} "I suggest that you remind yourself :D or, try again later."
        return 1
    fi

    payload=$(echo ${msg} | sed -r 's/^remind me //')                                                       # Remove 'remind me '.
    payload=$(echo ${payload} | sed -r 's|[^ a-zA-Z0-9:/-]||g' | sed 's/>//g' | sed 's/<//g')               # Sanitize user input (i.e. remove non-alphanumeric characters).

    cronjobSubroutine "${payload}" "NONE"
    if [ "$(echo $?)" == "1" ] ; then say ${chan} "Sorry, I couldn't setup your reminder." ; fi             # Case: error within cronjobSubroutine.

# Handle a reminder request on behalf of another user.

elif has "${msg}" "^remind " ; then
    cronjob_len=$(crontab -l | wc -l)                                                                       # Get the current number of cronjobs.
    if [ "${cronjob_len}" -gt "${MAX_REM}" ] ; then                                                         # Max reminders.
        say ${chan} "YAY!!! You have officially reached the self-imposed maximum number of reminders (i.e. MAX=${MAX_REM})."
        say ${chan} "I suggest that you remind yourself :D or, try again later."
        return 1
    fi

    payload=$(echo ${msg} | sed -r 's/^remind //')                                                          # Remove 'remind me '.
    recipient=$(echo ${payload} | sed -r 's/ .*//')                                                         # Get the recipient's nick.
    payload=$(echo ${payload} | cut -d' ' -f2-)
    payload=$(echo ${payload} | sed -r 's|[^ a-zA-Z0-9:/-]||g' | sed 's/>//g' | sed 's/<//g')               # Sanitize user input (i.e. remove non-alphanumeric characters).

    cronjobSubroutine "${payload}" "${recipient}"
    if [ "$(echo $?)" == "1" ] ; then say ${chan} "Sorry, I couldn't setup your reminder." ; fi             # Case: error within cronjobSubroutine.

# Handle incoming msg from self (_reminderbot => _reminderbot).

elif has "${msg}" "^!signal " && [[ ${nick} = "_reminderbot" ]]; then
    payload=$(echo ${msg} | sed -r 's|!signal (.*)|\1|')
    task=$(echo ${payload} | sed -r 's|~.*||' | sed -r 's|[ ]*$||')
    time_sched=$(echo ${payload} | sed -r 's|.*~(.*)~.*~.*|\1|' | sed -r 's|^[ ]*||' | sed -r 's|[ \)]*$||')
    time_sched=$(date --date="${time_sched}" +"%a, %b %d %I:%M%P")
    chan=$(echo ${payload} | sed -r 's|^(.*) ~ (.*) ~ (.*)|\2|')
    nick=$(echo ${payload} | sed -r 's|^(.*) ~ (.*) ~ (.*) ~ (.*)|\4|')

    recipient="$(echo ${nick} | cut -d ' ' -f2-)"
    nick="$(echo ${nick} | sed -r 's| .*||')"

    if [[ "${recipient}" = "${nick}" ]] ; then
        say ${chan} "${nick}: On ${time_sched}, you asked me to remind you ${task}."
    else
        say ${chan} "${recipient}: On ${time_sched}, ${nick} asked me to remind you ${task}."        
    fi

# Authorized users (refer to 'commands.sh: 23') can send internal IRC commands to the IRC server.  (e.g. _reminderbot: injectcmd join #bots auth_key)

elif has "${msg}" "^_reminderbot: injectcmd " && [[ "${AUTHORIZED}" == *"${nick}"* ]] ; then
    cmd=$(echo ${msg} | sed -r 's/^_reminderbot: injectcmd //')
    send "${cmd}"

# Authorized users can send msgs as _reminderbot to other users/channels.  (e.g. _reminderbot: sendcmd #bots test msg)

elif has "${msg}" "^_reminderbot: sendcmd " && [[ "${AUTHORIZED}" == *"${nick}"* ]] ; then
    buffer=$(echo ${msg} | sed -re 's/^_reminderbot: sendcmd //')
    dest=$(echo ${buffer} | sed -e "s| .*||")
    message=$(echo ${buffer} | cut -d " " -f2-)
    say ${dest} "${message}"

fi

#################################################  Commands End  ################################################## 

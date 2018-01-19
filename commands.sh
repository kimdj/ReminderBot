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

MAX_REM='500'                                       # Maximum number of reminders (or maximum number of cronjobs).
AUTHORIZED='_sharp MattDaemon'                      # List of users authorized to execute bot commands (e.g. injectcmd, sendcmd).

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
# say ${chan} 'time format OK'
        return 0
    else
# say ${chan} 'time format FAIL'
        return 1
    fi
}

# This subroutine parses a time input value and sets variables accordingly (e.g. ${h}, ${m}).

function timeSubroutine {
# say ${chan} "==> entering timeSubroutine"
# say ${chan} "==> payload: ${1}"
    payload=${1}                                                                    # 12:00am  12:00pm  0000  2400  00:00  24:00  3pm
    checkFormatSubroutine "${payload}"
    if [[ $? -eq 1 ]] ; then return 1 ; fi                                          # If format is incorrect, return immediately.

    if [ ${#payload} == 4 ] ; then
        h=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}).*|\1|')                        # Strip the hours, minutes, and am/pm.
    else
        h=$(echo ${payload} | sed -r 's|([0-9]{1}).*|\1|')                        # Strip the hours, minutes, and am/pm.
    fi
    m=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}):?([0-9]{2}).*|\2|')
    if [[ "${m}" == "${payload}" ]] ; then m='00' ; fi                              # Case: 3pm ==> 00 min default
    am_pm=$(echo ${payload} | sed -r 's|.*([a|p]m).*|\1|')
    if [[ "${am_pm}" == "${payload}" ]] ; then am_pm='am' ; fi                      # Case: 3:00 ==> am default

    if [ "${h}" -gt "23" ] && [ "${m}" -gt "0" ] ; then                             # 2401 and greater is out-of-bounds
        say ${chan} 'time is out-of-bounds'
        return 1
    fi

    if [ "${h}" -gt "24" ] ; then                                                   # hour range: 0-24
        say ${chan} 'time is out-of-bounds'
        return 1
    fi

    if [ "${m}" -gt "59" ] ; then                                                   # minutes range: 0-59
        say ${chan} 'time is out-of-bounds'
        return 1
    fi

    if [ "${am_pm}" == "pm" ] ; then                                                # Standardize to military time.
        h=$(expr ${h} + 12)
    elif [ "${h}" == "12" ] && [ "${am_pm}" == "am" ] ; then
        h='00'
    fi
# say ${chan} "==> ${h}${m}"
}

# This subroutine parses a date input value and sets variables accordingly (e.g. ${day_of_month}, ${month}, ${day_of_week}).

function daySubroutine {
# say ${chan} "==> entering daySubroutine"
# say ${chan} "==> daySubroutine payload: ${1}"
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

# say ${chan} "==> =========================> ${month_t}"
# say ${chan} "==> =========================> ${day_t}"
# say ${chan} "==> =========================> ${year_t}"

        if [ "${day_t}" -gt "$(date -d "${month_t}/1 + 1 month - 1 day" "+%d")" ] ; then        # If day is out-of-bounds, return immediately.
            return 1                                                                            # (i.e. specified day exceeds the last day of a given month)
        fi

        if [ "${month_t}" -gt "12" ] ; then      # If month is out-of-bounds, return immediately.
            return 1
        fi

        if [ "${year_t}" -lt "18" ] ; then      # If year is out-of-bounds, return immediately.
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
    payload=${1}                                          # at 3pm to do something, blah
# say ${chan} "==> payload: ${payload}"

    at=$(echo ${payload} | sed -r 's|(.*)(at [0-9][0-9apm:]*)(.*)|\2|')                             # Populate ${at}.
    if [[ "${at}" == "${payload}" ]] ; then at=$(echo ${payload} | sed -r 's|.*||') ; fi

    on_d=$(echo ${payload} | sed -r 's|.*(on [0-9mondaytueswhrfi][0-9\/mondaytueswhrfi-]*).*|\1|')  # Populate ${on_d}.
    if [[ "${on_d}" == "${payload}" ]] ; then on_d=$(echo ${payload} | sed -r 's|.*||') ; fi

    this_d=$(echo ${payload} | sed -r 's|.*(this [mondaytueswhrfi]*).*|\1|')                        # Populate ${this_d}.
    if [[ "${this_d}" == "${payload}" ]] ; then this_d=$(echo ${payload} | sed -r 's|.*||') ; fi

    next_d=$(echo ${payload} | sed -r 's|.*(next [mondaytueswhrfi]*).*|\1|')                        # Populate ${next_d}.
    if [[ "${next_d}" == "${payload}" ]] ; then next_d=$(echo ${payload} | sed -r 's|.*||') ; fi

    payload=$(echo ${payload} | sed -r 's|(.*)(at [0-9][0-9apm:]* )(.*)|\1\3|')
    payload=$(echo ${payload} | sed -r 's|(.*)(on [0-9mondaytueswhrfi][0-9\/mondaytueswhrfi-]* )(.*)|\1\3|')
    payload=$(echo ${payload} | sed -r 's|(.*)(this [mondaytueswhrfi]*)(.*)|\1\3|')
    task=$(echo ${payload} | sed -r 's|(.*)(next [mondaytueswhrfi]*)(.*)|\1\3|' | sed -r 's|^[ ]*||' | sed -r 's|[ ]*$||')  # Populate ${task}.

# say ${chan} "====================================> task: ${task}"
# echo "    at: ${at}"
# echo "  on_d: ${on_d}"
# echo "this_d: ${this_d}"
# echo "next_d: ${next_d}"
# echo " "

    at=$(echo ${at} | sed -r 's|.*at [^0-9]*(.*)|\1|')                                              # at 3:00pm ==> 3:00pm
    on_d=$(echo ${on_d} | sed -r 's|.*on (.*)|\1|')                                                 # on sunday ==> sunday
    this_d=$(echo ${this_d} | sed -r 's|.*this (.*)|\1|')                                           # this fri ==> fri
    next_d=$(echo ${next_d} | sed -r 's|.*next (.*)|\1|')                                           # next wed ==> wed

# echo "    at ==> ${at}"
# echo "  on_d ==> ${on_d}"
# echo "this_d ==> ${this_d}"
# echo "next_d ==> ${next_d}"

    if [ -z "${at}" ] && [ -z "${on_d}" ] && [ -z "${this_d}" ] && [ -z "${next_d}" ] ; then
        say ${chan} "ERROR: $(uuidgen)"
        return 1
    fi

#   Example of cronjob definition:        ########################################################
#   .---------------- minute (0 - 59)
#   |  .------------- hour (0 - 23)
#   |  |  .---------- day of month (1 - 31)
#   |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
#   |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
#   |  |  |  |  |
#   *  *  *  *  * user-name  command to be executed        #######################################

    if [ -n "${on_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: on sunday at 3:00pm
# say ${chan} 'Case: on ... , at ...'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
# say ${chan} "==> cronjob: ${cronjob}"
        else                                                        # Case: on monday
# say ${chan} 'Case: on ...'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
# say ${chan} "==> cronjob: ${cronjob}"
        fi
    elif [ -n "${this_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: this tuesday at 4:00am
# say ${chan} 'Case: this ... , at ...'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
# say ${chan} "==> cronjob: ${cronjob}"
        else                                                        # Case: this wednesday
# say ${chan} 'Case: this ...'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
# say ${chan} "==> cronjob: ${cronjob}"
        fi
    elif [ -n "${next_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: next thursday at 5:00pm
# say ${chan} 'Case: next ..., at ...'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
# say ${chan} "==> cronjob: ${cronjob}"
        else                                                        # Case: next friday
# say ${chan} 'Case: next ...'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
# say ${chan} "==> cronjob: ${cronjob}"
        fi
    elif [ -n "${at}" ] ; then                                      # Case: at 10:00am
# say ${chan} 'Case: at ...'
        timeSubroutine "${at}"

        current_time=$(date +%H%M)
        if [ "${h}${m}" -lt "${current_time}" ] ; then
            day=$(date -d '+1 day' +%d)
        else
            day=$(date +%d)
        fi
        month=$(date +%m)

        cronjob=$(echo "${m} ${h} ${day} ${month} *")
# say ${chan} "==> cronjob: ${cronjob}"
    else                                                            # missing values
        say ${chan} 'FATAL ERROR: missing values'
        return 1
    fi

# say ${chan} "==> END REACHED; SUCCESS!"
}

# This subroutine converts a cronjob entry back to standard form.

function convertCronjobSubroutine {
    payload=${1}                          # 0 1 2 3 mon   or   * * * * mon
# say ${chan} "=====> ${payload}"
    m=$(echo ${payload} | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\1|')
    h=$(echo ${payload} | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\2|')

    if [ "${h}${m}" == "2400" ] ; then h='00' ; fi                  # Special case: if 2400, convert to 0000.

    day_of_month=$(echo ${payload} | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\3|')
    month=$(echo ${payload} | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\4|')
# day_of_month_plus_month=$(date -d "${month}/${day_of_month}" | sed -r 's|(.*) (.*) (.*).*|\2 \3|')
# say ${chan} "${m} ${h} ${day_of_month} ${month}"
    c=$(date --date="${month}/${day_of_month}/$(date +%y) ${h}:${m}")
# say ${chan} "c ==============> ${c}"
# say ${chan} "payload ==> ${payload}"
    day_of_week="$(echo "${payload}" | sed -r 's|(.*) (.*) (.*) (.*) (.*).*|\5|' | sed -r 's|(.{3}).*|\1|')"
# say ${chan} "day_of_week =====> ${day_of_week}"
    if [ "${day_of_week}" == '*' ] ; then
        true
    elif [ ! $(echo ${day_of_week} | sed -r 's|sun(day)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|mon(day)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|tue(sday)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|wed(nesday)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|thu(rsday)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|fri(day)?||') ] ||
         [ ! $(echo ${day_of_week} | sed -r 's|sat(urday)?||') ] ; then
        c=$(date --date="${day_of_week} ${h}:${m}")
    elif [ "${day_of_week}" -ge 0 -a "${day_of_week}" -le 6 ] ; then
        true
    else
        return 1
    fi

    converted_cronjob=$(echo ${c})
# say ${chan} "c ==============> ${c}"
}


# This subroutine parses a message for a reminder scheduling information, and adds a cronjob.

function cronjobSubroutine {
    payload=${1}                                                  # Entire message (e.g. on saturday to do something, tomorrow to do the thing).
# say ${chan} "MAIN PAYLOAD =====> ${payload}"
    if [[ $(echo ${payload,,} | sed -r 's|^(tomorrow).*|\1|') == "tomorrow" ]] || [[ $(echo ${payload,,} | sed -r 's|^(tmrw).*|\1|') == "tmrw" ]] ; then
# say ${chan} "entering cronjobSubroutine A (testing phase)"
        payload=$(echo ${payload} | cut -d ' ' -f2-)                    # Cut 'tomorrow' or 'tmrw' from ${payload}
        at=$(echo ${payload} | sed -r 's|(.*)(at [0-9][0-9apm:]*)(.*)|\2|')
# say ${chan} "at ==> ${at}"
# say ${chan} "payload ==> ${payload}"
        if [ "${at}" == "${payload}" ] ; then           # Case: 'at 300' doesn't exist
# say ${chan} "AA"
            at='9:00am'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
# say ${chan} "${h}${m}"
        else
# say ${chan} "AB"
            at=$(echo ${at} | sed -r 's|^at ||')
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
# say ${chan} "${h}${m}"
        fi

        day_of_month=$(date --date="tomorrow" +%d)
        month=$(date --date="tomorrow" +%m)
        day_of_week=$(date --date="tomorrow" +%w)
        cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")

        uuid=$(uuidgen)
        (crontab -l ; echo "${cronjob} echo \"${uuid}: $(date), ${chan}, ${nick}, ${task}\" >> /home/dkim/sandbox/_reminderbot/tasks/tmp") | crontab -       # Create a new cronjob entry.  (NOTE: when a cronjob is executed, ../tmp will be created.  Then, __reminderbot will send contents of tmp to _reminderbot, and remove tmp.)
# say ${chan} "complete cronjob: $(echo "${cronjob} echo ${uuid}: $(date), ${chan}, ${task}")"
        convertCronjobSubroutine "${cronjob}"
        say ${chan} "${nick}: You will be reminded @ ${converted_cronjob}"

    elif [ ! $(echo ${payload} | sed -r 's|^(in ([0-9]+[dhm]{1})+).*|\1|') == "${payload}" ] ; then                       # in 1d2h3m do something ==> in 1d2h3m
# say ${chan} "entering cronjobSubroutine B (testing phase)"
# say ${chan} "payload ==> ${payload}"
        times_array=$(echo ${payload} | sed -r 's|^in ([0-9]+.*(d\|h\|m)) .*|\1|')                                 # 3d2h1m
# say ${chan} "times_array ==> ${times_array}"
        times_array=$(echo ${times_array} | sed -r 's|d|d |g' | sed -r 's|h|h |g' | sed -r 's|m|m |g')      # 3d 2h 1m
# say ${chan} "times_array ==> ${times_array}"
        
        ARRAY=()
        while [[ -n "${times_array}" ]] ; do                                                 # Append each time to an array.
            ARRAY+=($(echo ${times_array} | sed -r 's| .*||'))
            times_array=$(echo ${times_array} | cut -d " "  -f2-)
        done

#         say ${chan} "array len ==> ${#ARRAY[@]}"                  # DEBUG: display array len, content
#         say ${chan} "array content ==> ${ARRAY[@]}"
#         for i in "${ARRAY[@]}" ; do
#             say ${chan} "${i}"
#         done

        for i in "${ARRAY[@]}" ; do                                 # Populate days, hours, minutes variables.
# say ${chan} "i ==> ${i}"
            if [[ "${i}" == *h* ]] ; then
# say ${chan} "ADDING TO HOURS"
                hours=$(echo ${i} | sed -r 's|h||')
            elif [[ "${i}" == *m* ]] ; then
# say ${chan} "ADDING TO MINUTES"
                minutes=$(echo ${i} | sed -r 's|m||')
            elif [[ "${i}" == *d* ]] ; then
# say ${chan} "ADDING TO DAYS"
                days=$(echo ${i} | sed -r 's|d||')
            else
                break
                return 1
            fi
        done

        task=$(echo ${payload} | sed -r 's|^in ([0-9]+.*(d\|h\|m)) (.*)|\3|' | sed 's|^[ ]*||' | sed 's|[ ]*$||')
# say ${chan} "days, hours, minutes ==> ${days} ${hours} ${minutes}"
# say ${chan} "task ==> ${task}"

        if [ ! ${days} ] && [ ! ${hours} ] && [ ! ${minutes} ] ; then                                     # If d,h,m are missing, return immediately.
            if [ $(echo ${days}${hours}${minutes} | sed 's/[ 0-9dhm]*//') ] ; then return 1 ; fi
        fi

        if [ -z "${days}" ] ; then days='0d' ; fi                               # Populate remaining empty variables with default values.
        if [ -z "${hours}" ] ; then hours='0h' ; fi
        if [ -z "${minutes}" ] ; then minutes='0m' ; fi

        ce_time=$(date +%s)                                                     # current epoch time
# say ${chan} "ce_time ==> ${ce_time}"
# say ${chan} "${days} ${hours} ${minutes}"
        days=$(echo ${days} | sed -r 's/d//')
        hours=$(echo ${hours} | sed -r 's/h//')
        minutes=$(echo ${minutes} | sed -r 's/m//')

        if [ "${days}" -gt 365 ] || [ "${hours}" -gt 100 ] || [ "${minutes}" -gt 1440 ] ; then
            say ${chan} "specified time is out-of-bounds"
            return 1
        fi

        e_time=$(( ${days}*24*60*60 + ${hours}*60*60 + ${minutes}*60 + ${ce_time} ))         # convert #d#h#m ==> epoch time
# (d * 24 * 60 * 60) + (h * 60 * 60) + (m * 60)

        s_time=$(date -d @${e_time} +%M%H%d%m)                                            # convert epoch time ==> standard time
        min=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\1/')
        hour=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\2/')
        day=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\3/')
        month=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\4/')
        uuid=$(uuidgen)
        (crontab -l ; echo "${min} ${hour} ${day} ${month} * echo \"${uuid}: $(date), ${chan}, ${nick}, ${task}\" >> /home/dkim/sandbox/_reminderbot/tasks/tmp") | crontab -       # Create a new cronjob entry.
# say ${chan} "complete cronjob: $(echo "${cronjob} echo ${uuid}: $(date), ${chan}, ${task}")"
        say ${chan} "${nick}: You will be reminded @ $(date -d @${e_time})"
    elif [ ! $(echo ${payload} | sed -r 's|^(in .*(hour[s]?\|hr[s]?\|minute[s]?\|min[s]?\|day[s]?)).*|\1|') == "${payload}" ] ; then                      #  in 1 hour do something ==> in 1 hour
# say ${chan} "entering cronjobSubroutine C (testing phase)"
        times_array=$(echo ${payload} | sed -r 's|^in (.*(hour[s]?\|hr[s]?\|minute[s]?\|min[s]?\|day[s]?)).*|\1|')                  # 1 hour 4 days 12 minutes
        task=$(echo ${payload} | sed -r 's|^in (.*(hour[s]?\|hr[s]?\|minute[s]?\|min[s]?\|day[s]?))*(.*)|\3|' | sed -r 's|^[ ]*||' | sed -r 's|[ ]*$||')
# say ${chan} "times_array: ${times_array}"
# say ${chan} "task: ${task}"
        ARRAY=()
        while [[ -n "${times_array}" ]] ; do                                                 # Append each time to an array.
            ARRAY+=($(echo ${times_array} | sed -r 's|^([0-9]*) ([a-zA-Z]*) .*|\1 \2|'))
            times_array=$(echo ${times_array} | cut -d " "  -f3-)
        done

# say ${chan} "array len ==> ${#ARRAY[@]}"                  # DEBUG: display array len, content
# say ${chan} "array content ==> ${ARRAY[@]}"
# for i in "${ARRAY[@]}" ; do
#     say ${chan} "${i}"
# done

        for i in "${ARRAY[@]}" ; do                                 # Populate days, hours, minutes variables.
# say ${chan} "i ==> ${i}"
            if [[ "${i}" == *hour* ]] || [[ "${i}" == *hr* ]] ; then
# say ${chan} "ADDING TO HOURS"
                hours=$(echo ${i} | sed -r 's| .*||')
            elif [[ "${i}" == *minute* ]] || [[ "${i}" == *min* ]] ; then
# say ${chan} "ADDING TO MINUTES"
                minutes=$(echo ${i} | sed -r 's| .*||')
            elif [[ "${i}" == *day* ]] ; then
# say ${chan} "ADDING TO DAYS"
                days=$(echo ${i} | sed -r 's| .*||')
            else
                break
                return 1
            fi
        done

        if [ ! ${days} ] && [ ! ${hours} ] && [ ! ${minutes} ] ; then                                     # If d,h,m are missing, return immediately.
            if [ $(echo ${days}${hours}${minutes} | sed 's/[ 0-9dhm]*//') ] ; then return 1 ; fi
        fi

        if [ -z "${days}" ] ; then days='0' ; fi                   # Populate remaining empty variables with default values.
        if [ -z "${hours}" ] ; then hours='0' ; fi
        if [ -z "${minutes}" ] ; then minutes='0' ; fi

# say ${chan} "days =====> ${days}"
# say ${chan} "hours ====> ${hours}"
# say ${chan} "minutes ==> ${minutes}"

        ce_time=$(date +%s)                                                                   # current epoch time
        e_time=$(( ${days}*24*60*60 + ${hours}*60*60 + ${minutes}*60 + ${ce_time} ))          # convert #d#h#m ==> epoch time
# (d * 24 * 60 * 60) + (h * 60 * 60) + (m * 60)

        s_time=$(date -d @${e_time} +%M%H%d%m)                                            # convert epoch time ==> standard time
        min=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\1/')
        hour=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\2/')
        day=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\3/')
        month=$(echo ${s_time} | sed -r 's/([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})/\4/')
        uuid=$(uuidgen)
        (crontab -l ; echo "${min} ${hour} ${day} ${month} * echo \"${uuid}: $(date), ${chan}, ${nick}, ${task}\" >> /home/dkim/sandbox/_reminderbot/tasks/tmp") | crontab -       # Create a new cronjob entry.
# say ${chan} "complete cronjob: $(echo "${cronjob} echo ${uuid}: $(date), ${chan}, ${task}")"
        say ${chan} "${nick}: You will be reminded @ $(date -d @${e_time})"
    else                                                                                # on sun at 300, next monday at 3:00pm, this sunday
# say ${chan} "entering cronjobSubroutine D (testing phase)"
        parseSubroutine "${payload}"
        if [ "$(echo $?)" == "1" ] ; then
            # say ${chan} "parseSubroutine failed"
            return 1
        fi                                  # If parseSubroutine fails, return immediately.

        uuid=$(uuidgen)
        (crontab -l ; echo "${cronjob} echo \"${uuid}: $(date), ${chan}, ${nick}, ${task}\" >> /home/dkim/sandbox/_reminderbot/tasks/tmp") | crontab -       # Create a new cronjob entry.
# say ${chan} "complete cronjob: $(echo "${cronjob} echo ${uuid}: $(date), ${chan}, ${task}")"
        convertCronjobSubroutine "${cronjob}"
        say ${chan} "${nick}: You will be reminded @ ${converted_cronjob}"
    fi
}

# This subroutine displays documentation for _reminderbot's functionalities.

function helpSubroutine {
    say ${chan} "${nick}: I will remind you of stuff!  DISCLAIMER: I am not liable for your forgetfulness."
    say ${chan} 'usage: "remind me in #d#h#m ..." such as 3d4h6m for 3 days, 4 hours, 6 minutes'
    say ${chan} '       "remind me in 5 days 4 hours 3 minutes ..." | "remind me in 2 hrs 3 mins ..."'
    say ${chan} '       "remind me on sun at 1700 ..." | "remind me at 3:00pm on 8/8/18 ..."'
    say ${chan} '       "remind me at 23:59 on 9-9-18 ..." | "remind me on 3/13/18 at 13:13 ..."'
    say ${chan} '       "remind me tomorrow ..." | "remind me tmrw at 3:13pm ..."'
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
    str1='running! '
    str2=$(ps aux | grep ./_reminderbot | head -n 1 | awk '{ print "[%CPU "$3"]", "[%MEM "$4"]", "[VSZ "$5"]", "[TIME "$10"]" }')
    str="${str1}${str2}"
    say ${chan} "${str}"

# Source.

elif has "${msg}" "^_reminderbot: source$" ; then
    say ${chan} "Try -> https://github.com/kimdj/_reminderbot -OR- /u/dkim/_reminderbot"

# Add a cronjob.

elif has "${msg}" "^remind me " ; then
    cronjob_len=$(crontab -l | sed 's/^ *//;/^[*@0-9]/!d' | wc -l)
    if [ ${cronjob_len} -gt ${MAX_REM} ] ; then                                             # Max reminders ==> 500
        say ${chan} "YAY!!! You have officially reached the self-imposed maximum number of reminders (i.e. 500)."
        say ${chan} "NO SOUP FOR YOU! COME BACK ONE YEAR! NEXT!"
    fi

    payload=$(echo ${msg} | sed -r 's/^remind me //')
    payload=$(echo ${payload} | sed -r 's|[^ a-zA-Z0-9]||g' | sed 's/>//g' | sed 's/<//g')            # Sanitize user input (i.e. remove non-alphanumeric characters).
# say ${chan} "sanitized msg: ${payload}"
    cronjobSubroutine "${payload}"
    if [ "$(echo $?)" == "1" ] ; then
        say ${chan} "Sorry, I couldn't setup your reminder."
    fi

# Handle incoming msg from self (_reminderbot => _reminderbot).

elif has "${msg}" "^!signal " && [[ ${nick} = "__reminderbot" ]] || [[ ${nick} = "_reminderbot" ]]; then
    payload=$(echo ${msg} | sed -r 's|!signal (.*)|\1|')
    task=$(echo ${payload} | sed -r 's|~.*||' | sed -r 's|[ ]*$||')
    time_sched=$(echo ${payload} | sed -r 's|.*~(.*)~.*~.*|\1|' | sed -r 's|^[ ]*||' | sed -r 's|[ \)]*$||')
    chan=$(echo ${payload} | sed -r 's|^(.*) ~ (.*) ~ (.*)|\2|')
    nick=$(echo ${payload} | sed -r 's|^(.*) ~ (.*) ~ (.*) ~ (.*)|\4|')

    time_sched=$(date --date="${time_sched}" +"%a, %b %d %I:%M%P" | sed -r 's|(.*)0([0-9]{1})(.*)|\1\2\3|')
    say ${chan} "${nick}: On ${time_sched}, you asked me to remind you ${task}."

# Have _reminderbot send an IRC command to the IRC server.

elif has "${msg}" "^_reminderbot: injectcmd " && [[ "${AUTHORIZED}" == *"${nick}"* ]] ; then
    cmd=$(echo ${msg} | sed -r 's/^_reminderbot: injectcmd //')
    send "${cmd}"

# Have _reminderbot send a message.

elif has "${msg}" "^_reminderbot: sendcmd " && [[ "${AUTHORIZED}" == *"${nick}"* ]] ; then
    buffer=$(echo ${msg} | sed -re 's/^_reminderbot: sendcmd //')
    dest=$(echo ${buffer} | sed -e "s| .*||")
    message=$(echo ${buffer} | cut -d " " -f2-)
    say ${dest} "${message}"

fi

#################################################  Commands End  ##################################################

#!/bin/bash



# This subroutine checks whether the time input is in the correct format.

function checkFormatSubroutine {
    payload=${1}

    if [ -z $(echo ${payload} | sed -r 's|[0-9]?[0-9]{1}:[0-9]{2}[a|p]m||' | sed -r 's|[0-9]?[0-9]{1}:?[0-9]{2}||' | sed -r 's|[0-9]?[0-9]{1}[a|p]m||') ] ; then
        %echo 'time format OK'
        return 0
    else
        %echo 'time format FAIL'
        return 1
    fi
}

# This subroutine parses a time input value and sets variables accordingly (e.g. ${h}, ${m}).

function timeSubroutine {
say ${chan} "==> entering timeSubroutine"
say ${chan} "==> payload: ${1}"
    payload=${1}                                                                    # 12:00am  12:00pm  0000  2400  00:00  24:00  3pm
    checkFormatSubroutine "${payload}"
    if [[ $? -eq 1 ]] ; then return 1 ; fi                                          # If format is incorrect, immediately return.

    h=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}).*|\1|')                        # Strip the hours, minutes, and am/pm.
    m=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}):?([0-9]{2}).*|\2|')
    if [[ "${m}" == "${payload}" ]] ; then m='00' ; fi                              # Case: 3pm ==> 00 min default
    am_pm=$(echo ${payload} | sed -r 's|.*([a|p]m).*|\1|')
    if [[ "${am_pm}" == "${payload}" ]] ; then am_pm='am' ; fi                      # Case: 3:00 ==> am default

    if [ "${h}" -gt "23" ] && [ "${m}" -gt "0" ] ; then                             # Case: 2401 and greater
        %echo 'time is out-of-bounds'
        return 1
    fi

    if [ "${m}" -gt "59" ] ; then                                                   # Case: 12:60 and greater
        return 1
    fi

    if [ "${am_pm}" == "pm" ] ; then                                                # Standardize to military time.
        h=$(expr ${h} + 12)
    elif [ "${h}" == "12" ] && [ "${am_pm}" == "am" ] ; then
        h='00'
    fi
    say ${chan} "==> ${h}${m}"
}

# This subroutine parses a date input value and sets variables accordingly (e.g. ${day_of_month}, ${month}, ${day_of_week}).

function daySubroutine {
say ${chan} "==> entering daySubroutine"
say ${chan} "==> daySubroutine payload: ${1}"
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

        say ${chan} "==> =========================> ${month_t}"
        say ${chan} "==> =========================> ${day_t}"
        say ${chan} "==> =========================> ${year_t}"

        if [ "${day_t}" -gt "$(date -d "${month_t}/1 + 1 month - 1 day" "+%d")" ] ; then        # If day is out-of-bounds, immediately return.
            return 1                                                                            # (i.e. specified day exceeds the last day of a given month)
        fi

        if [ "${month_t}" -gt "12" ] ; then      # If month is out-of-bounds, immediately return.
            return 1
        fi

        if [ "${year_t}" -lt "18" ] ; then      # If year is out-of-bounds, immediately return.
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
    say ${chan} "==> payload: ${payload}"

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

    # echo "  task: ${task}"
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
            %echo '11111'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
            say ${chan} "==> cronjob: ${cronjob}"
        else                                                        # Case: on monday
            %echo '22222'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
            say ${chan} "==> cronjob: ${cronjob}"
        fi
    elif [ -n "${this_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: this tuesday at 4:00am
            %echo '33333'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
            say ${chan} "==> cronjob: ${cronjob}"
        else                                                        # Case: this wednesday
            %echo '44444'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
            say ${chan} "==> cronjob: ${cronjob}"
        fi
    elif [ -n "${next_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: next thursday at 5:00pm
            %echo '55555'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
            say ${chan} "==> cronjob: ${cronjob}"
        else                                                        # Case: next friday
            %echo '66666'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week}")
            say ${chan} "==> cronjob: ${cronjob}"
        fi
    elif [ -n "${at}" ] ; then                                      # Case: at 10:00am
        %echo '77777'
        timeSubroutine "${at}"

        current_time=$(date +%H%M)
        if [ "${h}${m}" -lt "${current_time}" ] ; then
            day=$(date -d '+1 day' +%d)
        else
            day=$(date +%d)
        fi
        month=$(date +%m)

        cronjob=$(echo "${m} ${h} ${day} ${month} *")
        say ${chan} "==> cronjob: ${cronjob}"
    else                                                            # missing values
        %echo 'missing values'
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
        # send error msg
        return 1
    fi

    say ${chan} "==> END REACHED; SUCCESS!"
}



while read line ; do
    echo "line ==> ${line}"
    parseSubroutine "${line}"
    echo " "
    echo " "
    # sleep 2
done < msgs

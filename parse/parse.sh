#!/bin/bash



# This subroutine checks whether the time input is in the correct format.

function checkFormatSubroutine {
    payload=${1}

    if [ -z $(echo ${payload} | sed -r 's|[0-9]?[0-9]{1}:[0-9]{2}[a|p]m||' | sed -r 's|[0-9]?[0-9]{1}:?[0-9]{2}||' | sed -r 's|[0-9]?[0-9]{1}[a|p]m||') ] ; then
        echo 'time format OK'
        return 0
    else
        echo 'time format FAIL'
        return 1
    fi
}

# This subroutine parses a time input value and sets variables accordingly (e.g. ${h}, ${m}).

function timeSubroutine {
    echo "entering timeSubroutine"
echo "payload: ${1}"
    payload=${1}                                                                    # 12:00am  12:00pm  0000  2400  00:00  24:00  3pm
    checkFormatSubroutine "${payload}"
    if [[ $? -eq 1 ]] ; then return 1 ; fi                                          # If format is incorrect, immediately return.

    h=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}).*|\1|')                        # Strip the hours, minutes, and am/pm.
    m=$(echo ${payload} | sed -r 's|([0-9]?[0-9]{1}):?([0-9]{2}).*|\2|')
    if [[ "${m}" == "${payload}" ]] ; then m='00' ; fi                              # Case: 3pm ==> 00 min default
    am_pm=$(echo ${payload} | sed -r 's|.*([a|p]m).*|\1|')
    if [[ "${am_pm}" == "${payload}" ]] ; then am_pm='am' ; fi                      # Case: 3:00 ==> am default

    if [ "${h}" -gt "23" ] && [ "${m}" -gt "0" ] ; then
        echo 'time is out-of-bounds'
        return 1
    fi

    if [ "${am_pm}" == "pm" ] ; then                                                # Standardize to military time.
        h=$(expr ${h} + 12)
    elif [ "${h}" == "12" ] && [ "${am_pm}" == "am" ] ; then
        h='00'
    fi
    echo "${h}${m}"
}

# This subroutine parses a date input value and sets variables accordingly (e.g. ${day_of_month}, ${month}, ${day_of_week}).

function daySubroutine {
echo "entering daySubroutine"
echo "daySubroutine payload: ${1}"
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

        echo "=========================> ${month_t}"
        echo "=========================> ${day_t}"
        echo "=========================> ${year_t}"

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

    # echo "  task: ${task}"
    # echo "    at: ${at}"
    # echo "  on_d: ${on_d}"
    # echo "this_d: ${this_d}"
    # echo "next_d: ${next_d}"
    # echo " "

    at=$(echo ${at} | sed -r 's|.*at [^0-9]*(.*)|\1|')
    on_d=$(echo ${on_d} | sed -r 's|.*on (.*)|\1|')
    this_d=$(echo ${this_d} | sed -r 's|.*this (.*)|\1|')
    next_d=$(echo ${next_d} | sed -r 's|.*next (.*)|\1|')

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
            echo '11111'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            echo "cronjob: ${cronjob}"
        else                                                        # Case: on monday
            echo '22222'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${on_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            echo "cronjob: ${cronjob}"
        fi
    elif [ -n "${this_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: this tuesday at 4:00am
            echo '33333'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            echo "cronjob: ${cronjob}"
        else                                                        # Case: this wednesday
            echo '44444'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${this_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            echo "cronjob: ${cronjob}"
        fi
    elif [ -n "${next_d}" ] ; then
        if [ -n "${at}" ] ; then                                    # Case: next thursday at 5:00pm
            echo '55555'
            timeSubroutine "${at}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            echo "cronjob: ${cronjob}"
        else                                                        # Case: next friday
            echo '66666'
            timeSubroutine "9:00am"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
            daySubroutine "${next_d}"
            if [ "$(echo $?)" == "1" ] ; then return 1 ; fi

            cronjob=$(echo "${m} ${h} ${day_of_month} ${month} ${day_of_week} ")
            echo "cronjob: ${cronjob}"
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
        echo "cronjob: ${cronjob}"
    else                                                            # missing values
        echo 'missing values'
        if [ "$(echo $?)" == "1" ] ; then return 1 ; fi
        # send error msg
        return 1
    fi

    echo "END REACHED; SUCCESS!"
}



while read line ; do
    echo "line ==> ${line}"
    parseSubroutine "${line}"
    echo " "
    echo " "
    # sleep 2
done < msgs

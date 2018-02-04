#!/bin/bash
# _reminderbot ~ main
# Copyright (c) 2017 David Kim
# This program is licensed under the "MIT License".
# Date of inception: 1/15/17

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
        echo "***** Trapped CTRL-C *****"
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"     # Path to _reminderbot.

LOG_FILE_1=${DIR}/log.stdout        # Redirect file descriptors 1 and 2 to log.out
LOG_FILE_2=${DIR}/log.stderr
exec > >(tee -a ${LOG_FILE_1} )
PID_LOG_STDOUT=$(echo $!)
exec 2> >(tee -a ${LOG_FILE_2} >&2)
PID_LOG_STDERR=$(echo $!)

BOT_NICK="_reminderbot"
KEY="$(cat ./config.txt)"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

nanos=1000000000
interval=$(( ${nanos} * 50 / 100 ))
declare -i prevdate
prevdate=0

function send {
    while read -r line; do
        newdate="$(date +%s%N)"
        if [ ${prevdate} -gt ${newdate} ] ; then
            sleep $(bc -l <<< "(${prevdate} - ${newdate}) / ${nanos}")
            newdate="$(date +%s%N)"
        fi
        prevdate=${newdate}+${interval}
        echo "-> ${1}"
        echo "${line}" >> ${BOT_NICK}.io
    done <<< "$1"
}

# This subroutine checks for a file called tmp in ../tasks/ and sends the content as a signal msg to _reminderbot.

function signalSubroutine {
    if [ -e tasks/tmp ] ; then                  # If tasks/tmp exists, send file contents !signal handler.  Then, remove tasks/tmp.
        while read line; do
            s_uuid=$(echo ${line} | sed -r 's/^(.*): .*/\1/')
            s_time_sched=$(echo ${line} | sed -r 's/^.*: ([ a-zA-Z0-9:]*), .*/\1/')
            s_chan=$(echo ${line} | sed -r 's/^.*: ([ a-zA-Z0-9:]*), ([^,]*), .*/\2/')
            s_nick=$(echo ${line} | sed -r 's/^.*: ([ a-zA-Z0-9:]*), ([^,]*), (.*), .*/\3/')
            s_task=$(echo ${line} | sed -r 's/^.*: ([ a-zA-Z0-9:]*), ([^,]*), (.*), (.*.)/\4/')

            echo "==> tmp file detected; processing reminder ..."
            echo "line ===============> ${s_line}"
            echo "uuid ===============> ${s_uuid}"
            echo "time_sched =========> ${s_time_sched}"
            echo "task ===============> ${s_task}"
            echo "nick ===============> ${s_nick}"
            echo "chan ===============> ${s_chan}"

            payload="!signal ${s_task} ~ ${s_time_sched}) ~ ${s_chan} ~ ${s_nick}"

            send "PRIVMSG _reminderbot :${payload}"
            crontab -l | grep -v "${s_uuid}" | crontab -              # Remove the cronjob by grep-ing out the specified cronjob uuid.
        done < tasks/tmp

        rm tasks/tmp
    fi
}

# This subroutine checks for a file called cmd in ../commands/ and executes it's content.

function cmdSubroutine {
    if [ -e commands/cmd ] ; then                       # if a cmd file exists, run the cmd
        while read line ; do
            send "${line}"
        done < commands/cmd
        rm commands/cmd
    fi
}

cp commands/join-cmd commands/cmd                       # Join channels.

rm ${BOT_NICK}.io
mkfifo ${BOT_NICK}.io

tail -f ${BOT_NICK}.io | openssl s_client -connect irc.cat.pdx.edu:6697 | while true ; do

    # If log.out is empty, reset logging.  (cron job empties log.out after backup)
    LOG_FILE_1=${DIR}/log.stdout
    LOG_FILE_2=${DIR}/log.stderr
    if [ ! -s ${LOG_FILE_1} ] && [ ! -s ${LOG_FILE_2} ] ; then
        if [ -z "$(ps --no-header ${PID_LOG_STDOUT})" ] ; then kill "${PID_LOG_STDOUT}" ; fi
        if [ -z "$(ps --no-header ${PID_LOG_STDERR})" ] ; then kill "${PID_LOG_STDERR}" ; fi
        exec > >(tee -a ${LOG_FILE_1} )
        PID_LOG_STDOUT=$(echo $!)
        exec 2> >(tee -a ${LOG_FILE_2} >&2)
        PID_LOG_STDERR=$(echo $!)
    fi

    if [[ -z ${started} ]] ; then
        send "NICK ${BOT_NICK}"
        send "USER 0 0 0 :${BOT_NICK}"
        started="yes"
    fi

    # If there's an incoming msg, assign it to ${irc} and break out of the loop.
    # Otherwise, cronjob(s) are run and append reminders to a file called tmp:
    #
    # 00 13 22 01 * echo "d4da751e-446f-4f29-9248-1ca5f177f4a1: Sun Jan 21 16:38:02 PST 2018, #bingobobby, _sharp, do something"
    # 00 12 22 01 * echo "de64569f-8027-4330-b5dc-6bbb636d0ba0: Sun Jan 21 16:39:03 PST 2018, #bots, _sharp, do something fun"
    # 30 21 30 01 * echo "00e44e16-d33e-4448-b2ff-40f9dbebe82d: Sun Jan 21 19:34:28 PST 2018, _sharp, _sharp, to eat cereal"
    #
    # signalSubroutine will check for the existence of the tmp file.
    # If it exists, then for each line, send a signal msg containing a reminder
    # to _reminderbot and _reminderbot has a handler that essentially forwards
    # the contents of the signal msg to the appropriate channel.
    # 
    # Finally, check to see if cmd file exists.  If so, execute the cmds.

    while [ -z "${irc}" ] ; do                                  # While loop is used to enable non-blocking I/O (read).
        read -r -t 0.5 irc                                      # Time out and return failure if a complete line of input is not read within TIMEOUT seconds.
        if [ "$(echo $?)" == "1" ] ; then irc='' ; fi

        signalSubroutine
        cmdSubroutine
    done

    # echo "==> ${irc}" >> irc-output.log                     # Re-direct incoming internal irc msgs to file.
    echo "==> ${irc}"
    if $(echo "${irc}" | cut -d ' ' -f 1 | grep -P "PING" > /dev/null) ; then
        send "PONG"
    elif $(echo "${irc}" | cut -d ' ' -f 1 | grep -P "ING" > /dev/null) ; then                          # NOTICE: very, very crude way of mitigating PING/PONG faulty handshake error.
        send "PONG"                                                                                     #         i.e. _reminderbot will randomly receive an unexpected 'ING' instead of
    elif $(echo "${irc}" | cut -d ' ' -f 2 | grep -P "PRIVMSG" > /dev/null) ; then                      #              the expected 'PING', and as a result it will not send back the
#:nick!user@host.cat.pdx.edu PRIVMSG #bots :This is what an IRC protocol PRIVMSG looks like!            #              expected 'PONG' msg.
        nick="$(echo "${irc}" | cut -d ':' -f 2- | cut -d '!' -f 1)"
        chan="$(echo "${irc}" | cut -d ' ' -f 3)"
        if [ "${chan}" = "${BOT_NICK}" ] ; then chan="${nick}" ; fi 
        msg="$(echo "${irc}" | cut -d ' ' -f 4- | cut -c 2- | tr -d "\r\n")"
        echo "$(date) | ${chan} <${nick}>: ${msg}"
        var="$(echo "${nick}" "${chan}" "${msg}" | ./commands.sh)"
        if [[ ! -z ${var} ]] ; then
            send "${var}"
        fi
    fi

    irc=''                                              # Reset ${irc}.
done

#!/bin/bash
# _reminderbot ~ main
# Copyright (c) 2017 David Kim
# This program is licensed under the "MIT License".
# Date of inception: 1/14/17



# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
        echo "***** Trapped CTRL-C *****"
}

# LOG_FILE_1=/home/dkim/sandbox/_reminderbot/log.stdout        # Redirect file descriptors 1 and 2 to log.out
# LOG_FILE_2=/home/dkim/sandbox/_reminderbot/log.stderr
# exec > >(tee -a ${LOG_FILE_1} )
# exec 2> >(tee -a ${LOG_FILE_2} >&2)

BOT_NICK="_reminderbot"
KEY="$(cat ./config.txt)"

nanos=1000000000
interval=$(( $nanos * 50 / 100 ))
declare -i prevdate
prevdate=0

function send {
    while read -r line; do
        newdate=`date +%s%N`
        if [ $prevdate -gt $newdate ] ; then
            sleep `bc -l <<< "($prevdate - $newdate) / $nanos"`
            newdate=`date +%s%N`
        fi
        prevdate=$newdate+$interval
        echo "-> $1"
        echo "$line" >> ${BOT_NICK}.io
    done <<< "$1"
}

function signalSubroutine {
    if [ -e tasks/tmp ] ; then                  # If tasks/tmp exists, send file contents !signal handler.  Then, remove tasks/tmp.
        while read line; do
            uuid=$(echo ${line} | sed -r 's/^(.*): .*/\1/')
            time_sched=$(echo ${line} | sed -r 's/^.*: ([ a-zA-Z0-9:]*), .*/\1/')
            chan=$(echo ${line} | sed -r 's/^.*: ([ a-zA-Z0-9:]*), ([^,]*), .*/\2/')
            nick=$(echo ${line} | sed -r 's/^.*: ([ a-zA-Z0-9:]*), ([^,]*), (.*), .*/\3/')
            task=$(echo ${line} | sed -r 's/^.*: ([ a-zA-Z0-9:]*), ([^,]*), (.*), (.*.)/\4/')
            echo "line ========> ${line}"
            echo "uuid ===============> ${uuid}"
            echo "time_sched =========> ${time_sched}"
            echo "task ===============> ${task}"
            echo "nick ===============> ${nick}"
            echo "chan ===============> ${chan}"
            # send "PRIVMSG ${chan} :line ==> ${line}"
            send "PRIVMSG _reminderbot :!signal ${task} ~ ${time_sched}) ~ ${chan} ~ ${nick}"
            crontab -l | grep -v "${uuid}" | crontab -              # Remove the cronjob by grep-ing out the specified cronjob uuid.
        done < tasks/tmp

        rm tasks/tmp
    fi
}

function cmdSubroutine {
    if [ -e commands/cmd ] ; then                   # if a cmd file exists, run the cmd
        while read line ; do
            send "$line"
        done < commands/cmd
        rm commands/cmd
    fi
}

cp commands/join-cmd commands/cmd                   # Join channels.

rm ${BOT_NICK}.io
mkfifo ${BOT_NICK}.io

tail -f ${BOT_NICK}.io | openssl s_client -connect irc.cat.pdx.edu:6697 | while true ; do

    # # If log.out is empty, reset logging.  (cron job empties log.out after backup)
    # LOG_FILE_1=/u/dkim/sandbox/_reminderbot/log.stdout
    # LOG_FILE_2=/u/dkim/sandbox/_reminderbot/log.stderr
    # if [ ! -s ${LOG_FILE_1} ] && [ ! -s ${LOG_FILE_2} ] ; then
    #     exec > >(tee -a ${LOG_FILE_1} )
    #     exec 2> >(tee -a ${LOG_FILE_2} >&2)
    # fi

    if [[ -z $started ]] ; then
        send "NICK $BOT_NICK"
        send "USER 0 0 0 :$BOT_NICK"
        started="yes"
    fi

    while [ -z "${irc}" ] ; do                      # While loop is used to enable non-blocking I/O (read).
        read -t 0.5 irc                             # Time out and return failure if a complete line of input is not read within TIMEOUT seconds.
        if [ $(echo $?) == 1 ] ; then irc='' ; fi

        signalSubroutine
        cmdSubroutine
    done

    echo "==> $irc" >> irc-output.log               # Re-direct incoming internal irc msgs to file.
    echo "==> $irc"
    if $(echo "$irc" | cut -d ' ' -f 1 | grep -P "PING" > /dev/null) ; then
        send "PONG"
    elif $(echo "$irc" | cut -d ' ' -f 2 | grep -P "PRIVMSG" > /dev/null) ; then 
#:nick!user@host.cat.pdx.edu PRIVMSG #bots :This is what an IRC protocol PRIVMSG looks like!
        nick="$(echo "$irc" | cut -d ':' -f 2- | cut -d '!' -f 1)"
        chan="$(echo "$irc" | cut -d ' ' -f 3)"
        if [ "$chan" = "$BOT_NICK" ] ; then chan="$nick" ; fi 
        msg="$(echo "$irc" | cut -d ' ' -f 4- | cut -c 2- | tr -d "\r\n")"
        echo "$(date) | $chan <$nick>: $msg"
        var="$(echo "$nick" "$chan" "$msg" | ./commands.sh)"
        if [[ ! -z $var ]] ; then
            send "$var"
        fi
    fi

    irc=''                                          # Reset ${irc}.
done

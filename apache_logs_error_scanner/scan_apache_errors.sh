#!/bin/bash

####################
# Configurations   #
####################
threshold=100
hours_ago=1
emails="wangyaofeng@gmail.com,kanazawahideyuki@gmail.com"
tmp_error_log="/tmp/`date '+%Y%m%d_%H%M%S'`_apache_errors.log"


###################
# Main            #
###################
main() {
        # If incorrect no. of arguments passed, exit
        if [ "$#" -ne 1 ]; then
                echo "[INFO] Usage: `basename "$0"` <APACHE_LOG_FILE>" && exit 22
        fi

        logfile=`realpath $1`

        # If logfile doesn't exist, exit
        if [ ! -f ${logfile} ]; then
                echo "[ERROR] File not found!" && exit 23
        fi

        # Obtain error logs from apache logs, no. of 4xx errors and no. of 5xx errors
        date_match=$(date -d "`echo $hours_ago` hours ago" '+%d/%b/%Y:%H')
        error_logs=$(grep ${date_match} ${logfile} | awk '{ if ( $9 ~ /^[45][0-9]{2}$/ ) print $0;}' )
        error_count=$(echo "${error_logs}" | wc -l )
        errors_4xx=$(echo "${error_logs}" | awk '{ if ( $9 ~ /^[4][0-9]{2}$/ ) print $0;}' | wc -l )
        errors_5xx=$(echo "${error_logs}" | awk '{ if ( $9 ~ /^[5][0-9]{2}$/ ) print $0;}' | wc -l )

        # Send email if threshold is breached
        if [[ "${error_count}" -ge ${threshold} ]]; then
                echo ${error_logs} > ${tmp_error_log}
                send_mail
                rm ${tmp_error_log}
        fi
}


###############################
# Function for sending mail   #
###############################
send_mail () {
        start_dt=$(date -d "`echo ${hours_ago}` hours ago" '+%d %b %Y %H:00:00')
        end_dt=$(date '+%d %b %Y %H:00:00')
        subject="[Alert] Error response threshold breached for Apache logs"
        content=$(cat ./apache_error_mail_template | sed "s|(THRESHOLD)|${threshold}|" | sed "s|(APACHE_LOG_FILE)|${logfile}|" | sed "s|(START_TIME)|${start_dt}|" | sed "s|(END_TIME)|${end_dt}|" | sed "s|(4xx_ERROR_COUNT)|${errors_4xx}|" | sed "s|(5xx_ERROR_COUNT)|${errors_5xx}|" | sed "s|(ERROR_COUNT)|${error_count}|")
        echo "${content}" | mail -A "${tmp_error_log}" -s ${subject} ${emails}
}


main "$@"; exit
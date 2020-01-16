#!/bin/bash
# /etc/cron.hourly/unban - runs on schedule in droplet
START=$(date +'%s')
JAILS=$(fail2ban-client status | awk -F: '/Jail/ {print $2}' | sed 's/,//g' | xargs)
ALL_IPS=0
FOUND_IPS=0

for jail in $JAILS; do
  IPS=$(fail2ban-client status "$jail" | awk -F : '/IP list/ {print $2}' | xargs)
  for IP in $IPS; do
    ((ALL_IPS++))
    C=$(curl -s "https://ipapi.co/${IP}/json" | jq -r '.country_code')
    [ "$C" = "KE" ] && {
      fail2ban-client set "$jail" unbanip "$IP"
      echo "Found $IP..." | logger -t unban
      ((FOUND_IPS++))
    }
  done
done
echo "Released $FOUND_IPS out of $ALL_IPS" | logger -t unban
STOP=$(date +'%s')
echo "Time taken: $((STOP - START)) seconds" | logger -t unban

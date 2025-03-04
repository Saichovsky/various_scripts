#!/bin/bash
# This script gets English IPTV channels from the iptv.org repo and merges them into a single
# list that can be used in an IPTV service. Store this script in /etc/cron.daily for daily updates

# Update these as per your web server configuration
LIST=eng.m3u
LISTDIR=/var/www/iptv/stream

cd /tmp
printf "Updating lists... "
curl -sL https://raw.githubusercontent.com/iptv-org/iptv/master/streams/u{s,k}.m3u >${LIST}

# Remove unwanted second header from the second list and sanitize content
H2=$(awk '/EXTM3U/ {if(NR !=1) print NR}' ${LIST})
sed -i "s/^#EXTM3U.*/#EXTM3U/; ${H2}d; /^#EXTINF.*XXX/I {N; d;}" ${LIST}
mv ${LIST} ${LISTDIR}/
echo "done!"

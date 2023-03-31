#!/bin/bash
# This script has been edited to work with Saltbox
# If you use the default rclone settings, this script will run out of the box.
#
# Do not edit this script unless you know what you are doing.


# Defaults
api=www.googleapis.com
whitelist=.whitelist-apis
blacklist=.blacklist-apis
testfile='GDSA1:/appbackups/GoogleDriveSpeedTest/500MB.bin'

#-------------------------#
# Check if Binfile exists #
#-------------------------#

if [ ! -f /mnt/remote/Backups/GoogleDriveSpeedTest/500MB.bin ]; then
    echo "First run detected. Creating 500MB test file and uploading it to Google Drive."
    mkdir /mnt/remotes/appbackups/GoogleDriveSpeedTest/
    fallocate -l 500M /tmp/500MB.bin
    mv /tmp/500MB.bin /mnt/remotes/appbackups/GoogleDriveSpeedTest/
    echo "Finished uploading to Google Drive."
fi

#-------------------#
# Hosts file backup #
#-------------------#

for f in /etc/hosts.backup; do
	if [ -f "$f" ]; then
		printf "Hosts backup file found - restoring\n"
		sudo cp $f /etc/hosts
		break
	else
		printf "Hosts backup file not found - backing up\n"
		sudo cp /etc/hosts $f
		break
	fi
done

#-----------------#
# Diggity dig dig #
#-----------------#

mkdir /tmp/tmpapi
mkdir /tmp/tmpapi/speedresults/
mkdir /tmp/tmpapi/testfile/
touch /tmp/tmpapi/rclone.log
dig +answer $api +short > /tmp/tmpapi/api-ips-fresh

#--------------------------#
# Whitelist Known Good IPs #
#--------------------------#

mv /tmp/tmpapi/api-ips-fresh /tmp/tmpapi/api-ips-progress
touch $whitelist
while IFS= read -r wip; do
	echo "$wip" >> /tmp/tmpapi/api-ips-progress
done < "$whitelist"
mv /tmp/tmpapi/api-ips-progress /tmp/tmpapi/api-ips-plus-white

#------------------------#
# Backlist Known Bad IPs #
#------------------------#

mv /tmp/tmpapi/api-ips-plus-white /tmp/tmpapi/api-ips-progress
touch $blacklist
while IFS= read -r bip; do
        grep -v "$bip" /tmp/tmpapi/api-ips-progress > /tmp/tmpapi/api-ips
        mv /tmp/tmpapi/api-ips /tmp/tmpapi/api-ips-progress
done < "$blacklist"
mv /tmp/tmpapi/api-ips-progress /tmp/tmpapi/api-ips

#--------------#
# Colour codes #
#--------------#

RED='\033[1;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
NC='\033[0m'

#------------------#
# Checking each IP #
#------------------#

input=tmpapi/api-ips
while IFS= read -r ip; do
	hostsline="$ip\t$api"
	sudo -- sh -c -e "echo '$hostsline' >> /etc/hosts"
	printf "Please wait, downloading the test file from $ip... "
	rclone copy --log-file /tmp/tmpapi/rclone.log -v "${testfile}" /tmp/tmpapi/testfile
		if grep -q "KiB/s" /tmp/tmpapi/rclone.log; then
		speed=$(grep "KiB/s" /tmp/tmpapi/rclone.log | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
	        printf "${RED}$speed KiB/s${NC} - Blacklisting\n"
        	rm -r /tmp/tmpapi/testfile
	        rm /tmp/tmpapi/rclone.log
		echo "$ip" >> .blacklist-apis
		sudo cp /etc/hosts.backup /etc/hosts
		else
	speed=$(grep "MiB/s" /tmp/tmpapi/rclone.log | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
	printf "${GRN}$speed MiB/s${NC}\n"
	echo "$ip" >> /tmp/tmpapi/speedresults/$speed
	rm -r /tmp/tmpapi/testfile
	rm /tmp/tmpapi/rclone.log
	sudo cp /etc/hosts.backup /etc/hosts
	fi
done < "$input"

#-----------------#
# Use best result #
#-----------------#

ls /tmp/tmpapi/speedresults > /tmp/tmpapi/count
max=$(sort -nr /tmp/tmpapi/count | head -1)
macs=$(cat /tmp/tmpapi/speedresults/$max)
printf "${YEL}The fastest IP is $macs at a speed of $max | putting into hosts file\n"
hostsline="$macs\t$api"
sudo -- sh -c -e "echo '$hostsline' >> /etc/hosts"

#-------------------#
# Cleanup tmp files #
#-------------------#

rm -r tmpapi

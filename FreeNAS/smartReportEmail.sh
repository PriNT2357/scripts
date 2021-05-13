#!/bin/sh

### https://pastebin.com/9xBRFFuB
### https://www.ixsystems.com/community/threads/scripts-to-report-smart-zpool-and-ups-status-hdd-cpu-t%C2%B0-hdd-identification-and-backup-the-config.27365/
### slightly modified to include Multi Zone Errors
### Modify your email and drive list as needed

### Parameters ###
logfile="/tmp/smart_report.tmp"
email="<<<YourEmailHere>>>"
subject="$(hostname) - SMART Status Report"
boundary="bv6780aw45hkgzf690w34a"
drives="$(smartctl --scan | grep "da" | awk '{print $1}')"
tempWarn=40
tempCrit=45
sectorsCrit=10
testAgeWarn=10
warnSymbol="?"
critSymbol="!"

### Set email headers ###
(
    echo "To: ${email}"
    echo "Subject: ${subject}"
    echo "MIME-Version: 1.0"
    echo "Content-Type: multipart/mixed; boundary=${boundary}"
    echo -e "\r\n"
) > "$logfile"

### Set email body ###
echo "--${boundary}" >> "$logfile"
echo "Content-Type: text/html" >> "$logfile"
echo "<pre style=\"font-size:14px\">" >> "$logfile"

###### summary ######
(
    echo ""
    echo "########## SMART status report summary for all drives ##########"
    echo ""
    echo "+------+-------------------+----+-----+-----+-----+-------+-------+--------+------+------+------+------+-------+----+"
    echo "|Device|Serial             |Temp|Power|Start|Spin |ReAlloc|Current|Offline |UDMA  |Multi |Seek  |High  |Command|Last|"
    echo "|      |                   |    |On   |Stop |Retry|Sectors|Pending|Uncorrec|CRC   |Zone  |Errors|Fly   |Timeout|Test|"
    echo "|      |                   |    |Hours|Count|Count|       |Sectors|Sectors |Errors|Errors|      |Writes|Count  |Age |"
    echo "+------+-------------------+----+-----+-----+-----+-------+-------+--------+------+------+------+------+-------+----+"
) >> "$logfile"
for ldrive in $drives
do
    (
	drive=$(echo $ldrive | awk '{gsub(/\/dev\//,""); print}') 
	smartctl -A -i -v 7,hex48 /dev/"$drive" | \
        awk -v device="$drive" -v tempWarn="$tempWarn" -v tempCrit="$tempCrit" -v sectorsCrit="$sectorsCrit" \
        -v testAgeWarn="$testAgeWarn" -v warnSymbol="$warnSymbol" -v critSymbol="$critSymbol" \
        -v lastTestHours="$(smartctl -l selftest /dev/"$drive" | grep "^# 1" | awk '{print $9}')" '\
        /Serial Number:/{serial=$3} \
        /Temperature_Celsius/{temp=$10} \
        /Power_On_Hours/{onHours=$10} \
        /Start_Stop_Count/{startStop=$10} \
        /Spin_Retry_Count/{spinRetry=$10} \
        /Reallocated_Sector/{reAlloc=$10} \
        /Current_Pending_Sector/{pending=$10} \
        /Offline_Uncorrectable/{offlineUnc=$10} \
        /Multi_Zone_Error_Rate/{mzErrors=$10} \
        /UDMA_CRC_Error_Count/{crcErrors=$10} \
        /Seek_Error_Rate/{seekErrors=("0x" substr($10,3,4));totalSeeks=("0x" substr($10,7))} \
        /High_Fly_Writes/{hiFlyWr=$10} \
        /Command_Timeout/{cmdTimeout=$10} \
        END {
            testAge=sprintf("%.0f", (onHours - lastTestHours) / 24);
            if (temp + 0 > tempCrit + 0 || reAlloc + 0 > sectorsCrit + 0 || pending + 0 > sectorsCrit + 0 || offlineUnc + 0 > sectorsCrit + 0)
                device=device " " critSymbol;
            else if (temp > tempWarn || reAlloc > 0 || pending > 0 || offlineUnc > 0 || testAge + 0 > testAgeWarn + 0)
                device=device " " warnSymbol;
            seekErrors=sprintf("%d", seekErrors);
            totalSeeks=sprintf("%d", totalSeeks);
            mzErrors=sprintf("%d", mzErrors);
            if (totalSeeks == "0") {
                seekErrors="N/A";
                totalSeeks="N/A";
            }
            if (hiFlyWr == "") hiFlyWr="N/A";
            if (cmdTimeout == "") cmdTimeout="N/A";
            printf "|%-6s|%-19s| %s |%5s|%5s|%5s|%7s|%7s|%8s|%6s|%6s|%6s|%6s|%7s|%4s|\n",
            device, serial, temp, onHours, startStop, spinRetry, reAlloc, pending, offlineUnc, \
            crcErrors, mzErrors, seekErrors, hiFlyWr, cmdTimeout, testAge;
        }'
    ) >> "$logfile"
done
(
    echo "+------+-------------------+----+-----+-----+-----+-------+-------+--------+------+------+------+------+-------+----+"
    echo ""
    echo ""
) >> "$logfile"

###### for each drive ######
for ldrive in $drives
do
    drive=$(echo $ldrive | awk '{gsub(/\/dev\//,""); print}')
    brand="$(smartctl -i /dev/"$drive" | grep "Model Family" | awk '{print $3, $4, $5}')"
    serial="$(smartctl -i /dev/"$drive" | grep "Serial Number" | awk '{print $3}')"
    (
        echo ""
        echo "########## SMART status report for ${drive} drive (${brand}: ${serial}) ##########"
        smartctl -H -A -l error /dev/"$drive"
        smartctl -l selftest /dev/"$drive" | grep "^# 1 \|Num" | cut -c6-
        echo ""
        echo ""
    ) >> "$logfile"
done
sed -i '' -e '/smartctl 6.3/d' "$logfile"
sed -i '' -e '/Copyright/d' "$logfile"
sed -i '' -e '/=== START OF READ/d' "$logfile"
sed -i '' -e '/SMART Attributes Data/d' "$logfile"
sed -i '' -e '/Vendor Specific SMART/d' "$logfile"
sed -i '' -e '/SMART Error Log Version/d' "$logfile"

echo "</pre>" >> "$logfile"
echo "--${boundary}--" >> "$logfile"

### Send report ###
sendmail -t < "$logfile"
rm "$logfile"

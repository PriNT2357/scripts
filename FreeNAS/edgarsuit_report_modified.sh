#!/bin/bash

###### ZPool & SMART status report with FreeNAS config backup
### Original script by joeschmuck, modified by Bidelu0hm, then by melp (me)
### https://github.com/edgarsuit/FreeNAS-Report/blob/master/report.sh

### At a minimum, enter email address in user-definable parameter section. Feel free to edit other user parameters as needed.
### If you find any errors, feel free to contact me on the FreeNAS forums (username melp) or email me at jason at jro dot io.

### Version: v1.3
### Changelog:
# v1.3:
#   - Added scrub duration column
#   - Fixed for FreeNAS 11.1 (thanks reven!)
#   - Fixed fields parsed out of zpool status
#   - Buffered zpool status to reduce calls to script
# v1.2:
#   - Added switch for power-on time format
#   - Slimmed down table columns
#   - Fixed some shellcheck errors & other misc stuff
#   - Added .tar.gz to backup file attached to email
#   - (Still coming) Better SSD SMART support
# v1.1:
#   - Config backup now attached to report email
#   - Added option to turn off config backup
#   - Added option to save backup configs in a specified directory
#   - Power-on hours in SMART summary table now listed as YY-MM-DD-HH
#   - Changed filename of config backup to exclude timestamp (just uses datestamp now)
#   - Config backup and checksum files now zipped (was just .tar before; now .tar.gz)
#   - Fixed degrees symbol in SMART table (rendered weird for a lot of people); replaced with a *
#   - Added switch to enable or disable SSDs in SMART table (SSD reporting still needs work)
#   - Added most recent Extended & Short SMART tests in drive details section (only listed one before, whichever was more recent)
#   - Reformatted user-definable parameters section
#   - Added more general comments to code
# v1.0:
#   - Initial release

### TODO:
# - Fix SSD SMART reporting
# - Add support for conveyance test


###### User-definable Parameters
### Email Address
email="email@address.com"

### Global table colors
okColor="#c9ffcc"       # Hex code for color to use in SMART Status column if drives pass (default is light green, #c9ffcc)
warnColor="#ffd6d6"     # Hex code for WARN color (default is light red, #ffd6d6)
critColor="#ff0000"     # Hex code for CRITICAL color (default is bright red, #ff0000)
altColor="#f4f4f4"      # Table background alternates row colors between white and this color (default is light gray, #f4f4f4)

### zpool status summary table settings
usedWarn=90             # Pool used percentage for CRITICAL color to be used
scrubAgeWarn=30         # Maximum age (in days) of last pool scrub before CRITICAL color will be used

### SMART status summary table settings
includeSSD="false"      # [NOTE: Currently this is pretty much useless] Change to "true" to include SSDs in SMART status summary table; "false" to disable
tempWarn=40             # Drive temp (in C) at which WARNING color will be used
tempCrit=45             # Drive temp (in C) at which CRITICAL color will be used
sectorsCrit=10          # Number of sectors per drive with errors before CRITICAL color will be used
testAgeWarn=5           # Maximum age (in days) of last SMART test before CRITICAL color will be used
powerTimeFormat="ymdh"  # Format for power-on hours string, valid options are "ymdh", "ymd", "ym", or "y" (year month day hour)

### FreeNAS config backup settings
configBackup="false"     # Change to "false" to skip config backup (which renders next two options meaningless); "true" to keep config backups enabled
saveBackup="true"       # Change to "false" to delete FreeNAS config backup after mail is sent; "true" to keep it in dir below
backupLocation="/path/to/config/backup"   # Directory in which to save FreeNAS config backups


###### Auto-generated Parameters
#host=$(hostname -s)
host=$(hostname)
logfile="/tmp/smart_report.tmp"
subject="Status Report for ${host}"
if [ "$configBackup" == "true" ]; then
    subject="Status Report and Configuration Backup for ${host}"
fi

boundary="gc0p4Jq0M2Yt08jU534c0p"
if [ "$includeSSD" == "true" ]; then
    #drives=$(for drive in $(sysctl -n kern.disks); do
    drives=$(for drive in $(sysctl -n kern.disks | sed 's/ada/\n1./g' | sed 's/da/\n2./g' | sort -t '.' -r -k 2,2 -V | sed 's/1\./ada/' | sed 's/2\./da/'); do
        if [ "$(smartctl -i /dev/"${drive}" | grep "SMART support is: Enabled")" ]; then
            printf "%s " "${drive}"
        fi
    done | awk '{for (i=NF; i!=0 ; i--) print $i }')
else
    #drives=$(for drive in $(sysctl -n kern.disks); do
    drives=$(for drive in $(sysctl -n kern.disks | sed 's/ada/\n1./g' | sed 's/da/\n2./g' | sort -t '.' -r -k 2,2 -V | sed 's/1\./ada/' | sed 's/2\./da/'); do
        if [ "$(smartctl -i /dev/"${drive}" | grep "SMART support is: Enabled")" ] && ! [ "$(smartctl -i /dev/"${drive}" | grep "Solid State Device")" ]; then
            printf "%s " "${drive}"
        fi
    done | awk '{for (i=NF; i!=0 ; i--) print $i }')
fi
pools=$(zpool list -H -o name)


###### Email pre-formatting
### Set email headers
(
    echo "From: ${email}"
    echo "To: ${email}"
    echo "Subject: ${subject}"
    echo "MIME-Version: 1.0"
    echo "Content-Type: multipart/mixed; boundary=${boundary}"
) > "$logfile"


###### Config backup (if enabled)
if [ "$configBackup" == "true" ]; then
    # Set up file names, etc for later
    tarfile="/tmp/config_backup.tar.gz"
    filename="$(date "+FreeNAS_Config_%Y-%m-%d")"
    ### Test config integrity
    if ! [ "$(sqlite3 /data/freenas-v1.db "pragma integrity_check;")" == "ok" ]; then
        # Config integrity check failed, set MIME content type to html and print warning
        (
            echo "--${boundary}"
            echo "Content-Type: text/html"
            echo "<b>Automatic backup of FreeNAS configuration has failed! The configuration file is corrupted!</b>"
            echo "<b>You should correct this problem as soon as possible!</b>"
            echo "<br>"
        ) >> "$logfile"
    else
        # Config integrity check passed; copy config db, generate checksums, make .tar.gz archive
        cp /data/freenas-v1.db "/tmp/${filename}.db"
        md5 "/tmp/${filename}.db" > /tmp/config_backup.md5
        sha256 "/tmp/${filename}.db" > /tmp/config_backup.sha256
        (
            cd "/tmp/" || exit;
            tar -czf "${tarfile}" "./${filename}.db" ./config_backup.md5 ./config_backup.sha256;
        )
        (
            # Write MIME section header for file attachment (encoded with base64)
            echo "--${boundary}"
            echo "Content-Type: application/tar+gzip"
            echo "Content-Transfer-Encoding: base64"
            echo "Content-Disposition: attachment; filename=${filename}.tar.gz"
            base64 "$tarfile"
            # Write MIME section header for html content to come below
            echo "--${boundary}"
            echo "Content-Type: text/html"
        ) >> "$logfile"
        # If logfile saving is enabled, copy .tar.gz file to specified location before it (and everything else) is removed below
        if [ "$saveBackup" == "true" ]; then
            cp "${tarfile}" "${backupLocation}/${filename}.tar.gz"
        fi
        rm "/tmp/${filename}.db"
        rm /tmp/config_backup.md5
        rm /tmp/config_backup.sha256
        rm "${tarfile}"
    fi
else
    # Config backup enabled; set up for html-type content
    (
        echo "--${boundary}"
        echo "Content-Type: text/html"
    ) >> "$logfile"
fi


###### Report Summary Section (html tables)
### zpool status summary table
(
    # Write HTML table headers to log file; HTML in an email requires 100% in-line styling (no CSS or <style> section), hence the massive tags
    echo "<br><br>"
    echo "<table style=\"border: 1px solid black; border-collapse: collapse;\">"
    echo "<tr><th colspan=\"9\" style=\"text-align:center; font-size:20px; height:40px; font-family:courier;\">ZPool Status Report Summary</th></tr>"
    echo "<tr>"
    echo "  <th style=\"text-align:center; width:130px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Pool<br>Name</th>"
    echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Status</th>"
    echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Read<br>Errors</th>"
    echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Write<br>Errors</th>"
    echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Cksum<br>Errors</th>"
    echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Used %</th>"
    echo "  <th style=\"text-align:center; width:100px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Scrub<br>Repaired<br>Bytes</th>"
    echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Scrub<br>Errors</th>"
    echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Last<br>Scrub<br>Age</th>"
    echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Last<br>Scrub<br>Time</th>"
    echo "</tr>"
) >> "$logfile"
poolNum=0
for pool in $pools; do
    # zpool health summary
    status="$(zpool list -H -o health "$pool")"
    # Total all read, write, and checksum errors per pool
    errors="$(zpool status "$pool" | grep -E "(ONLINE|DEGRADED|FAULTED|UNAVAIL|REMOVED)[ \\t]+[0-9]+")"
    readErrors=0
    for err in $(echo "$errors" | awk '{print $3}'); do
        if echo "$err" | grep -E -q "[^0-9]+"; then
            readErrors=1000
            break
        fi
        readErrors=$((readErrors + err))
    done
    writeErrors=0
    for err in $(echo "$errors" | awk '{print $4}'); do
        if echo "$err" | grep -E -q "[^0-9]+"; then
            writeErrors=1000
            break
        fi
        writeErrors=$((writeErrors + err))
    done
    cksumErrors=0
    for err in $(echo "$errors" | awk '{print $5}'); do
        if echo "$err" | grep -E -q "[^0-9]+"; then
            cksumErrors=1000
            break
        fi
        cksumErrors=$((cksumErrors + err))
    done
    # Not sure why this changes values larger than 1000 to ">1K", but I guess it works, so I'm leaving it
    if [ "$readErrors" -gt 999 ]; then readErrors=">1K"; fi
    if [ "$writeErrors" -gt 999 ]; then writeErrors=">1K"; fi
    if [ "$cksumErrors" -gt 999 ]; then cksumErrors=">1K"; fi
    # Get used capacity percentage of the zpool
    used="$(zpool list -H -p -o capacity "$pool")"
    # Gather info from most recent scrub; values set to "N/A" initially and overwritten when (and if) it gathers scrub info
    scrubRepBytes="N/A"
    scrubErrors="N/A"
    scrubAge="N/A"
    scrubTime="N/A"
    statusOutput="$(zpool status "$pool")"
    if [ "$(echo "$statusOutput" | grep "scan" | awk '{print $2}')" = "scrub" ]; then
        multiDay="$(echo "$statusOutput" | grep "scan" | grep -c "days")"
        scrubRepBytes="$(echo "$statusOutput" | grep "scan" | awk '{gsub(/B/,"",$4); print $4}')"
        if [ "$multiDay" -ge 1 ] ; then
          scrubErrors="$(echo "$statusOutput" | grep "scan" | awk '{print $10}')"
        else
          scrubErrors="$(echo "$statusOutput" | grep "scan" | awk '{print $8}')"
        fi
        # Convert time/datestamp format presented by zpool status, compare to current date, calculate scrub age
        if [ "$multiDay" -ge 1 ] ; then
          scrubDate="$(echo "$statusOutput" | grep "scan" | awk '{print $17"-"$14"-"$15"_"$16}')"
        else
          scrubDate="$(echo "$statusOutput" | grep "scan" | awk '{print $15"-"$12"-"$13"_"$14}')"
        fi
        scrubTS="$(date -j -f "%Y-%b-%e_%H:%M:%S" "$scrubDate" "+%s")"
        currentTS="$(date "+%s")"
        scrubAge=$((((currentTS - scrubTS) + 43200) / 86400))
        if [ "$multiDay" -ge 1 ] ; then
          scrubTime="$(echo "$statusOutput" | grep "scan" | awk '{print $6" "$7" "$8}')"
        else
          scrubTime="$(echo "$statusOutput" | grep "scan" | awk '{print $6}')"
        fi
    fi
    # Check if scrub is in progress
    if [ "$(echo "$statusOutput"| grep "scan" | awk '{print $4}')" = "progress" ]; then
        scrubAge="In Progress"
    fi
    # Set row's background color; alternates between white and $altColor (light gray)
    if [ $((poolNum % 2)) == 1 ]; then bgColor="#ffffff"; else bgColor="$altColor"; fi
    poolNum=$((poolNum + 1))
    # Set up conditions for warning or critical colors to be used in place of standard background colors
    if [ "$status" != "ONLINE" ]; then statusColor="$warnColor"; else statusColor="$bgColor"; fi
    if [ "$readErrors" != "0" ]; then readErrorsColor="$warnColor"; else readErrorsColor="$bgColor"; fi
    if [ "$writeErrors" != "0" ]; then writeErrorsColor="$warnColor"; else writeErrorsColor="$bgColor"; fi
    if [ "$cksumErrors" != "0" ]; then cksumErrorsColor="$warnColor"; else cksumErrorsColor="$bgColor"; fi
    if [ "$used" -gt "$usedWarn" ]; then usedColor="$warnColor"; else usedColor="$bgColor"; fi
    if [ "$scrubRepBytes" != "N/A" ] && [ "$scrubRepBytes" != "0" ]; then scrubRepBytesColor="$warnColor"; else scrubRepBytesColor="$bgColor"; fi
    if [ "$scrubErrors" != "N/A" ] && [ "$scrubErrors" != "0" ]; then scrubErrorsColor="$warnColor"; else scrubErrorsColor="$bgColor"; fi
    if [ "$(echo "$scrubAge" | awk '{print int($1)}')" -gt "$scrubAgeWarn" ]; then scrubAgeColor="$warnColor"; else scrubAgeColor="$bgColor"; fi
    (
        # Use the information gathered above to write the date to the current table row
        printf "<tr style=\"background-color:%s;\">
            <td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s%%</td>
            <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            <td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
        </tr>\\n" "$bgColor" "$pool" "$statusColor" "$status" "$readErrorsColor" "$readErrors" "$writeErrorsColor" "$writeErrors" "$cksumErrorsColor" \
        "$cksumErrors" "$usedColor" "$used" "$scrubRepBytesColor" "$scrubRepBytes" "$scrubErrorsColor" "$scrubErrors" "$scrubAgeColor" "$scrubAge" "$scrubTime"
    ) >> "$logfile"
done
# End of zpool status table
echo "</table>" >> "$logfile"

### SMART status summary table
(
    # Write HTML table headers to log file
    echo "<pre style=\"font-size:14px\">"
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
# End SMART summary table and summary section
(
    echo "+------+-------------------+----+-----+-----+-----+-------+-------+--------+------+------+------+------+-------+----+"
    echo ""
    echo "</pre>"
) >> "$logfile"


###### Detailed Report Section (monospace text)
echo "<pre style=\"font-size:14px\">" >> "$logfile"

### zpool status for each pool
for pool in $pools; do
    (
        # Create a simple header and drop the output of zpool status -v
        echo "<b>########## ZPool status report for ${pool} ##########</b>"
        echo "<br>"
        zpool status -v "$pool"
        echo "<br><br>"
    ) >> "$logfile"
done

### SMART status for each drive
for drive in $drives; do
    # Gather brand and serial number of each drive
    brand="$(smartctl -i /dev/"$drive" | grep "Model Family" | awk '{print $3, $4, $5}')"
    serial="$(smartctl -i /dev/"$drive" | grep "Serial Number" | awk '{print $3}')"
    (
        # Create a simple header and drop the output of some basic smartctl commands
        echo "<br>"
        echo "<b>########## SMART status report for ${drive} drive (${brand}: ${serial}) ##########</b>"
        smartctl -H -A -l error /dev/"$drive"
        smartctl -l selftest /dev/"$drive" | grep "Extended \\|Num" | cut -c6- | head -2
        smartctl -l selftest /dev/"$drive" | grep "Short \\|Num" | cut -c6- | head -2 | tail -n -1
        echo "<br><br>"
    ) >> "$logfile"
done
# Remove some un-needed junk from the output
sed -i '' -e '/smartctl 6.3/d' "$logfile"
sed -i '' -e '/Copyright/d' "$logfile"
sed -i '' -e '/=== START OF READ/d' "$logfile"
sed -i '' -e '/SMART Attributes Data/d' "$logfile"
sed -i '' -e '/Vendor Specific SMART/d' "$logfile"
sed -i '' -e '/SMART Error Log Version/d' "$logfile"

### End details section, close MIME section
(
    echo "</pre>"
    echo "--${boundary}--"
)  >> "$logfile"

### Send report
sendmail -t -oi < "$logfile"
rm "$logfile"
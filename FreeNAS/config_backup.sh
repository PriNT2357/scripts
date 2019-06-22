#!/bin/sh

### http://pastebin.com/syF2JeAU
### https://forums.freenas.org/index.php?threads/scripts-to-report-smart-zpool-and-ups-status-hdd-cpu-t%C2%B0-hdd-identification-and-backup-the-config.27365/

### Parameters ###
logfile="/tmp/config_backup_error.tmp"
tarfile="/tmp/config_backup.tar"
filename="$(date "+FreeNAS_Config_%Y-%m-%d_%H-%M-%S")"
email="<<<YourEmailHere>>>"
subject="Config Backup for FreeNAS"

if [ "$(sqlite3 /data/freenas-v1.db "pragma integrity_check;")" == "ok" ]
then
### Send config backup ###
    cp /data/freenas-v1.db "/tmp/${filename}.db"
    md5 "/tmp/${filename}.db" > /tmp/config_backup.md5
    sha256 "/tmp/${filename}.db" > /tmp/config_backup.sha256
    cd "/tmp/"; tar -cf "${tarfile}" "./${filename}.db" ./config_backup.md5 ./config_backup.sha256; cd -
    uuencode "${tarfile}" "${filename}.tar" | mail -s "${subject}" "${email}"
    rm "/tmp/${filename}.db"
    rm /tmp/config_backup.md5
    rm /tmp/config_backup.sha256
    rm "${tarfile}"
else
### Send error message ###
    (
        echo "To: ${email}"
        echo "Subject: ${subject}"
        echo "Content-Type: text/html"
        echo "MIME-Version: 1.0"
        echo -e "\r\n"
        echo "<pre style=\"font-size:14px\">"
        echo ""
        echo "Automatic backup of FreeNAS config failed."
        echo ""
        echo "The config file is corrupted!"
        echo ""
        echo "You should correct this problem as soon as possible."
        echo ""
        echo "</pre>"
    ) >> "${logfile}"
    sendmail -t < "${logfile}"
    rm "${logfile}"
fi

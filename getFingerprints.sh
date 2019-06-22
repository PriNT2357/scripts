#!/bin/bash

for f in $(find /etc/ -name "*.pub" -type f); do
	echo "$f";
#	echo "  sha256"
	echo "    $(ssh-keygen -E sha256 -l -f $f)"
#	echo "  md5"
	echo "    $(ssh-keygen -E md5 -l -f $f)"
done

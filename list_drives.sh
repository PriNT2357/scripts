#!/bin/bash

for d in $(sudo camcontrol devlist | grep ",da" | awk '{print $3 " " $11}' | grep -o -e ",.*)" | sed 's/,//' | sed 's/)//'); do sudo smartctl -a /dev/$d | grep "Serial Number" | echo -e $d '\t' $(awk '{print $3}'); done
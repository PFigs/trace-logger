#!/bin/bash
DEVICE=`lsusb -d 1366:1015 -v | grep iSerial | awk {'print $3'}`;
echo $DEVICE > devices.rst;
sed -i 's/ /\t/g' ./devices.rst
chown builder:builder devices.rst;
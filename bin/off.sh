#!/bin/bash
stty -F /dev/ttyUSB0 9600
echo -e '\xFF\x01\x00' > /dev/ttyUSB0
exit 0


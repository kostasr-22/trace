#!/bin/sh

if [ -z "$1" ]
then
	echo "Usage: $0 <pid>"
	exit 1
fi

cat /proc/$1/maps > trace.maps

./trace $1 2>&1 > trace.out

exit 0

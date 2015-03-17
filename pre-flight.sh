#/usr/bin/bash

if [[ -f ../config ]];
then
	source ../config
else
	echo "Could not find config file"
	exit 1
fi;

if [[ -d "./.git" ]];
then 
	CURRENT_TAG=$( git describe --tags --long --always );
elif [[ -f "./git-status-log" ]];
then
	CURRENT_TAG=$( grep "^commit" ./git-status-log | head -n 1 | sed "s/^commit\ \([0-9a-f]\{7\}\).*/\1/" );
else
	CURRENT_TAG="<VOID>";
	echo "warning: current directory does neither hold an installed version of the pipeline nor a git repository";
fi;

echo current_tag: $CURRENT_TAG
echo version    : $version


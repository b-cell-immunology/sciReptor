#/usr/bin/bash

export RAWDATADIR="../raw_data";

if [[ -e .preflight_failed ]]; then	rm .preflight_failed; fi

if [[ $1 == "" ]];
then
	echo "ERROR: No runname provided!";
	echo "usage: pre-flight.sh <runname>";
	exit 1;
fi;

export RUNNAME="$1";
export RUNDIR="$RAWDATADIR"/"$RUNNAME";

if [[ !  -e "$RUNDIR" ]];
then
	echo "ERROR: No directory for runname \"$RUNNAME\" found!";
	exit 1;
fi;

if [[ -f ../config ]];
then
	source ../config;
else
	echo "ERROR: Could not find config file";
	exit 1;
fi;

# == Check git and repo version ==

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


if [[ "$CURRENT_TAG" != "$version" ]];
then
	echo "FAILED: Code version in repository ($CURRENT_TAG) is not identical to \"version\" tag in config file ($version)!"
	touch .preflight_failed
fi;

# == Check input files ==
ls -1 "$RUNDIR"/*.fasta | while read FASTANAME
do
	if [[ ! -e "${FASTANAME}.qual" ]];
	then
		echo "FAILED: Sequence file \"$FASTANAME\" does not have a corresponding quality score file (.qual)!";
		touch .preflight_failed
	fi;

	if [[ ! -e "${FASTANAME}.info" ]];
	then
		echo "FAILED: Sequence file \"$FASTANAME\" does not have a corresponding metainformation file (.info)!";
		touch .preflight_failed
	else
		if ( grep -q "^\s*runname=" "${FASTANAME}.info" );
		then
			INFO_RUNNAME="$( grep "^\s*runname=" "${FASTANAME}.info" | tail -n 1 | sed "s/^\s*runname=//" )";
			if [[ "$INFO_RUNNAME" != "$RUNNAME" ]];
			then
				echo "FAILED: The \"runname\" entry in sequence information file \"${FASTANAME}.info\" does not match runname directory \"$RUNNAME\"!";
				touch .preflight_failed
			fi;
		else
			echo "FAILED: Sequence information file \"${FASTANAME}.info\" does not contain a \"runnname\" entry!";
			touch .preflight_failed
		fi;
	fi;
done


if [[ -e .preflight_failed ]];
then
	rm .preflight_failed;
	exit 2;
else
	exit 0;
fi;

# Pre-flight checks to be implemented:
# 1. Check whether DB schemes "database" and "library" exist and confirm that user has the required access privileges

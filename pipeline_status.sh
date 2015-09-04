#!/usr/bin/bash

REGEX_PROC_PIPELINE='make\s+-j\s+[0-9]{1,3}\s+all\s+(run|experiment_id)=\w+\s+(run|experiment_id)=.*'

if [[ $( pgrep -c -f "$REGEX_PROC_PIPELINE" ) -gt 0 ]];
then
	echo "List of currently running pipelines:"
	ps -fp $( pgrep -f "$REGEX_PROC_PIPELINE" )
else
	echo "No pipeline processes found."
fi;

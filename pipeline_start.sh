#!/usr/bin/bash
#
# This script starts the central 'make' process to run the pipeline. It logs all output into a logfile
# in the main project directory. In addition it starts the pipeline as a background process.
#

if [[ $# > 0 ]];
then
	SHOW_HELP=0
	for COMLINE_CURRENT in "$@";
	do
		case $COMLINE_CURRENT in
			--cores=*)
				PIPELINE_CORES="${COMLINE_CURRENT#*=}"
				shift
				if ! [[ $PIPELINE_CORES =~ ^[0-9]+$ ]];
				then
					echo "ERROR: <CPU cores> must be a positive integer value"
					SHOW_HELP=1
				fi
			;;
			--run=*)
				PIPELINE_RUN="${COMLINE_CURRENT#*=}"
				shift
			;;
			--experiment_id=*)
				PIPELINE_EXPERIMENT_ID="${COMLINE_CURRENT#*=}"
				shift
			;;
			-?|-h|--help)
				SHOW_HELP=1
	    			shift
			;;
			*)
				echo "Invalid command line option"
				SHOW_HELP=1
		    		shift
			;;
		esac
	done;
else
	SHOW_HELP=1
fi;

if [[ $SHOW_HELP == 1 ]] || [[ ! $PIPELINE_CORES ]] || [[ ! $PIPELINE_RUN ]] || [[ ! $PIPELINE_EXPERIMENT_ID ]];
then
	echo "Usage: $0 --cores=<CPU cores> --run=<run_id> --experiment_id=<experiment_id>"
	echo "All parameters are mandatory."
	exit 1
fi;

TEMP_LOGFILE="../pipeline_run_${PIPELINE_RUN}_$( date --utc +%Y-%m-%d-%H-%M-%S )_$( openssl rand -base64 3 | tr [OIl/+=] [oiLXYZ] ).log"
touch $TEMP_LOGFILE
echo Logging to $TEMP_LOGFILE
nohup make -j ${PIPELINE_CORES} all run=${PIPELINE_RUN} experiment_id=${PIPELINE_EXPERIMENT_ID} > ${TEMP_LOGFILE} 2>&1 &
MAKE_PID=$!
echo "Processing started, PID $MAKE_PID"
tail --pid=${MAKE_PID} -f ${TEMP_LOGFILE}

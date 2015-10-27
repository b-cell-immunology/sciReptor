#!/usr/bin/bash
#
# This script will simply repeat the processing of a dataset over and over until some type of non-clean exit occurs.
# If the bug is suspected to involve the 'make' path, the switch '--debug=bv' should be added to the 'nohup make ...' line in the pipeline_start.sh script.

export RUN_CURR=""       # run
export EXP_CURR=""       # experiment_id
export DB_CURR=$( grep "^database" ../config | sed "s/.*=//" )
export MAIL_ADDR=""

while true;
do
	mysql --defaults-file=${HOME}/.my.cnf --defaults-group-suffix=_igdb --database=${DB_CURR} --batch --execute "SHOW TABLES;" \
	| tail -n +2 \
	| xargs -n1 -I '{}' mysql --defaults-file=${HOME}/.my.cnf --defaults-group-suffix=_igdb --database=${DB_CURR} --execute "TRUNCATE TABLE ${DB_CURR}.{};"

	mysql --defaults-file=${HOME}/.my.cnf --defaults-group-suffix=_igdb --database=${DB_CURR} --batch --execute "SHOW TABLES;" \
	| tail -n +2 \
	| grep "^derived_.*" \
	| xargs -n1 -I '{}' mysql --defaults-file=${HOME}/.my.cnf --defaults-group-suffix=_igdb --database=${DB_CURR} --execute "DROP TABLE ${DB_CURR}.{};"

	mysql --defaults-file=${HOME}/.my.cnf --defaults-group-suffix=_igdb --database=${DB_CURR} --batch --execute "SHOW PROCEDURE STATUS;" \
	| tail -n +2 \
	| grep "^${DB_CURR}.*" \
	| sed "s/^${DB_CURR}\s\+\([[:alnum:]_]\+\).*/\1/" \
	| xargs -n1 -I '{}' mysql --database=${DB_CURR} --execute "DROP PROCEDURE ${DB_CURR}.{};"

	make clean run=${RUN_CURR}

	./pipeline_start.sh --cores=4 --run=${RUN_CURR} --experiment_id=${EXP_CURR}

	if (! tail -n10 $( ls -1t ../pipeline_run_${RUN_CURR}_* | head -n1 ) | grep -q "^Finished without errors on" );
	then
		break
	fi
done
tail -n10 $( ls -1t ../pipeline_run_${RUN_CURR}_* | head -n1 ) | mail -s "Shakedown crashed" ${MAIL_ADDR}

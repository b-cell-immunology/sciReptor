# Name:			lib_pipeline_QC.R
# Version:		0.1.4 (2014-12-31)
# Authors:		Christian Busse, Katharina Imkeller
# Maintainer:	Christian Busse (busse@mpiib-berlin.mpg.de)
# Licence:		AGPL3
# Provides:		This library provides functions that perform DB querys and return aggregated data structures that can be used
#				for graphical output. It does not contain the output functions itself.
# Requires:		nothing
# 
#

# Call:			func.tag.stats(db_connection, db_name, run_name, tag.landing.zone, locus[, debug_level])
#
# Parameters:	<db_connection>:	handle to MySQL database, other DBMS are not supported, read-only access is sufficient
#				<db_name>:			name of the DB scheme
#				<run_name>:			name of the sequencing run
#				<locus>:			name of the locus to analyse, must match [HKL] as in the DB
#				<tag.landing.zone>: minimal start position of the distal tag
#				[debug_level]:		defaults to 2; set to 3 for additional output
# Returns:		A list containing the following elements:
#				- "F"		[list]		Aggregated mutation status of the proximal tag. Unmutated tags are counted as "no_mutation",
#										mutated ones are aggregated using the concatenated string of the mutations detected (using
#										[d]eletion, [i]nsertion and [r]eplacement). Note that multiple mutation of the same type
#										will be counted individually. The order in the string is not related to the order of mutations
#										in the tags.
#				- "R"		[list]		Like "F", but contains data for the distal tag
#				- "status"	[vector]	Aggregated numbers of reads with no, distal only, proximal only and both tags are 
#										in elements 1 to 4, respectively
#				- "locus"	[char]		The name of the locus as provided in the 'locus' parameter
# Description:	This function provides a basic statistic of reads and tag identification status of a run. The requests are made
#				in two stages since MySQL does not  provide an PARTITION function that would allow to obtain the best tag match
#				for a given read. Therefore this is implemented as a two stage process, first to obtain the list of all reads
#				that match the criteria (run, locus) and then request the best tags for a given # read and tag position (proximal
#				or distal). Note that the "F" and "R" used here pertain to *tag* and not to *read* directionality. They are
#				hardcoded here since they are part of the basic DB structure that is unlikely to change.
#
func.tag.stats <- function(connection.mysql, name.database, name.run, tag.landing.zone, locus, debug.level) {

	if(missing(debug.level)) {
		debug.level <- 2
	}

	list.output <- list(
		"F" = NULL,
		"R" = NULL,
		"status" = rep(0,4),
		"locus" = locus
	)

	selected.seq_ids <- dbGetQuery(connection.mysql,
		paste(
			"SELECT seq_id ",
			"FROM ", name.database,".reads ",
			"JOIN (SELECT sequencing_run_id FROM ", name.database,".sequencing_run ",
			"WHERE sequencing_run.name='", name.run, "') AS selected_run ",
			"ON reads.sequencing_run_id = selected_run.sequencing_run_id ",
			"WHERE locus='", locus, "'",
			sep=""
		)
	)

	if (length(selected.seq_ids) > 0) {
		for (current.seq_id in selected.seq_ids[,"seq_id"]) {

			if(debug.level >= 4) cat(paste("[lib_pipeline_QC.R][DEBUG] Selecting reads with seq_id ", current.seq_id, " and locus ", locus, "\n", sep=""));

			temp.forward <- dbGetQuery(connection.mysql,
				paste(
					"SELECT insertion, deletion, replacement ",
					"FROM ", name.database, ".reads_tags ",
					"WHERE seq_id = ", current.seq_id, " ",
					"AND direction = 'F' ",
					"ORDER BY percid DESC, start ASC ",
					"LIMIT 1;",
					sep=""
				)
			)

			temp.reverse <- dbGetQuery(connection.mysql,
				paste(
					"SELECT insertion, deletion, replacement ",
					"FROM ", name.database, ".reads_tags ",
					"WHERE seq_id = ", current.seq_id, " ",
					"AND direction = 'R' ",
					"AND start >= ", tag.landing.zone ," ",
					"ORDER BY percid DESC, start DESC ",
					"LIMIT 1;",
					sep=""
				)
			)

			temp.status <- dim(temp.forward)[1] * 2 + dim(temp.reverse)[1]

			list.output[["status"]][temp.status + 1] <- list.output[["status"]][temp.status + 1] + 1

			func.mutation.string <- function(mutation.count) {
				temp.string <- ""
				for (mutation.class in c("deletion", "insertion", "replacement")) {
					temp.string <- paste(
						temp.string,
						paste(
							rep(
								substr(mutation.class,1,1),
								mutation.count[mutation.class]
							),
							collapse=""
						),			
						sep=""
					)
				}

				if (nchar(temp.string) == 0) {temp.string <- "no_mutation"}
				return(temp.string)
			}

			if(bitwAnd(temp.status, 2) == 2) {
				string.mutations <- func.mutation.string(temp.forward)
				if(string.mutations %in% names(list.output[["F"]])) {
					list.output[["F"]][[string.mutations]] <- list.output[["F"]][[string.mutations]] + 1
				} else {
					list.output[["F"]][[string.mutations]] <- 1
				}
			}

			if(bitwAnd(temp.status, 1) == 1) {
				string.mutations <- func.mutation.string(temp.reverse)
				if(string.mutations %in% names(list.output[["R"]])) {
					list.output[["R"]][[string.mutations]] <- list.output[["R"]][[string.mutations]] + 1
				} else {
					list.output[["R"]][[string.mutations]] <- 1
				}
			}
		}
	}

	return(list.output)
}

# Call:			func.locus.count(db_connection, db_name, run_name)
#
# Parameters:	<db_connection>:	handle to MySQL database, other DBMS are not supported, read-only access is sufficient
#				<db_name>:			name of the DB scheme
#				<run_name>:			name of the sequencing run
# Returns:		A data frame with two columns: 
#				- "locus"	The single character designation of the locus or "NULL"
#				- "count"	aggregated number of occurences of "locus" in the current run
# Description:	This function provides a basic aggregation of the loci found in a given run.
#
func.locus.count <- function(connection.mysql, name.database, name.run){
	df.output <- dbGetQuery(
		connection.mysql,
		paste(
			"SELECT locus, COUNT(DISTINCT seq_id) AS count ",
			"FROM ", name.database,".reads ",
			"JOIN (SELECT sequencing_run_id FROM ", name.database, ".sequencing_run ",
			"WHERE sequencing_run.name='", name.run, "') AS selected_run ",
			"ON reads.sequencing_run_id = selected_run.sequencing_run_id ",
			"GROUP BY locus",
			sep=""
		)
	)

	df.output[is.na(df.output[,"locus"]), "locus"] <- "NULL"

	return(df.output)
}

# Call:			func.tag.position.aggregate(db_connection, db_name, name.run, direction, aggregation.range, bin.size)
#
# Parameters:	<db_connection>:	handle to MySQL database, other DBMS are not supported, read-only access is sufficient
#				<db_name>:			name of the DB scheme
#				name.run:			name of the sequencing run
#				direction:			orientation of the tags
#				aggregation.range	(maximum tag start position [bp] to be included + 1) (700 should be a good default)
#				bin.size			size of bins in bp
# Returns:		A matrix containing the aggregated position counts for each locus
# Description:	This function aggregates tag counts versus position and locus. The position binning is done with a width of <bin.size> bp
#

func.tag.position.aggregate <- function(connection.mysql, name.database, name.run, direction, aggregation.range, bin.size){

	aggregation.bins <- ifelse(
		aggregation.range/bin.size==trunc(aggregation.range/bin.size),
		aggregation.range/bin.size,
		trunc(aggregation.range/bin.size)+1
	)

	func.matrix.aggregate <- function(positions, locus.current) {
		vector.locus.select <- positions[,"locus"]==locus.current
		vector.locus.range <- positions[,"posstart"] < aggregation.range
		if (any(vector.locus.select & ! vector.locus.range)) {
			cat(paste(
				"[lib_pipeline_QC.R][INFO] Tag position aggregation yielded positions out of specificed range for locus ",
				locus.current,
				" and direction ",
				direction,
				". A total of ",
				sum(positions[(vector.locus.select & ! vector.locus.range),"counts"]),
				" tags were clipped.\n",
				sep=""
			))
			vector.locus.select <- vector.locus.select & vector.locus.range
		}

		vector.output <- rep(0,aggregation.bins)
		vector.output.select <- ( 
			seq(from=0, by=bin.size, length.out=aggregation.bins)
			%in%
			positions[vector.locus.select, "posstart"]
		)
		if (sum(vector.output.select) != sum(vector.locus.select)) {
			print("[lib_pipeline_QC.R][DEBUG][START   ] Mismatched selection vector length")
			print(positions)
			print(sum(vector.output.select))
			print(sum(vector.locus.select))
			print(vector.output.select)
			print(vector.locus.select)
			print("[lib_pipeline_QC.R][DEBUG][STOP    ] Mismatched selection vector length")
		}
		vector.output[vector.output.select] <- positions[vector.locus.select, "counts"]

		return(vector.output)
	}

	df.tag.positions.binned <- dbGetQuery(
		connection.mysql,
		paste(
			"SELECT COUNT(DISTINCT reads_tags.reads_tagid) AS counts, TRUNCATE(start/", bin.size,",0)*",bin.size," AS posstart, locus ",
			"FROM ", name.database,".reads ",
			"INNER JOIN ", name.database,".reads_tags ",
			"ON (reads.seq_id = reads_tags.seq_id ",
				"AND direction = '", direction,"') ",
			"INNER JOIN ", name.database, ".sequencing_run ",
			"ON (reads.sequencing_run_id = sequencing_run.sequencing_run_id ",
				"AND sequencing_run.name = '", name.run, "') ",
			"WHERE locus IS NOT NULL ",
			"GROUP BY posstart, locus",
			sep=""
		)
	)

	matrix.tag.positions.binned <- sapply(
		X=sort(unique(df.tag.positions.binned[,"locus"])),
		FUN=func.matrix.aggregate,
		positions=df.tag.positions.binned
	)

	return(matrix.tag.positions.binned)

}


# Call:			func.reads.well(connection.mysql, name.database, name.run, locus[, consensus.rank])
#
# Parameters:	<db_connection>:	handle to MySQL database, other DBMS are not supported, read-only access is sufficient
#				<db_name>:			name of the DB scheme
#				<run_name>:			name of the sequencing run
#				<locus>:			name of the locus to analyse, must match [HKL] as in the DB
#				[consensus.rank]:	by default (0) the function will count all reads mapped to a well. If this option is set (1 or 2) 
#									it will select only the reads belonging to the first or second consensus of the well.
# Returns:		An ordered vector containing the number of reads mapped to the individual wells. Wells with zero reads are removed.
# Description:	The function count the reads mapped to the wells of a given DB, run, locus.
#
func.reads.well <- function(connection.mysql, name.database, name.run, locus, consensus.rank) {

	if(missing(consensus.rank)) {
		consensus.rank <- 0
	}

	if(consensus.rank == 0) {
		temp.reads.well <- dbGetQuery(
			connection.mysql,
			paste(
				"SELECT COUNT(*) AS cnt ",
				"FROM ", name.database, ".reads ",
				"JOIN ", name.database, ".sequencing_run ",
				"ON (",
					"reads.sequencing_run_id = sequencing_run.sequencing_run_id AND ",
					"sequencing_run.name = '", name.run,"' AND ",
					"reads.locus = '", locus,
				"') ",
				"WHERE well_id IS NOT NULL ",
				"GROUP BY well_id ", 
				"ORDER BY cnt ASC",
				sep=""
			)
		)
	} else {
		temp.reads.well <-dbGetQuery(
			connection.mysql,
			paste(
				"SELECT COUNT(consensus_stats.consensus_id) AS cnt ",
				"FROM ", name.database, ".reads ",
				"JOIN ", name.database, ".sequencing_run ",
				"ON (",
					"reads.sequencing_run_id = sequencing_run.sequencing_run_id AND ",
					"sequencing_run.name = '", name.run,"' AND ",
					"well_id IS NOT NULL AND ",
					"reads.locus = '", locus,
				"') ",
				"JOIN ", name.database, ".consensus_stats ",
				"ON consensus_stats.consensus_id = reads.consensus_id ",
				"JOIN ", name.database, ".sequences ",
				"ON (sequences.seq_id = consensus_stats.sequences_seq_id AND sequences.consensus_rank = ", consensus.rank, ") ",
				"GROUP BY consensus_stats.consensus_id ",
				"ORDER BY cnt ASC",
				sep=""
			)
		)
	}
	return(as.vector(t(temp.reads.well)))
}

# Call:			func.qual.length(connection.mysql, name.database, name.run, locus)
#
# Parameters:	connection.mysql:	handle to MySQL database, other DBMS are not supported, read-only access is sufficient
#				name.database:		name of the DB scheme
#				name.run:			name of the sequencing run
#				locus:				name of the locus to analyse, must match [HKL] as in the DB
# Returns:		Data frame with two columns:
#				- "length"			aggregated number of reads terminating at a given bp (meaning that this is the last bp of the read).
#				- "quality"			average (NA removed) quality score at a given position
#				There is no bp index, the first line is bp 1 and the structure is continuous from there to the last line (=last bp).
# Description:	This function performs basic aggregation of read counts and quality value by bp position. 
#				CAVE: This function does require a reasonable amount of memory (2+ GB) for a normal sized run. It's is not clear whether there
#				would be  any more elegant solution (i.e. performing the aggregation in the DBMS), since this would require quite a lot from MySQL.
func.qual.length <- function(connection.mysql, name.database, name.run, locus) {

 	query.result <- dbGetQuery(
 		connection.mysql,
		paste(
		"SELECT length, quality ",
			"FROM ", name.database, ".reads ",
			"INNER JOIN ", name.database, ".sequencing_run ",
			"ON (reads.sequencing_run_id = sequencing_run.sequencing_run_id ",
				"AND locus='", locus, "' ",
				"AND sequencing_run.name = '", name.run, "')",
			sep=""
		)
	)

	if (length(query.result) > 0) {
		length.max <- max(query.result$length)
		length.aggregated <- hist(query.result$length, breaks=c(0:length.max), plot=FALSE)$counts

		# Split the quality string, convert it to integers and fill the ragged right ends with NAs so that it can be converted to an array
		#
		quality.array <- sapply(
			query.result$quality,
			FUN=function(quality.string.current) {
				quality.integer <- as.integer(unlist(strsplit(quality.string.current, " ")))
				return(
					c(
						quality.integer, 
						rep(NA, length.max - length(quality.integer))
					)
				)
			},
			USE.NAMES=FALSE
		)
		quality.means <- colMeans(t(quality.array), na.rm=TRUE)

		# Make the function a little bit more considerate in terms of memory usage, run garbage collection explicitly
		#
		rm(query.result, quality.array)
		gc()

	} else {
		length.aggregated <- NULL
		quality.means <- NULL
	}

	return(
		data.frame(
			length = length.aggregated,
			quality = quality.means
		)
	)
}

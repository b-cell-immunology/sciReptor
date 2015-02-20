# Name:			flow_to_db.R
# Verson:		0.1.2 (2015-02-07)
# Authors:		Christian Busse
# Maintainer:	Christian Busse (busse@mpiib-berlin.mpg.de)
# Licence:		AGPL3
# Provides:		This script imports flow cytometric data into the DB 
# Requires:		lib_pipeline_common, lib_authentication_common, lib_flowcyt_sorting_indexed, RMySQL
# Comments:		This script inserts the information for FCS files into the database
# Changes:		CB Feb 2015: config file and FCS file selection now configurable via command line, log levels
#
#
library(RMySQL)
source("lib/lib_pipeline_common.R")
source("lib/lib_authentication_common.R")
source("lib/lib_flowcyt_sorting_indexed.R")

# Set default parameters
#
file.config <- "../config"				# config file
search.fcs.dir <- "."					# directory containing the FCS files
search.fcs.regexp <- ".*\\.fcs$"		# RegExp pattern to select FCS files (default: all)

# Get command line parameters and split at "=", then do parsing. Probably not the 'R'-way to do things, but works
# 
vector.cmd.line <- unlist(strsplit(commandArgs(TRUE),"="))
if(length(vector.cmd.line) > 0) {
	cnt.cmd.line <- 1
	while(cnt.cmd.line < length(vector.cmd.line)){
		if(vector.cmd.line[cnt.cmd.line] == "--config"){
			file.config <- vector.cmd.line[cnt.cmd.line + 1]
			cnt.cmd.line <- cnt.cmd.line + 2
			next;
		}
		if(vector.cmd.line[cnt.cmd.line] == "--path"){
			search.fcs.dir <- vector.cmd.line[cnt.cmd.line + 1]
			cnt.cmd.line <- cnt.cmd.line + 2
			next;
		}
		if(vector.cmd.line[cnt.cmd.line] == "--regexp"){
			search.fcs.regexp <- vector.cmd.line[cnt.cmd.line + 1]
			cnt.cmd.line <- cnt.cmd.line + 2
			next;
		}
		stop(paste("ERROR: flow_to_db.R: Unknown option:",vector.cmd.line[cnt.cmd.line]))
	}
	if(cnt.cmd.line == length(vector.cmd.line)) {
		warning(paste("WARNING: flow_to_db.R: Did not parse command line option",vector.cmd.line[cnt.cmd.line]))
	}
}

# Load parameters from config file
#
list.config.global <- func.read.config(file.config)

# Set the log level as specified in config file, if not set there default to 3 (INFO)
#
if(! is.null(list.config.global[["log_level"]])) {
	config.debug.level <- list.config.global[["log_level"]]
} else {
	config.debug.level <- 3
}


# Get the list of FCS files and load them, exit with warning if no files are found
#
vector.file.names.full <- list.files(path=search.fcs.dir, pattern=search.fcs.regexp, full.names=TRUE)
if (length(vector.file.names.full) == 0) {
	if (config.debug.level >= 2) {
		cat(paste("[flow_to_db.R][WARNING] No files matching pattern \"", search.fcs.regexp, "\" were found in path \"",search.fcs.dir,"\". No flow data was imported.\n",sep=""))
	}
	quit(save="no", status=0)
}

list.fcs.all.indexed <- lapply(
	vector.file.names.full,
	FUN=func.read.indexed.FCS  
)

# Get a DB connection, using the preferred authentication mechanism (defined in $HOME/.my.authencation, defaults to usage of .my.cnf)
#
connection.mysql <- switch(config.authentication.method,
	cnf_file = dbConnect(
		MySQL(),
		group=config.authentication.profile[["cnf_group"]]
	),
	kwallet = dbConnect(
		MySQL(),
		host = config.authentication.profile[["kwallet_host"]],
		user = config.authentication.profile[["kwallet_user"]],
		password = getKWalletPassword(
			config.authentication.profile[["kwallet_wallet"]],
			config.authentication.profile[["kwallet_folder"]],
			generateKWalletKey(config.authentication.profile[["kwallet_host"]], config.authentication.profile[["kwallet_user"]])
		)
	)
)

lapply(
	list.fcs.all.indexed, 
	function(fcs.current) {

		# Read the custom barcode keyword.
		#
		if(is.null(fcs.current$description[["INDEX SORTING PLATE BARCODE"]])) {
			stop(paste("File ",fcs.current$file, " does not contain an INDEX SORTING PLATE BARCODE key. Aborting!", sep=""))
		} else {
			fcs.barcode <- fcs.current$description[["INDEX SORTING PLATE BARCODE"]]
		}

		# Read the parameters, names and display hints from the metainfo. Note that only "$PxN" (termed 'parameter' here) is mandatory according to
		# to FCS3.1
		#
		parameter.col.order <- c("detector_name","detector_scale","detector_spec","detector_voltage","marker_name","marker_fluorochrome")
		fcs.parameters <- matrix(
			unlist(
				lapply(
					seq(1, as.integer(fcs.current$description[["$PAR"]])),
					function(para.count) {
						func.keyword.or.na <- function(para.keyword) {
							if(is.null(fcs.current$description[[para.keyword]])) {
								NA
							} else {
								fcs.current$description[[para.keyword]]
							}
						}
						temp.return.vector <- vector()
						temp.return.vector <- c(temp.return.vector, detector_name = func.keyword.or.na(paste("$P",para.count,"N",sep="")))
						temp.return.vector <- c(temp.return.vector, detector_scale = func.keyword.or.na(paste("P",para.count,"DISPLAY",sep="")))
						temp.return.vector <- c(temp.return.vector, detector_voltage = func.keyword.or.na(paste("$P",para.count,"V",sep="")))
						temp.short.name <- func.keyword.or.na(paste("$P",para.count,"S",sep=""))
						if(is.na(temp.short.name)){
							temp.marker.vector <- c(marker_name=NA, marker_fluorochrome=NA, detector_spec=NA)
						} else {
							temp.marker.vector <- unlist(strsplit(temp.short.name, ";"))
							if(length(temp.marker.vector) > length(parameter.col.order) - length(temp.return.vector)) {
								stop(paste("File ",fcs.current$file, " contains to many values in short name of parameter ",para.count,". Aborting!", sep=""))
							} else {
								temp.marker.vector <- c(temp.marker.vector, rep(NA, length(parameter.col.order)-length(temp.return.vector)-length(temp.marker.vector)))
								temp.marker.vector[nchar(temp.marker.vector) == 0] <- NA
								names(temp.marker.vector) <- c("marker_name","marker_fluorochrome","detector_spec")
							}
						}
						return(c(temp.return.vector, temp.marker.vector)[parameter.col.order])
					}
				)
			),
			ncol=length(parameter.col.order),
			byrow=TRUE,
			dimnames=list(NULL, parameter.col.order)
		)

		# Convert time to actual seconds, so that $TIMESTEP does not have to be saved separately
		#
		index.col.time <- grep("TIME", colnames(fcs.current$data), ignore.case=TRUE)
		fcs.timestep <- as.numeric(fcs.current$description[["$TIMESTEP"]])
		if(xor(is.null(index.col.time), is.null(fcs.timestep))) {
			if(is.null(index.col.time)) {
				warning(paste("'Time' parameter is missing although $TIMESTEP keyword is specified in file ", fcs.current$file, ".", sep=""))
			} else {
				warning(paste("$TIMESTEP keyword is not specified, although 'Time' parameter is present in file ", fcs.current$file, ".", sep=""))
			}
		} else {
			if(! is.null(index.col.time)) {
				fcs.current$data[,index.col.time] <- fcs.current$data[,index.col.time] * fcs.timestep
			} else {
				message("No time parameter recorded")
			}
		}


		# Set the current barcode as variable in the database
		#
		dbGetQuery(
			connection.mysql,
			paste("SET @BARCODE := '", fcs.barcode, "';",sep="")
		)

		# Sanity Checks. Test whether
		# - the selected barcode exists at all in the database
		# - there is only a single plate layout per barcode
		# - the plate dimensions saved in the FCS file and the ones in the database are identical
		#
		# CAVE: Code still assumes that every barcoded entry is complete i.e. has a plate_layout_id and a sort_id
		#
		if(
			dbGetQuery(
				connection.mysql,
				paste(
					"SELECT COUNT(event_id) AS events ",
					"FROM ", list.config.global$database,".event ",
					"WHERE plate_barcode = @BARCODE;",
					sep=""
				)
			)[,"events"]
			== 0
		) {
			stop(paste("Barcode ", fcs.barcode, " not found in table \"event\" of database ", list.config.global$database, ".", sep=""))
		}

		plate.layout.id <- dbGetQuery(
			connection.mysql,
			paste(
				"SELECT DISTINCT plate_layout_id ",
				"FROM ", list.config.global$database,".event ",
				"WHERE plate_barcode = @BARCODE;",
				sep=""
			)
		)[, "plate_layout_id"]
		if(length(plate.layout.id) > 1){
			stop(paste("Barcode ", fcs.barcode, " matches to more than one plate layout.", sep=""))
		}

		plate.layout.dimensions <- as.numeric(
			dbGetQuery(
				connection.mysql,
				paste(
					"SELECT n_rows, n_cols ",
					"FROM ", list.config.global$library, ".plate_layout_library ",
					"WHERE plate_layout_id = ", plate.layout.id,
					sep=""
				)
			)
		)
		names(plate.layout.dimensions) <- c("rows","columns")
		if(! all(plate.layout.dimensions == fcs.current$dimensions)) {
			stop(
				paste(
					"Plate ", fcs.barcode, " has different dimensions in FCS [",
					paste(rev(fcs.current$dimensions), collapse=":"), "] and database [",
					paste(rev(plate.layout.dimensions), collapse=":"), "] ([col:row]).",
					sep=""
				)
			)
		}

		# Obtain all sort_ids, iterate through them and check whether their parameters are already in the DB
		#
		sort.ids.all <- dbGetQuery(
			connection.mysql,
			paste(
				"SELECT DISTINCT sort_id ",
				"FROM ", list.config.global$database,".event ",
				"WHERE plate_barcode = @BARCODE;",
				sep=""
			)
		)[, "sort_id"]

		sapply(
			sort.ids.all,
			function(sort.id.current) {

				# Obtain the total number of channels (if any exist already)
				#
				channel.count.total <- dbGetQuery(
					connection.mysql,
					paste(
						"SELECT COUNT(DISTINCT channel_id) AS channels ",
						"FROM ", list.config.global$database,".flow_meta ",
						"WHERE sort_id = ", sort.id.current,
						sep=""
					)
				)[,"channels"]

				if(channel.count.total == 0) {
					temp.string.insert.parameters <- gsub(
						"\'NA\'",
						"NULL",
						paste(
							"(",
							paste(
								apply(
									cbind(fcs.parameters, sort_id=sort.id.current)[,c(parameter.col.order, "sort_id")],
									1,
									function(x){
										paste(
											"\'",
											paste(
												x,
												collapse="\',\'"
											),
											"\'",
											sep=""
										)
									}
								),
								collapse="),("
							),
							");",
							sep=""
						)
					)
					dbGetQuery(
						connection.mysql,
						paste(
							"INSERT INTO ", list.config.global$database,".flow_meta ",
							"(", paste(c(parameter.col.order, "sort_id"), collapse=", ") ,") ",
							"VALUES ", temp.string.insert.parameters,
							sep=""
						)
					)
				} else {
					warning(paste("Parameters already present for plate ", fcs.barcode, " sort_id ", sort.id.current, ". New parameters not inserted.", sep=""))
				}
			}
		)

		sort.events <- dbGetQuery(
			connection.mysql,
			paste(
				"SELECT event_id, well, sort_id ",
				"FROM ", list.config.global$database,".event ",
				"WHERE plate_barcode = @BARCODE;",
				sep=""
			)
		)
		sort.data.combined <- merge(fcs.current$data, sort.events, by.x="event", by.y="well")

		lapply(
			sort(unique(sort.data.combined[,"sort_id"])),
			function(id.sort.current) {
				vector.select.sort.id <- sort.data.combined[,"sort_id"] == id.sort.current
				df.channels <- dbGetQuery(
					connection.mysql,
					paste(
						"SELECT channel_id, detector_name ",
						"FROM ", list.config.global$database,".flow_meta ",
						"WHERE sort_id = ", id.sort.current,
						sep=""
					)
				)
				print(
					paste(
						"Insert barcode ", fcs.barcode, " sort_id ", id.sort.current,
						" event count ", paste(dim(sort.data.combined), collapse=":"),
						sep=""
					)
				)
				apply(
					sort.data.combined[vector.select.sort.id, c("event_id", df.channels[,"detector_name"])],
					1,
					function(event.current){
						temp.string.flow.data <- paste(
							"(\'",
							paste(
								apply(
									matrix(
										c(
											rep(c(t(event.current[1])), length(event.current)-1),
											c(t(event.current[2:length(event.current)])),
											df.channels[,"channel_id"]
										),
										ncol=3
									),
									1,
									function(temp.event){
										paste(
											temp.event,
											collapse="\',\'"
										)
									}
								),
								collapse="\'),(\'"
							),
							"\')",
							sep=""
						)
						dbGetQuery(
							connection.mysql,
							paste(
								"INSERT INTO ", list.config.global$database,".flow ",
								"(event_id, value, channel_id) ",
								"VALUES ", temp.string.flow.data,
								sep=""
							)
						)
					}
				)
			}
		)
	}
)

dbDisconnect(connection.mysql);

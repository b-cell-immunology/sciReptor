# Name:			pipeline_QA.R
# Verson:		0.1.5 (2015-02-08)
# Authors:		Christian Busse, Katharina Imkeller
# Maintainer:	Christian Busse (busse@mpiib-berlin.mpg.de)
# Licence:		AGPL3
# Provides:		This script produces all plots required for quality assurance (QA) of a run.
# Requires:		lib_pipeline_common, lib_pipeline_QA, lib_authentication_common, RMySQL
# Notes:		Running QA on a DB with 500 kReads requires: 1 CPU core for 1 hour, 1 GB / 250 MB
#				network traffic (Rx/Tx), 250 MB / 3.5 GB RAM (ave. / peak), around 80 min. wall clock time
# Changes:		KI Oct 2014: PDFs are now stored in the quality output directory.
#				CB Dec 2014: Handles lacking sequence data for individual loci gracefully, less noisy output
#				CB Feb 2015: config file and output dirs via command line, log levels
#
#
library(RMySQL)
source("lib/lib_pipeline_common.R")
source("lib/lib_pipeline_QA.R")
source("lib/lib_authentication_common.R")

# Set default parameters
#
file.config <- "../config"				# config file
dir.output <- ".."						# base directory for QA output
config.name.run <- NULL					# name of the run to be processed

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
		if(vector.cmd.line[cnt.cmd.line] == "--qadir"){
			dir.output <- vector.cmd.line[cnt.cmd.line + 1]
			cnt.cmd.line <- cnt.cmd.line + 2
			next;
		}
		if(vector.cmd.line[cnt.cmd.line] == "--run"){
			config.name.run <- vector.cmd.line[cnt.cmd.line + 1]
			cnt.cmd.line <- cnt.cmd.line + 2
			next;
		}
		stop(paste("ERROR: pipeline_QA.R: Unknown option:",vector.cmd.line[cnt.cmd.line]))
	}
	if(cnt.cmd.line == length(vector.cmd.line)) {
		warning(paste("WARNING: pipeline_QA.R: Did not parse command line option",vector.cmd.line[cnt.cmd.line]))
	}
}

if(is.null(config.name.run)) {
	stop("ERROR: pipeline_QA.R: run name not specified")
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

# The following lists define loci and directions. The list.config.loci determines which loci will be included in the DB queries. Both lists
# determine which loci or directions will be included in the print-outs.
#
list.config.loci <- list(
	H = "heavy",
	K = "kappa",
	L = "lambda"
)

list.config.directions <- list(
	F = "proximal",
	R = "distal"
)

# The following lists configure certain aspects of the output, but will not influence the content itself 
#

# Which colors used to mark-up loci in mixed plots
#
list.config.colors.locus <- list(
	H = "#FF1F00",
	K = "#009F00",
	L = "#3F3FFF"
)

# Get a DB connection, using the preferred authentication mechanism (defined in $HOME/.my.authentication, defaults to usage of .my.cnf)
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


# === QA Step 1 - Tag Stats and Locus counts ===
#
# Get total locus count for the given run. This is done to make sure that there is not a substantial population of reads that
# is not covered by the loci given in list.config.loci. Currently locus identification is derived from the identified V segment
# and as long as the default E-value threshold of 10 is used it is very unlikely that locus identification should fail.
#
if (config.debug.level >= 3) cat("[pipeline_QA.R][INFO] Entering step 1\n");

df.locus.counts <- func.locus.count(
	connection.mysql = connection.mysql,
	name.database = list.config.global$database,
	name.run = config.name.run
)


# Do the actual database request. This can take a long time (hours), for further information see comment in library_QA.R.
# Parallization has not yet been tested, however one potential problem is the simultanious use of the same DB connection.
#
list.tag.stats <- lapply(
	X = names(list.config.loci),
	FUN = func.tag.stats,
	connection.mysql = connection.mysql,
	name.database = list.config.global$database,
	name.run = config.name.run,
	tag.landing.zone = list.config.global$tag_landing_zone,
	debug.level = config.debug.level
)
names(list.tag.stats) <- sapply(list.tag.stats, function(x){x$locus})

# The output will consist of 3 bargraphs per locus, one showing the readnumbers vs tag identification status and one for 
# each of the tag positions (proximal and distal, showing mutation frequency and mutation types. Note that the "F" and "R"
# taken from list.config.directions are not related to the directionality of the *read*, but pertain to the directionality 
# of the *tag* and therefore correspond to proximal and distal position.
#
#
pdf(file=file.path(dir.output, config.name.run, "QA_out_tag_stats.pdf"), paper="A4r", width=11.7, height=8.27)
par(mfrow = c(3, length(list.tag.stats)),oma=c(1, 0, 1.25, 0))

lapply(
	names(list.tag.stats),
	function(locus.current) {
		nreads.all.total <- sum(list.tag.stats[[locus.current]][["status"]])
		barplot(
			rev(list.tag.stats[[locus.current]][["status"]]) / nreads.all.total,
			main=paste(
				list.config.loci[[locus.current]]," total\n(n=",
				prettyNum(
					nreads.all.total,
					big.mark=",",
					big.interval=3L
				), ")",
				sep=""
			),
			ylim=c(0,1),
			names.arg = c("both tags","proximal only","distal only","no tags"),
			ylab="[%]",
			axes=FALSE
		)
		axis(2, seq(from=0, to=1, by=0.2), seq(from=0, to=100, by=20))

		lapply(
			names(list.config.directions),
			function(direction.current) {
				if(! is.null(list.tag.stats[[locus.current]][[direction.current]])) {
					mutation.strings.all <- names(list.tag.stats[[locus.current]][[direction.current]])
					mutation.strings.mutated <- sort(mutation.strings.all[mutation.strings.all != "no_mutation"])
					if (length(mutation.strings.mutated) > 0) {
						table.mutations <- aggregate(
							list.tag.stats[[locus.current]][[direction.current]][mutation.strings.mutated],
							FUN=sum,
							by=list(nchar(mutation.strings.mutated))
						)
						colnames(table.mutations) <- c("nmutations","nreads")

						nreads.mapped.total <- sum(list.tag.stats[[locus.current]][[direction.current]])
						nreads.mapped.ok <- nreads.mapped.total - sum(table.mutations[,"nreads"])

						matrix.barplot <- matrix(
							c(
								nreads.mapped.ok / nreads.mapped.total,
								table.mutations[,"nreads"] / nreads.mapped.total,
								rep(0, length(mutation.strings.mutated)),
								rep(0, length(table.mutations[,"nreads"])+1),
								list.tag.stats[[locus.current]][[direction.current]][mutation.strings.mutated] / sum(table.mutations[,"nreads"])
							), 
							ncol = 2
						)

						barplot(
							matrix.barplot,
							width=c(1,1),
							space=c(0.1,0.2),
							xlim=c(0,3),
							main=paste(
								list.config.loci[[locus.current]], " ",
								list.config.directions[[direction.current]], "\n",
								"(n=", prettyNum(nreads.mapped.total, big.mark=",", big.interval=3L), "  -  ",
								round(nreads.mapped.total*100/nreads.all.total,1),"% of total)",
								sep=""),
							names.arg = c("all", "mutated"),
							legend.text = c("0", table.mutations[,"nmutations"], toupper(mutation.strings.mutated)),
							args.legend=list(x="topright"),
							ylab="[%]",
							axes=FALSE
						)
						axis(2, seq(from=0, to=1, by=0.2), seq(from=0, to=100, by=20))
					} else {
						nreads.mapped.total <- sum(list.tag.stats[[locus.current]][[direction.current]])
						matrix.barplot <- matrix(c(1,0), ncol = 2)
						barplot(
							matrix.barplot,
							width=c(1,1),
							space=c(0.1,0.2),
							xlim=c(0,3),
							main=paste(
								list.config.loci[[locus.current]], " ",
								list.config.directions[[direction.current]], "\n",
								"(n=", prettyNum(nreads.mapped.total, big.mark=",", big.interval=3L), "  -  ",
								round(nreads.mapped.total*100/nreads.all.total,1),"% of total)",
								sep=""),
							names.arg = c("all", "mutated"),
							legend.text = c("0", "-"),
							args.legend=list(x="topright"),
							ylab="[%]",
							axes=FALSE
						)
						axis(2, seq(from=0, to=1, by=0.2), seq(from=0, to=100, by=20))
						text(1.8, 0.5, labels=c("No data\navailable"), adj=c(0.5,0.5))
					}
				} else {
					plot.new()
					box()
					title(main=paste(list.config.loci[[locus.current]], " ", list.config.directions[[direction.current]], "\n(n=N/A)", sep=""))
					text(0.5, 0.5, labels=c("No data available"), adj=c(0.5,0.5))
				}
			}
		) -> temp.null
	}
) -> temp.null

mtext(
	paste(
		"Pipeline QA for run ", config.name.run, " from database ", list.config.global$database, " on ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
		sep=""
	),
	outer=TRUE,
	side=3,
	font=2
)

# Aggregate the locus counts. Note that 'sum' is an easy way to get around the case distinction of the locus selection vectors being all 'FALSE'.
# This is important since prettyNum cannot handle zero-length vector ('numeric(0)') gracefully.
#
locus.counts.total <- sum(df.locus.counts[,"count"])
locus.counts.unlisted <- sum(df.locus.counts[(! df.locus.counts[,"locus"] %in% c(names(list.config.loci),"NULL")), "count"])
locus.counts.null <- sum(df.locus.counts[df.locus.counts[,"locus"]=="NULL", "count"])

mtext(
	paste(
		"The run contained a total of ", prettyNum(locus.counts.total, big.mark=",", big.interval=3L), " reads of which ",
		prettyNum(locus.counts.null, big.mark=",", big.interval=3L), " failed locus identification and ",
		prettyNum(locus.counts.unlisted, big.mark=",", big.interval=3L), " had a locus not included in the locus list.",
		sep=""
	),
	outer=TRUE,
	side=1
)

dev.off() -> temp.null

if (config.debug.level >= 3) cat("[pipeline_QA.R][INFO] Leaving step 1\n");


# === QA Step 2 - Tag position aggregation ===
#

if (config.debug.level >= 3) cat("[pipeline_QA.R][INFO] Entering step 2\n");

pdf(file=file.path(dir.output, config.name.run, "QA_out_tag_positions.pdf"), paper="A4r", width=11.7, height=8.27)
par(mfcol=c(2, 3),oma=c(1, 0, 1.25, 0))

config.tag.aggregation.range <- 700
config.tag.bin.size <- 10
config.tag.x.ticks <- 8

func.plot.tag.aggregate <- function(direction, aggregate.array, text.main){

	if(missing(text.main) && direction %in% unlist(names(list.config.directions))) {
		text.main <- list.config.directions[[direction]]
	}

	xlab.tick.count <-ifelse(
		config.tag.aggregation.range/config.tag.bin.size==trunc(config.tag.aggregation.range/config.tag.bin.size),
		config.tag.aggregation.range/config.tag.bin.size,
		trunc(config.tag.aggregation.range/config.tag.bin.size)+1
	)
	ylim.max.lin <- max(colSums(t(aggregate.array[[direction]]))) * 1.05
	ylim.max.log <- trunc(log(max(colSums(t(aggregate.array[[direction]]))),10))+1

	barplot(
		t(aggregate.array[[direction]]),
		width=0.8,
		space=0.25,
		col=unlist(list.config.colors.locus[colnames(aggregate.array[[direction]])]),
		ylim=c(0,ylim.max.lin),
		xlab="start position [bp]",
		main=text.main
	)
	axis(
		1,
		seq(from=0, by=xlab.tick.count/(config.tag.x.ticks-1), length.out=xlab.tick.count),
		trunc(seq(from=0, by=xlab.tick.count*config.tag.bin.size/(config.tag.x.ticks-1), length.out=xlab.tick.count))
	)
	abline(v=list.config.global$tag_landing_zone/config.tag.bin.size)
	box()
	legend(
		"topright",
		unlist(list.config.loci[colnames(aggregate.array[[direction]])]),
		fill=unlist(list.config.colors.locus[colnames(aggregate.array[[direction]])]),
		inset=0.01
	)

	matrix.tag.positions.log <- (
		aggregate.array[[direction]] / 
		colSums(t(aggregate.array[[direction]]))) * 
		log(colSums(t(aggregate.array[[direction]]))+1,10
	)
	matrix.tag.positions.log[is.nan(matrix.tag.positions.log)] <- 0

	barplot(
		t(matrix.tag.positions.log),
		axes=FALSE,
		width=0.8,
		space=0.25,
		col=unlist(list.config.colors.locus[colnames(aggregate.array[[direction]])]),
		xlab="start position [bp]",
		ylim=c(0,ylim.max.log)
	)
	axis(
		1,
		seq(from=0, by=xlab.tick.count/(config.tag.x.ticks-1), length.out=xlab.tick.count),
		trunc(seq(from=0, by=xlab.tick.count*config.tag.bin.size/(config.tag.x.ticks-1), length.out=xlab.tick.count))
	)
	axis(2, seq(from=0, to=ylim.max.log), 10^seq(from=0, to=ylim.max.log))
	abline(v=list.config.global$tag_landing_zone/config.tag.bin.size)
	box()

}

list.tag.positions <- lapply(
	unlist(names(list.config.directions)),
	FUN=func.tag.position.aggregate,
	connection.mysql = connection.mysql,
	name.database = list.config.global$database,
	name.run = config.name.run,
	aggregation.range = config.tag.aggregation.range,
	bin.size = config.tag.bin.size
)
names(list.tag.positions) <- unlist(names(list.config.directions))

if(length(list.tag.positions) > 1) {
	temp.array <- matrix(
		rep(0,length(list.tag.positions[[1]])),
		ncol=ncol(list.tag.positions[[1]]),
		dimnames=list(NULL,colnames(list.tag.positions[[1]]))
	)
	for(temp.direction in names(list.tag.positions)){
		temp.col.exist <- colnames(temp.array)[colnames(temp.array) %in% colnames(list.tag.positions[[temp.direction]])]
		temp.array[,temp.col.exist] <- temp.array[,temp.col.exist] + list.tag.positions[[temp.direction]]
	}
	func.plot.tag.aggregate(direction="A", aggregate.array=list(A=temp.array), text.main="all")
	rm(temp.array, temp.direction)
}


lapply(
	names(list.tag.positions),
	FUN=func.plot.tag.aggregate,
	aggregate.array=list.tag.positions
) -> temp.null

mtext(
	paste(
		"Aggregated tag positions for run ", config.name.run, " from database ", list.config.global$database, " on ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
		sep=""
	),
	outer=TRUE,
	side=3,
	font=2
)

dev.off() -> temp.null

if (config.debug.level >= 3) cat("[pipeline_QA.R][INFO] Leaving step 2\n");


# === QA Step 3 - Reads per well ===
#

if (config.debug.level >= 3) cat("[pipeline_QA.R][INFO] Entering step 3\n");

pdf(file=file.path(dir.output, config.name.run, "QA_out_reads_per_well.pdf"), paper="A4r", width=11.7, height=8.27)
par(mfcol=c(2, 3), oma=c(1, 0, 1.25, 0))

lapply(
	names(list.config.loci),
	FUN=function(locus.current) {
		reads.well.all <- func.reads.well(
			connection.mysql = connection.mysql,
			name.database = list.config.global$database,
			name.run = config.name.run,
			locus = locus.current
		)

		reads.well.consensus.1 <- func.reads.well(
			connection.mysql = connection.mysql,
			name.database = list.config.global$database,
			name.run = config.name.run,
			locus = locus.current,
			consensus.rank = 1
		)

		reads.well.consensus.2 <- func.reads.well(
			connection.mysql = connection.mysql,
			name.database = list.config.global$database,
			name.run = config.name.run,
			locus = locus.current,
			consensus.rank = 2
		)

		if (length(reads.well.all) > 0) {
		
			config.histbreaks <- seq(
				from = -1,
				to = max(reads.well.all) + list.config.global$n_consensus - 1,
				by = list.config.global$n_consensus
			)

			hist.reads.well.all <- hist(reads.well.all, breaks=config.histbreaks, main=list.config.loci[[locus.current]], xlab="reads/wells", ylab="wells")

			if (length(reads.well.consensus.1) > 0) {
				hist.reads.well.consensus.1 <- hist(reads.well.consensus.1, breaks=config.histbreaks, plot=FALSE)
				lines(hist.reads.well.consensus.1$mids[-1], hist.reads.well.consensus.1$counts[-1], col='red')
			} else {
				abline(h=0,col='red')
			}

			if (length(reads.well.consensus.2) > 0) {
				hist.reads.well.consensus.2 <- hist(reads.well.consensus.2, breaks=config.histbreaks, plot=FALSE)
				lines(hist.reads.well.consensus.2$mids[-1], hist.reads.well.consensus.2$counts[-1], col='blue')
			} else {
				abline(h=0,col='blue')
			}

			legend("topright", c("1st consensus", "2nd consensus"), fill=c('red', 'blue'))
		
			plot(
				hist.reads.well.all$mids - hist.reads.well.all$mids[1],
				cumsum(hist.reads.well.all$counts)/sum(hist.reads.well.all$counts),
				type = 'l',
				yaxs='i',
				xaxs='i',
				ylim=c(0,1),
				ylab="cumulated wells",
				xlab="reads/well"
			)
			abline(v=list.config.global$n_consensus)
		} else {
			plot.new()
			box()
                        title(main=list.config.loci[[locus.current]])
                        text(0.5, 0.5, labels=c("No data available"), adj=c(0.5,0.5))

			plot.new()
			box()
                        title(main=list.config.loci[[locus.current]])
                        text(0.5, 0.5, labels=c("No data available"), adj=c(0.5,0.5))
		}
	}
) -> temp.null

mtext(
	paste(
		"Reads per well for run ", config.name.run, " from database ", list.config.global$database, " on ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
		sep=""
	),
	outer=TRUE,
	side=3,
	font=2
)

dev.off() -> temp.null

if (config.debug.level >= 3) cat("[pipeline_QA.R][INFO] Leaving step 3\n");


# === QA Step 4 - Raw readlength and quality values ===
#

if (config.debug.level >= 3) cat("[pipeline_QA.R][INFO] Entering step 4\n");

pdf(file=file.path(dir.output, config.name.run, "QA_out_along_bp.pdf"), paper="A4r", width=11.7, height=8.27)
par(mfrow=c(2, 3),oma=c(1, 0, 1.25, 0), mar=c(5, 4, 4, 4) + 0.1)

lapply(
	names(list.config.loci),
	FUN=function(locus.current) {
		df.length.quality <- func.qual.length(
			connection.mysql = connection.mysql,
			name.database = list.config.global$database,
			name.run = config.name.run,
			locus = locus.current
		)

		if (length(df.length.quality) > 0) {
			plot(
				c(1:length(df.length.quality$length)),
				df.length.quality$length,
				type='l',
				xlab="position [bp]",
				ylab="reads",
				main=paste(
					list.config.loci[[locus.current]], " ",
					"(n=", prettyNum(sum(df.length.quality$length), big.mark=",", big.interval=3L), ")",
					sep=""
				)
			)
			polygon(
				c(1:length(df.length.quality$length)),
				df.length.quality$length,
				col=unlist(list.config.colors.locus[locus.current]),
				border=NA
			)

			ylim.quality.max <- (trunc(max(df.length.quality$quality, na.rm = TRUE)/10)+1)*10
			ylim.quality.scaling <- max(df.length.quality$length, na.rm = TRUE) / ylim.quality.max

			lines(df.length.quality$quality * ylim.quality.scaling)
			axis(
				4,
				seq(from=0 ,to=ylim.quality.max, length.out=5) * ylim.quality.scaling,
				seq(from=0 ,to=ylim.quality.max, length.out=5)
			)
			mtext("mean quality", side=4, line=2, cex=0.67)
			box()
		} else {
			plot.new()
			box()
                        title(main=paste(list.config.loci[[locus.current]]," (n=0)",sep=""))
                        text(0.5, 0.5, labels=c("No data available"), adj=c(0.5,0.5))
		}
	}
) -> temp.null

mtext(
	paste(
		"Read lengths and average quality for run ", config.name.run, " from database ", list.config.global$database, " on ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
		sep=""
	),
	outer=TRUE,
	side=3,
	font=2
)

dev.off() -> temp.null

if (config.debug.level >= 3) cat("[pipeline_QA.R][INFO] Leaving step 4\n");


# Clean-up and exit
#

dbDisconnect(connection.mysql)

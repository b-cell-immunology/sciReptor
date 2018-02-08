# Name:			lib_flowcyt_sorting_indexed.R
# Verson:		0.1.2  (2015-07-21)
# Author(s):	Christian Busse
# Maintainer:	Christian Busse (christian.busse@dkfz-heidelberg.de)
# Licence:		AGPL3
# Provides:		Functions to read index sort location data along with the flow cytometric parameters from FCS files produced by BD's 
#				FACSDiVa software (Versions 7 and 8 should work, but only 8 is tested). The evalulated keywords are not standardized
#				up to FCS3.1, therefore data from non-BD machines/software will most likely not work.
#				Please note: BD's Sortware software uses a completely different approach to record index sort data and is therefore
#				currently not supported.
# Requires:		Bioconductor flowCore package
# 
#

library(flowCore)

# Defines the supported versions of FCS files
#
config.fcs.versions.valid			<- c("FCS2.0","FCS3.0","FCS3.1")
config.fcs.versions.supported		<- c("FCS2.0","FCS3.0","FCS3.1")
config.software.identifier.keywords	<- c("CREATOR","APPLICATION")
config.software.whitelist <- c("BD FACSDiva Software Version 8.0", "BD FACSDiva Software Version 8.0.1")
config.software.blacklist <- c("BD FACS<e2><84><a2> Sortware 1.2.0.142")

# Call:			func.read.indexed.FCS(filename)
#
# Parameters:	<filename>:							Complete filename (if necessary including path) of the FCS file
#
# Returns:		A list containing the following elements:
#				- "file"        [string]	The filename of the FCS (Note that this is the current filename, not the one stored in the $FIL keyword)
#				- "fcs.version" [string]	The "FCSx.y" version string of the file
#				- "dimensions"  [vector]	The dimensions of the target plate as stored in "INDEX SORTING DEVICE_DIMENSION". First value is rows, second columns.
#				- "keyword"		[matrix]	The list of keywords.
#				- "data"		[matrix]	The flow cytometric anf location data for all $TOT events in the file ($PAR + 3 columns). Note that "row" and "column"
#											are real coordinates NOT offsets to well A01. "events" are counted from A01 left-to-right, then top-to-bottom.
#
# Description:	This function reads an FCS file containing index sort data and returns a list data structure containing flow cytometric and location data.
#
func.read.indexed.FCS <- function(fcs.file.full, debug.level) {

    if(missing(debug.level)) {
		debug.level <- 2
	}

	# Sanity checks 1. There is no flowCore internal function to test for the actual FCS version, therefore this information is retrieved
	# via a direct read (which is basically the same thing that isFCSfile() does). As of 06/2015, index sorting data is not specified in the current FCS 3.1 standard,
	# which might result in isolated problems in the processing of index information. Therefore there is a two-stage test plus the check of flowCore support for a given
	# FCS version. However, it seems like there is hardly any difference in the way how FACSDiva writtes FCS 3.0 and 3.1 files, therefore no compatibility problem were
	# found (yet).
	#
	if( ! file.exists(fcs.file.full)) {
		internal.func.logging(paste("File \"", fcs.file.full, "\" does not exist.", sep=""), 0, debug.level)
		return(list())
	}
	fcs.version <- readChar(fcs.file.full, 6)
	if( ! fcs.version %in% config.fcs.versions.supported) {
		if(fcs.version %in% config.fcs.versions.valid) {
			internal.func.logging(paste("File \"", fcs.file.full, "\" uses currently unsupported FCS version ", fcs.version, ".", sep=""), 1, debug.level)
			internal.func.logging(paste("Current flowCore support for this FCS version is ", as.character(unname(isFCSfile(fcs.file.full))[1]), ".", sep=""), 3, debug.level)
			return(list())
		} else {
			internal.func.logging(paste("File \"", fcs.file.full, "\" is not a valid FCS file.", sep=""), 1, debug.level)
			return(list())
		}
	}
	fcs.data <- read.FCS(fcs.file.full)


	# Sanity checks 2. The current version of the FCS format does not specify a way to handle index sort data. In addition, BD has two different sorter
	# applications (FACSDiva and Sortware), which use completely different ways to store index data. Finally, files might have been recorded during an
	# index sort without actually containing index sort location data. Until further information is provided from BD, the testing for the
	# "INDEX SORT DEVICE TYPE" and "INDEX SORT SORTED LOCATION COUNT" seems to be the most reliable option to sort this out.
	#
	fcs.keyword.software.all<-description(fcs.data)[names(description(fcs.data)) %in% config.software.identifier.keywords]
	if (length(fcs.keyword.software.all) > 1) {
		if (length(fcs.keyword.software.all) == rle(unlist(unname(fcs.keyword.software.all)))$length[1]) {
			fcs.keyword.software.current <- names(fcs.keyword.software.all)[1]
		} else {
			stop(paste(
				"File ",
				fcs.file.full,
				" contains multiple software identfier keywords with non-identical values (keywords: ",
				paste(names(fcs.keyword.software.all),collapse=", "),
				") Aborting!",
				sep=""
			))
		}
	} else {
		if (length(fcs.keyword.software.all) < 1) {
			stop(paste("File ",fcs.file.full, " does not contain a valid software identfier keyword.", sep=""))
		} else {
			fcs.keyword.software.current <- names(fcs.keyword.software.all)[1]
		 }
	}

	fcs.value.software.current <- description(fcs.data)[[fcs.keyword.software.current]]
	if (fcs.value.software.current %in% config.software.blacklist) {
		stop(paste(
			"File ", fcs.file.full, " was generated by blacklisted \"", fcs.keyword.software.current, "\"=\"", fcs.value.software.current, "\".",
			sep=""
		))
	}
	if (! description(fcs.data)[[fcs.keyword.software.current]] %in% config.software.whitelist) {
		warning(paste(
			"File ", fcs.file.full, " was generated by \"", fcs.keyword.software.current, "\"=\"", fcs.value.software.current,
			"\", which is NOT on the whitelist.",
			sep=""
		))
	}


	if(is.null(description(fcs.data)$"INDEX SORTING SORTED LOCATION COUNT")) {
		if(is.null(description(fcs.data)$"INDEX SORTING DEVICE TYPE")) {
			stop(paste("File ",fcs.file.full, " does not contain index sort data. Aborting!", sep=""))
		} else {
			stop(paste("File ",fcs.file.full, " does contain some index sort data but no location information. Aborting!", sep=""))
		}
	}

	fcs.index.sorting.sorted.location.count <- as.integer(description(fcs.data)$"INDEX SORTING SORTED LOCATION COUNT")

	if(fcs.index.sorting.sorted.location.count != as.integer(description(fcs.data)$"$TOT")) {
		stop(
			paste(
				"File ", fcs.file.full, " has non-identical counts for total (n=", as.integer(description(fcs.data)$"$TOT"),
				") versus sorted events (n=", fcs.index.sorting.sorted.location.count,
				"). Aborting!",
				sep=""
			)
		)
	}

	if (nrow(exprs(fcs.data)) != fcs.index.sorting.sorted.location.count) {
		stop(
			paste(
				"Number of entries in the raw data table (n=", nrow(exprs(fcs.data)),
				") in file ", fcs.file.full, " does not match the number of sorted cells (n=", fcs.index.sorting.sorted.location.count,"). Aborting!",
				sep=""
			)
		)
	}

	# Get metainfo on the type and size of the sorting device.
	# ATTENTION: The device definition in BD FACSDiVa software is transposed (rows x columns) in comparision to the "normal" plate format (columns x rows).
	# However this is only true for the device definition, the index sorting information are in a "<column_offset>,<row_offset>;" format.
	#
	fcs.index.sorting.device.type <- as.integer(description(fcs.data)$"INDEX SORTING DEVICE TYPE")
	fcs.index.sorting.device.dimension <- as.integer(unlist(strsplit(description(fcs.data)$"INDEX SORTING DEVICE_DIMENSION",":")))
	names(fcs.index.sorting.device.dimension) <- c("rows","columns")


	# Parse INDEX SORTING LOCATION data into a single table. The information of order in the metainfo has to be stored since it is the only way
	# to associate the location data with the cytometry data.
	# The transposition of the lapply output and the "byrow" of the following matrix command are necessary since the number of locations given
	# in one line of the INDEX SORTING LOCATIONS metainfo varies. Further note that the values in the metainfo are offsets to well A01, therefore
	# all numbers are incremented by one to obtain the row / column number.
	#
	fcs.index.sorting.wells <- matrix(
		unlist(
			lapply(
				grep("INDEX SORTING LOCATIONS", names(description(fcs.data)),value=TRUE), 
				function(fcs.index.sorting.location.current) {
					temp.sorting.locations <- matrix(
						as.integer(
							unlist(
								strsplit(
									unlist(
										strsplit(
											description(fcs.data)[[fcs.index.sorting.location.current]],
											";"
										)
									),
									","
								)
							)
						) + 1,
						ncol=2,
						byrow=TRUE,
						dimnames=list(NULL,c("row", "column"))
					)
					temp.sorting.locations <- cbind(
						temp.sorting.locations,
						matrix(
							c(
								(temp.sorting.locations[,"row"]-1) * fcs.index.sorting.device.dimension["columns"] + temp.sorting.locations[,"column"],
								rep(as.integer(sub("^INDEX\ SORTING\ LOCATIONS_","",fcs.index.sorting.location.current)), dim(temp.sorting.locations)[1]),
								seq(1,dim(temp.sorting.locations)[1])
							),
							ncol=3,
							dimnames=list(NULL,c("event","line","element"))
						)
					)
					t(temp.sorting.locations)
				}
			)
		),
		ncol=5,
		byrow=TRUE,
		dimnames=list(NULL,c("row", "column","event","line","element"))
	)

	# Sanity checks 3. Test whether:
	# - there are any line+element combinations that are non-unique
	# - index sorting locations are outside of the dimensions of the device
	# - there are any column+row combinations that are non-unique
	# - there are any event numbers that are non-unique
	# - the number of parsed locations is identical to the number of recorded cells
	#
	if (any(duplicated(paste(fcs.index.sorting.wells[,"line"],fcs.index.sorting.wells[,"element"],sep="_")))) {
		stop(
			paste(
				"Collision in lines and elements parsed from the INDEX SORTING LOCATIONS of file ", fcs.file.full, ". Aborting!",
				sep=""
			)
		)
	}

	if ( 
		max(fcs.index.sorting.wells[,"row"]) > fcs.index.sorting.device.dimension["rows"] || min(fcs.index.sorting.wells[,"row"]) < 1 ||
		max(fcs.index.sorting.wells[,"column"]) > fcs.index.sorting.device.dimension["columns"] || min(fcs.index.sorting.wells[,"column"]) < 1
	) {
		stop(
			paste(
				"Index sorting locations (",
				min(fcs.index.sorting.wells[,"column"]), ">", max(fcs.index.sorting.wells[,"column"]),
				":",
				min(fcs.index.sorting.wells[,"row"]), ">", max(fcs.index.sorting.wells[,"row"]),
				") in file ",
				fcs.file.full,
				"are outside of device dimensions (", fcs.index.sorting.device.dimension["columns"], ":", fcs.index.sorting.device.dimension["rows"],
				"). Aborting!",
				sep=""
			)
		)
	}

	if (any(duplicated(paste(fcs.index.sorting.wells[,"row"],fcs.index.sorting.wells[,"column"],sep="_")))) {
		stop(
			paste(
				"Collision in columns and rows parsed from the INDEX SORTING LOCATIONS of file ", fcs.file.full, ". Aborting!",
				sep=""
			)
		)
	}

	if (any(duplicated(fcs.index.sorting.wells[,"event"]))) {
		stop(
			paste(
				"Collision in event numbers calculated from the INDEX SORTING LOCATIONS of file ", fcs.file.full, ". Aborting!",
				sep=""
			)
		)
	}

	if (nrow(fcs.index.sorting.wells) != fcs.index.sorting.sorted.location.count) {
		stop(
			paste(
				"Number of parsed INDEX SORTING LOCATIONS (n=", nrow(fcs.index.sorting.wells),
				") in file ", fcs.file.full, " does not match the number of sorted events (n=", fcs.index.sorting.sorted.location.count,"). Aborting!",
				sep=""
			)
		)
	}

	# Combine cytometry and location data. This requires that the location data is ordered according to the sequence in which the cells were sorted.
	#
	fcs.index.sorting.wells <- fcs.index.sorting.wells[order(fcs.index.sorting.wells[,"line"],fcs.index.sorting.wells[,"element"]),]
	
	if(is.null(description(fcs.data)$SPILL)) {
		warning(paste("File ",fcs.file.full, " lacks $SPILL compensation matrix. Skipping compensation!", sep=""))
		fcs.data.export <- exprs(fcs.data)
	} else {
		fcs.data.export <- exprs(compensate(fcs.data, description(fcs.data)$SPILL))
	}
	fcs.data.export <- cbind(
		fcs.data.export,
		fcs.index.sorting.wells[,c("event","row","column")]
	)

	fcs.data.export <- fcs.data.export[order(fcs.data.export[,"event"]),]


	return(
		list(
			file=fcs.file.full,
			fcs.version=fcs.version,
			dimensions=fcs.index.sorting.device.dimension,
			description=description(fcs.data),
			data=fcs.data.export
		)
	)
}

internal.func.logging<-function(log.message, log.severity, log.level){
	lut.severity <- c("FATAL","ERROR","WARNING","INFO","DEBUG","DEBUG+")
	if(log.severity <= log.level){
		cat(
			paste(
				"[lib_flowcyt_sorting_indexed.R][",
				lut.severity[log.severity+1],
				"] ",
				log.message,
				"\n",
				sep=""
			)
		)
	}
}

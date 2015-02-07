# Name:			lib_pipeline_common.R
# Verson:		0.2.1 (2015-02-07)
# Authors:		Christian Busse, Katharina Imkeller
# Maintainer:	Christian Busse (busse@mpiib-berlin.mpg.de)
# Licence:		AGPL3
# Provides:		This library provides general functions for the evaluation pipeline.
# Requires:		nothing
# 
#

# Call:			func.read.config(file.name)
#
# Parameters:	<file.name>:	name of the config file
# Returns:		A list containing all active (i.e. non-commented) key-value pairs given in the config file. Numeric values
#				are returned as such, everything else is returned as string.
# Description:	This function reads a config file that follows a <key>=<value> format, trailing spaces and semicolons will be removed.
#				The keys are expected to be bash compatible, i.e. that they only contain alphanumeric characters and underscores
#				and do not start with a number. White space characters preceeding and trailing the <key>=<value> pair will be removed.
#				Note that bash requires no spaces directly before or after the "=", therefore these characters will not be trimmed, but 
#				are also not tested for.
#				Variables in curly brackets (e.g. ${FOO}) will be subject to variable expansion, both for keys previously (!) defined
#				in the file and for general enviroment variables, with precedence given to the locally defined keys. Variable without
#				curly brackets (e.g. $FOO) will not be expanded by this script and passed on without modificatioin.
#
func.read.config <- function(file.name) {
	if(file.access(file.name, mode=4)==0){
		connection.file <- file(file.name)
		connection.text <- textConnection(readLines(connection.file))
		table.key.value <-read.table(connection.text, sep="=", comment.char="#")
		close(connection.text)
		close(connection.file)

		colnames(table.key.value) <- c("key", "value")

		# Remove leading and trailing spaces, trailing semicolons and check for unique and valid keys
		#
		table.key.value[,"key"] <- sub("^[[:space:]]*", "", table.key.value[,"key"])
		table.key.value[,"value"] <- sub("[[:space:]]*;$", "", table.key.value[,"value"])

		index.keys.valid <- grepl("^[_A-Za-z][_0-9A-Za-z]+$", table.key.value[,"key"])
		if (! all(index.keys.valid)) {
			stop(paste(
					"Invalid key(s) found in config file:",
					table.key.value[(! index.keys.valid),]
			))
			return(NA)
		}

		index.keys.duplicated <- duplicated(table.key.value[,"key"])
		if (any(index.keys.duplicated)) {
			stop(paste(
					"Duplicated key(s) found in config file:",
					table.key.value[(index.keys.duplicated),]
			))
			return(NA)
		}

		# Perform variable expansion for "curly style" variables as described above. Note that the expansion of locally defined 
		# (i.e. in the same file) keys is strictly "look-behind", i.e. it will only work on keys defined previously/above the current
		# key. This implementation was done to mimic the behavior of a config file when executed as bash script and also to avoid potential
		# issues with circular references.
		#
		table.key.value.expanded <- t(sapply(
			as.list(table.key.value[,"key"]),
			FUN=function(key.current){
				index.key.current <- match(key.current, table.key.value[,"key"])
				value.current <- table.key.value[index.key.current, "value"]
				re.match <- gregexpr("\\$\\{[_A-Za-z][_0-9A-Za-z]+\\}", value.current)
				re.length <- attr(re.match[[1]],"match.length")
				attributes(re.match[[1]])<-NULL
				re.start.pos <- re.match[[1]]

				if(re.start.pos[1] > 0) {
					# The positions match the whole variable ${FOO}, but only the actual name FOO is interesting -> clip
					temp.variables <- substr(rep(value.current,length(re.start.pos)), re.start.pos+2, re.start.pos+re.length-2)
					temp.replacements <- sapply(
						as.list(temp.variables),
						FUN=function(var.current) {
							expanded <- ""
							if ((index.key.current > 1) && (var.current %in% (table.key.value[1:(index.key.current-1), "key"]))) {
								expanded <- table.key.value[match(var.current, table.key.value[1:(index.key.current-1), "key"]), "value"]
							} else {
								if (length(Sys.getenv(var.current)) > 0) {
									expanded <- Sys.getenv(var.current)
								}
							}
							return(expanded)
						}
					)

					for(cnt.replace in 1:length(temp.replacements)) {
						value.current<-sub(
							paste("\\$\\{", temp.variables[cnt.replace],"\\}",sep=""),
							temp.replacements[cnt.replace],
							value.current
						)
					}
				}
				return(c(key.current, value.current))
			}
		))
		colnames(table.key.value.expanded) <- c("key", "value")

		temp.list <- suppressWarnings(
			lapply(
				as.list(table.key.value.expanded[,"value"]),
				FUN=function(x){
					ifelse(
						is.na(as.numeric(x)),
						x,
						as.numeric(x)
					)
				}
			)
		)
		names(temp.list) <- table.key.value.expanded[,"key"]

		return(temp.list)

	} else {
		stop(paste("Config file '", file.name, "' does not exist or is not readable!", sep=""))
		return(NA)
	}
}

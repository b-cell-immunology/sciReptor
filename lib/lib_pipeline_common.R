# Name:			lib_pipeline_common.R
# Verson:		0.2 (2014-06-01)
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
# Description:	This function reads a config file that follows a <key>=<value> format, trailing semicolons (';') will be removed.
#
func.read.config <- function(file.name) {
	if(file.access(file.name, mode=4)==0){
		connection.file <- file(file.name)
		connection.text <- textConnection(readLines(connection.file))
		temp.table<-read.table(connection.text, sep="=", comment.char="#")
		close(connection.text)
		close(connection.file)

		colnames(temp.table) <- c("key", "value")
		temp.table[,"value"] <- sub(";$", "", temp.table[,"value"])

		temp.list <- suppressWarnings(
			lapply(
				as.list(temp.table[,"value"]),
				FUN=function(x){
					ifelse(
						is.na(as.numeric(x)),
						x,
						as.numeric(x)
					)
				}
			)
		)
		names(temp.list) <- temp.table[,"key"]

		return(temp.list)

	} else {
		stop(paste("Config file '", file.name, "' does not exist or is not readable!", sep=""))
		return(NA)
	}
}

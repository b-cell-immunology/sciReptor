func.read.config <- function(file.name) {
	connection <- file(file.name)
	lines<-readLines(connection)
	close(connection)
	connection<-textConnection(lines)
	temp.table<-read.table(connection,sep="=")
	close(connection)
	colnames(temp.table) <- c("key","value")
	temp.table[,"value"] <- sub(";$","", temp.table[,"value"])
	temp.list<-as.list(temp.table[,"value"])
	names(temp.list) <- temp.table[,"key"]
	return(temp.list)
}

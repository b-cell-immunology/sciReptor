#!/bin/bash

# SYNOPSIS
# perform_igblast.sh <query_fasta> <outfile>
#
# DESCRIPTION
# do IgBLAST on a set of fasta sequences, Version 2.2.28+
# Special output options including alignments
#
# LOGGED INFORMATION
# - none (bcelldb_logger removed Oct 2014, in order to reduce number of entries in log table)
#
# AUTHOR
# Katharina Imkeller - imkeller@mpiib-berlin.mpg.de
#
# HISTORY
# Written Jan 2014
# Added alignments in output March 2014
# Modified to have DB files configurable via ./config file. January 2015 - CEB

query_file=$1;
out_file=$2;

# read config and set general path to database folder
#
source ../config
export IGDATA
export BLASTDB=${IGDATA}

igblastn \
	-germline_db_V $blastdb_segments_V \
	-germline_db_D $blastdb_segments_D \
	-germline_db_J $blastdb_segments_J \
	-organism $species \
	-auxiliary_data optional_file/${species}_gl.aux \
	-query $query_file \
	-outfmt '7 qseqid sseqid pident length mismatch gapopen qstart qend sstart send
		evalue bitscore qseq sseq frames qframe' \
	-num_alignments_V $num_V -num_alignments_D $num_D -num_alignments_J  $num_J \
	-num_alignments $num_align_igblast \
	> $out_file;

# log the process to db
# perl bcelldb_logger.pl "run IgBLAST.sh with\ninfile: $query_file\noutfile: $out_file":

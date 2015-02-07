#!/bin/bash

# SYNOPSIS
# perform_blast.sh <query_fasta> <outfile>
#
# DESCRIPTION
# run BLASTN on a set of fasta sequences against the human or mouse constant Ig segment database (NCBI)
#
# LOGGED INFORMATION
# - none (bcelldb_logger removed Oct 2014 to reduce nb of entries in log table)
#
# AUTHOR
# Katharina Imkeller - imkeller@mpiib-berlin.mpg.de
#
# HISTORY
# Written Jan 2014
# Modified to have DB files configurable via ./config file. January 2015 - CEB

query_file=$1;
out_file=$2;

# read config and set general path to database folder
#
source ../config
export BLASTDB=$IGDATA

blastn \
    -db $blastdb_segment_C \
    -query $query_file \
	-out $out_file \
    -outfmt $out_format_blast \
    -num_alignments $num_align_blast \
    ;

# log the process to db
#perl bcelldb_logger.pl "run BLAST.sh with\n \
#infile: $query_file\n \
#outfile: $out_file\n \
#Organism is $organism.\n";

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


source ../config

# path needed for BLAST to find database
# this is strange, but necessary
export BLASTDB=$IGDATA

query_file=$1;
out_file=$2;

if [ "$species" = "human" ] 
then
	database="database/hIGH-K-L_constant_exon1.fasta";
elif [ "$species" = "mouse" ] 
then
	database="database/mIgXc.fa";
else
	echo "species must be human or mouse";
fi

blastn \
    -db $database \
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

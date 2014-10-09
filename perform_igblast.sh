#!/bin/bash

# SYNOPSIS
# perform_igblast.sh <query_fasta> <outfile>
#
# DESCRIPTION
# do IgBLAST on a set of fasta sequences, Version 2.2.28+
# Special outpout options including alignments
#
# LOGGED INFORMATION
# - query file
# - outfile
#
# AUTHOR
# Katharina Imkeller - imkeller@mpiib-berlin.mpg.de
#
# HISTORY
# Written Jan 2014
# Added alignments in output March 2014


source ../config
export IGDATA

query_file=$1;
out_file=$2;

if [ "$species" = "human" ] 
then
database_V="database/human_gl_V";
database_D="database/human_gl_D";
database_J="database/human_gl_J";
organism="human";
aux_file="optional_file/human_gl.aux";
elif [ "$species" = "mouse" ]
then
database_V="database/Ig-V_segments_position_corrected.fasta";
database_D="database/Ig-D_segments_position_corrected.fasta";
database_J="database/Ig-J_segments_position_corrected.fasta";
organism="mouse";
aux_file="optional_file/mouse_gl.aux";
else
echo "species must be human or mouse";
fi

$blast_path/igblastn \
	-germline_db_V $IGDATA/$database_V \
	-germline_db_D $IGDATA/$database_D \
	-germline_db_J $IGDATA/$database_J \
	-organism $organism \
	-auxiliary_data $aux_file \
	-query $query_file \
	-outfmt '7 qseqid sseqid pident length mismatch gapopen qstart qend sstart send
   evalue bitscore qseq sseq frames qframe'\
	-num_alignments_V $num_V -num_alignments_D $num_D -num_alignments_J  $num_J \
	-num_alignments $num_align_igblast \
	> $out_file;

# log the process to db
perl bcelldb_logger.pl "run IgBLAST.sh with\ninfile: $query_file\noutfile: $out_file":


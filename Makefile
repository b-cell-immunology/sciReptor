# 
# MAKEFILE FOR 454 PYROSEQUENCING DATA
#
# This file sets up the rules (programming language 'make'), how different pipeline outputs depend on each other.
# 
# Arguments:
# 	- run
# 		name of the subdirectory, where you store the corresponding raw data, equivalent to sequencing run
# 		e.g.: D1_1sthalf_run1
# 	- experiment_id
# 		corresponding to the id of the matrix experiment
# 		e.g. D1	
#
#
# WORK FLOW FOR USE:
#
# First step on command line:
# 	> make init-env run=<runname>
#
# Second step manually
# 	- put raw data into ../raw_data/<run>/ 
# 		<XXX>.fasta
# 		<XXX>.fasta.qual
# 	- include a sequencing run info for every single fasta file 
# 		<XXX>.fasta.info
# 	- include metainformation
# 		<experiment_id>_metainfo.csv
# 		<experiment_id>_plate.csv
# 	
# Third step on command line:
# 	> make all run=<runname> experiment_id=<experiment_id>
# 	The experiment_id will be used as part of the unique identifier for the consensi. For each experiment_id, all sequences
# 	belonging to one well and one locus will be put together in a consensus.
#
#

#####
##### Initializing directories
#####

# project root is one directory further up then bin
project_root=..
# pipeline output, separated by sequencing run
dir=$(project_root)/pipeline_output/$(run)
# raw data, separated by sequencing run
raw_data=$(project_root)/raw_data/$(run)
# folder for quality control
quality_control=$(project_root)/quality_control/$(run)


#####
##### Defining files that will be generated during processing
#####

# split the data into N fatsa, igout, blout,.... files
N = 68
n = $(filter-out $(N),$(shell seq 0 1 $(N)))

# raw data INFILES
raw_files = $(wildcard $(raw_data)/*.fasta)
todb_reads_files = $(patsubst %.fasta,%.todb_reads_done,$(raw_files))

# files for READS
rfasta_files =  $(foreach k,$(n),$(dir)/$(N)_$(k).rfasta)
rigout_files = $(patsubst %.rfasta,%.rigout,$(rfasta_files))
rblout_files = $(patsubst %.rfasta,%.rblout,$(rfasta_files))
razers_files = $(patsubst %.rfasta,%.rrzout,$(rfasta_files))

# files for CONSENSUS
cfasta_files = $(wildcard $(dir)/cons_*_seqs.cfasta)
caln_files = $(patsubst %.cfasta, %.caln, $(cfasta_files))

# files for SEQUENCES
sfasta_files =  $(foreach k,$(n),$(dir)/$(N)_$(k).sfasta)
sigout_files = $(patsubst %.sfasta,%.sigout,$(sfasta_files))
sblout_files = $(patsubst %.sfasta,%.sblout,$(sfasta_files))



#####
##### Main rules for PHASE1 and PHASE2
##### Process needs to be split into two phases (i.e. recursive calling of make), 
##### because at the start, it is not clear yet how the consenusu files will look like.
##### PHASE1 ends with redefining sfasta and related files.
#####

all: PHASE2

# PHASE 2 starts, after the fasta files for alignment have been generated
# otherwise, make does not know which files belong to *.cfasta and *.caln
PHASE2: PHASE1
	$(MAKE) $(dir)/consensusfasta.done $(dir)/metainfotodb.done $(dir)/cdrfwrtodb.done $(dir)/allsigout.done $(dir)/allsblout.done $(dir)/igblastalignments.done $(dir)/mutations.done $(dir)/qualitycheck.done
	touch $@
	
# PHASE 1 does everything up to generating the *.caln files to db	
PHASE1: 
	$(MAKE) $(dir)/allaligntodb.done



#####
##### PHASE2 targets
#####

$(dir)/qualitycheck.done: $(dir)/allsigout.done
	Rscript pipeline_QA.R $(run)


# upload metainformation
# DONT FORGET to put the plate and metainfo to the raw_data directory
$(dir)/metainfotodb.done: $(dir)/mutations.done
	./todb_sampleinfo_highth.pl -p $(raw_data)/*_plate.csv -m $(raw_data)/*_metainfo.csv -pb $(raw_data)/*_platebarcode.csv
	Rscript todb_flow.R $(run)
	./create_spatials.py $(experiment_id) $(run)
	touch $@

# when igblast alignments uploaded, calculate mutations on all output files
$(dir)/mutations.done: $(dir)/igblastalignments.done mutation_matrix.txt
	./todb_mutations_from_align.pl -dir $(dir)
	touch $@

# create the mutation matrix
mutation_matrix.txt:
	./mutation_matrix.pl

# upload igblast alignments and write aln files to the dir
$(dir)/igblastalignments.done: $(sigout_files) 
	cat $(sigout_files) > $@.x
	./todb_igblast_align.pl -io $@.x -dir $(dir)
	touch $@

# upload CDR_FWR
# there ist still a problem, that not all cdr are found in high throughput
# maybe a problem of mv and touch sigout before
$(dir)/cdrfwrtodb.done: $(sigout_files) $(sfasta_files) $(dir)/allsigout.done
	cat $(sigout_files) > $@.x
	./todb_CDR_FWR.pl -io $@.x
	#rm $@.x
	touch $@

# upload sequence VDJ segments
$(dir)/allsigout.done: $(sigout_files) $(sfasta_files)
	cat $(sigout_files) > $@.x
	./todb_VDJ.pl -t VDJ_segments -io $@.x -ut sequences
	#rm $@.x
	touch $@

# upload sequence constant segments
$(dir)/allsblout.done: $(sblout_files) $(sfasta_files)
	cat $(sblout_files) > $@.x
	./todb_constant.pl -bo $@.x -t constant_segments
	#rm $@.x
	touch $@

# how to generate sequence blout from sfasta
%.sblout: %.sfasta
	./perform_blast.sh $< $@.x
	mv $@.x $@

# how to generate sequence igout from sfasta
%.sigout: %.sfasta
	./perform_igblast.sh $< $@.x
	mv $@.x $@

# how to get an sfasta file
%.sfasta: $(dir)/allaligntodb.done
	./fromdb_fasta.pl -s sequences -t VDJ_segments -f $@.x
	mv $@.x $@


#####
##### PHASE2 targets
#####

# tell that all alignments are in the database
$(dir)/allaligntodb.done: $(dir)/consensusfasta.done   $(caln_files)
	@echo $(MAKEFLAGS)
	@echo $(sfasta_files)
	@echo $(sblout_files)
	touch $@

# how to generate alignment from fasta
%.caln: %.cfasta
	./perform_muscle.pl -f $< -aln $@.x
	mv $@.x $@
	./todb_consensus_sequences.pl -aln $@

# get all the consensus fasta from the database
# only here cfasta and caln variables can be updated
$(dir)/consensusfasta.done: $(dir)/todb_consensus_tags_H.done $(dir)/todb_consensus_tags_K.done $(dir)/todb_consensus_tags_L.done
	./fromdb_consensus_fasta.pl -p $(dir)
	touch $@
	$(eval cfasta_files:=$(wildcard $(dir)/cons_*_seqs.cfasta))
	$(eval caln_files:=$(patsubst %.cfasta, %.caln, $(cfasta_files)))

# distribute consensus ids for this matrix HEAVY
$(dir)/todb_consensus_tags_H.done: $(dir)/allrigout.done $(dir)/allrblout.done $(dir)/allrazers.done
ifndef experiment_id
	@echo "specify the name of the experiment/matrix using experiment_id=<experiment_id>"
	exit 1
endif	
	./todb_consensus_tags.pl -m $(experiment_id) -l H
	touch $@
	
# distribute consensus ids for this matrix KAPPA
$(dir)/todb_consensus_tags_K.done: $(dir)/allrigout.done $(dir)/allrblout.done $(dir)/allrazers.done
ifndef experiment_id
	@echo "specify the name of the experiment/matrix using experiment_id=<experiment_id>"
	exit 1
endif	
	./todb_consensus_tags.pl -m $(experiment_id) -l K
	touch $@
	
# distribute consensus ids for this matrix LAMBDA
$(dir)/todb_consensus_tags_L.done: $(dir)/allrigout.done $(dir)/allrblout.done $(dir)/allrazers.done
ifndef experiment_id
	@echo "specify the name of the experiment/matrix using experiment_id=<experiment_id>"
	exit 1
endif	
	./todb_consensus_tags.pl -m $(experiment_id) -l L
	touch $@

# upload reads VDJ
$(dir)/allrigout.done: $(dir)/alltodb.done $(rigout_files)
	cat $? > $@.x
	mv $@.x $@
	./todb_VDJ.pl -t reads_VDJ_segments -io $@ -ut reads

$(dir)/allrblout.done: $(dir)/alltodb.done $(rblout_files)
	cat $? > $@.x
	mv $@.x $@
	./todb_constant.pl -bo $@ -t reads_constant_segments

$(dir)/allrazers.done: $(dir)/alltodb.done $(razers_files)
	cat $? > $@.x
	mv $@.x $@
	./todb_tags.pl -ro $@

%.rrzout: %.rfasta
	./perform_RazerS.pl -f $< -ro $@.razers
	mv $@.razers $@

%.rblout: %.rfasta
	./perform_blast.sh $< $@.x
	mv $@.x $@

%.rigout: %.rfasta
	./perform_igblast.sh $< $@.x
	mv $@.x $@

%.rfasta: $(dir)/alltodb.done
	./fromdb_fasta.pl -s reads -t reads_VDJ_segments -f $@.x
	mv $@.x $@

$(dir)/alltodb.done: $(todb_reads_files)
	cat $? >$@

%.todb_reads_done: %.fasta
	./todb_reads.pl -f $< -q $<.qual -ri $<.info -m $(experiment_id)
	touch $@



#####
##### targets to initialize or clean up
#####

init-env:
ifndef run
	@echo "specify run using run=<runname>, i.e. subdirectory where raw data is stored"
	exit 1
endif
	mkdir -p $(raw_data)
	mkdir -p $(quality_control)
	mkdir -p $(dir)

	   
clean-data: init-env
	rm -f $(dir)/*
	rm -f $(raw_data)/*_done





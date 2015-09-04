# 
# MAKEFILE FOR MATRIX PCR NGS DATA
#
# This file sets up the rules (programming language 'make'), how different pipeline outputs depend on each other.
# 
# Arguments:
# 	- run
# 		name of the subdirectory, where you store the corresponding raw data, equivalent to sequencing run
# 		e.g.: D01_1sthalf_run1
# 	- experiment_id
# 		corresponding to the id of the matrix experiment
# 		e.g. D01	
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
# 		<experiment_id>_metainfo.tsv
# 		<experiment_id>_plate.tsv
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
# locations for quality control data
quality_base_dir=$(project_root)/quality_control
quality_control=$(project_root)/quality_control/$(run)


#####
##### Defining files that will be generated during processing
#####

# split the data into <num_segments> fasta, igout, blout,.... files
num_segments = 96
n = $(filter-out $(num_segments),$(shell seq 0 1 $(num_segments)))

# File definitions for sffinfo extraction of sequence and qual data
# Note that some of these might be overlapping with other definitions
#
sff_files   = $(wildcard $(raw_data)/*.sff)
fasta_files = $(patsubst %.sff, %.fasta, $(sff_files))
qual_files  = $(patsubst %.sff, %.fasta.qual, $(sff_files))

# raw data INFILES
#raw_files = $(wildcard $(raw_data)/*.fasta)
todb_reads_files = $(addprefix $(dir)/, $(notdir $(patsubst %.fasta,%.todb_reads_done,$(wildcard $(raw_data)/*.fasta))))


# files for READS
rfasta_files =  $(foreach k,$(n),$(dir)/$(num_segments)_$(k).rfasta)
rigout_files = $(patsubst %.rfasta,%.rigout,$(rfasta_files))
rblout_files = $(patsubst %.rfasta,%.rblout,$(rfasta_files))
razers_files = $(patsubst %.rfasta,%.rrzout,$(rfasta_files))

# files for CONSENSUS
cfasta_files = $(wildcard $(dir)/cons_*_seqs.cfasta)
caln_files = $(patsubst %.cfasta, %.caln, $(cfasta_files))

# files for SEQUENCES
sfasta_files =  $(foreach k,$(n),$(dir)/$(num_segments)_$(k).sfasta)
sigout_files = $(patsubst %.sfasta,%.sigout,$(sfasta_files))
sblout_files = $(patsubst %.sfasta,%.sblout,$(sfasta_files))



#####
##### Main rules for PHASE1 and PHASE2
##### Process needs to be split into two phases (i.e. recursive calling of make), 
##### because at the start, it is not clear yet how the consenusu files will look like.
##### PHASE1 ends with redefining sfasta and related files.
#####

all: $(dir)/PHASE2

# PHASE 2 starts, after the fasta files for alignment have been generated
# otherwise, make does not know which files belong to *.cfasta and *.caln
$(dir)/PHASE2: $(dir)/PHASE1
	$(MAKE) $(dir)/consensusfasta.done $(dir)/metainfotodb.done $(dir)/cdrfwrtodb.done $(dir)/allsigout.done $(dir)/allsblout.done $(dir)/igblastalignments.done $(dir)/mutations.done $(dir)/qualitycontrol.done
	@echo "Finished without errors on `date --utc +%Y-%m-%d\ %H:%M:%S\ %Z`"
	touch $@
	
# PHASE 1 does everything up to generating the *.caln files to db	
$(dir)/PHASE1:
	$(MAKE) $(dir)/allaligntodb.done
	touch $@


#####
##### PHASE2 targets
#####

$(dir)/qualitycontrol.done: $(dir)/allsigout.done
	Rscript pipeline_QC.R --run $(run) --qcdir $(quality_base_dir)

# upload metainformation
# DONT FORGET to put the plate and metainfo to the raw_data directory
$(dir)/metainfotodb.done: $(dir)/mutations.done
	./todb_sampleinfo_highth.pl -p $(raw_data)/*_plate.tsv -m $(raw_data)/*_metainfo.tsv -pb $(raw_data)/*_platebarcode.tsv -exp $(experiment_id)
	Rscript todb_flow.R --path $(raw_data)
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
##### PHASE1 targets
#####

# tell that all alignments are in the database
$(dir)/allaligntodb.done: $(dir)/consensusfasta.done $(caln_files)
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
	$(eval cfasta_files:=$(wildcard $(dir)/cons_*_seqs.cfasta))
	$(eval caln_files:=$(patsubst %.cfasta, %.caln, $(cfasta_files)))
	touch $@

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
	file_temp_fasta="$(patsubst %.rfasta,%.fasta,$<)"; \
	mv $< $$file_temp_fasta; \
	./perform_RazerS.pl -f $$file_temp_fasta -ro $@.razers; \
	mv $$file_temp_fasta $<; \
	mv $@.razers $@

%.rblout: %.rfasta
	./perform_blast.sh $< $@.x
	mv $@.x $@

%.rigout: %.rfasta
	./perform_igblast.sh $< $@.x
	mv $@.x $@

.PRECIOUS: %.rfasta

# Use order-only prerequiste to avoid failing rebuild if change dates are to close
%.rfasta: | $(dir)/alltodb.done
	./fromdb_fasta.pl -s reads -t reads_VDJ_segments -f $@.x
	mv $@.x $@

$(dir)/alltodb.done: $(todb_reads_files)
	touch $@

$(dir)/$(notdir %.todb_reads_done ): $(raw_data)/$(notdir %.fasta)
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

	   
clean: 
ifndef run
	@echo "specify run using run=<runname>, i.e. subdirectory where raw data is stored"
	exit 1
endif
	find $(dir) -type f | xargs -r rm
	find $(quality_control) -type f | xargs -r rm

convert-sff: convert-sff-seq convert-sff-qual

convert-sff-seq: $(fasta_files)

convert-sff-qual: $(qual_files)

%.fasta: %.sff
	sffinfo -seq -notrim $< > $@
	cp -n metainfo/seqrun_info.txt $@.info

%.fasta.qual: %.sff
	sffinfo -qual -notrim $< > $@




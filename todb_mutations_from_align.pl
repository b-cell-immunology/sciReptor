#!/usr/bin/perl

=pod

=head1 NAME

todb_mutations_from_align

=head1 SYNOPSIS

todb_mutations_from_align.pl [-h] -dir <input_directory>

=head1 DESCRIPTION

This function calculates the mutations from the query-germline alignment and writes them to the database.

Take all alignments in input_directory with information on start of query and germline in reference to origin (frame 0). Take the mutation matrix and check for every codon (in frame!), where replacements, silent mutations, ins and dels occur. The variables in_status and del_status tracks the relative frame shift in reference to origin. BE CAREFULL: If the frame is shifted due to insertion/deletion, the translation of single codons is not meaningfull anymore and you have to check, whether silent/replacement assignment really correspond to what you want to see!

In the alignment file it allways needs to be like that:
><queryid>_<querystartposition>_query
<query sequence>
><queryid>_<germlinestartposition>_germline
<germline sequence>

1. Get all files from input directory
2. Build up hash from mutation_matrix
3. Go through all files, split alignment into reading frame codons
4. For every codon look for mutations and stopcodons

=head1 LOGGED INFORMATION

- sequences where there is a stop codon either in the query or in the germline

=head1 TO DO

deal with letters different than ACGT

optionaly write the output into a file (if just needed for analysis and do not want to write to DB)

=head1 AUTHOR

Katharina Imkeller

=head1 HISTORY

Written March 2014
consecutive_in_del_status replaced by (in_status, del_status)	KI	20150319

=cut


use DBI;
use strict;
use warnings;
use Getopt::Long;
use Bio::AlignIO;
use Bio::SimpleAlign;
use bcelldb_init;

my $help=0;
my $inputdir="";

&GetOptions("h!" => \$help,
	"dir=s" => \$inputdir,
);

$help=1 unless $inputdir;
exec('perldoc',$0) if $help;

## logging to database currently turned off due to database time-outs
# select LOG;

###
### 1. Get all files from input directory
###
# use all input files ending on .igblast.aln in the directory
my @files = <$inputdir/*.igblast.aln>;

###
### 2. Build up hash from mutation_matrix
###

# open mutation files and build up matrizes
open(my $mutation_table, "<mutation_matrix.txt");
my %mutation_table_hash;

# get different matrix entries into a hash with reference obs and germ codon
while (<$mutation_table>) {
	chomp $_;
	my ($obs_codon,$germ_codon,$mutation,$n_repl,$n_silent,$insertion,$deletion) = split("\t", $_);
	# mutations without known effect (that additionally occur in a codon with in del)
	$mutation_table_hash{$obs_codon}{$germ_codon}{'mutation'} = $mutation;
	# replacement mutations
	$mutation_table_hash{$obs_codon}{$germ_codon}{'n_repl'} = $n_repl;
	# silent mutations
	$mutation_table_hash{$obs_codon}{$germ_codon}{'n_silent'} = $n_silent;
	# insertions
	$mutation_table_hash{$obs_codon}{$germ_codon}{'insertion'} = $insertion;
	# deletions
	$mutation_table_hash{$obs_codon}{$germ_codon}{'deletion'} = $deletion;

}


###
### 3. Go through all files, split alignment into reading frame codons
###

my $dbh = get_dbh($conf{database});

foreach my $input (@files) {

	# open alignment file
	my $str = Bio::AlignIO->new(-file => "$input", -format => 'fasta') or die "$input could not be openened.";
	my $aln = $str->next_aln();
	
	# use lists to extract sequence and header of alignments
	my @seqs = ();
	my @seq_ids;
	foreach my $single_aln ($aln->each_seq()) {
		push(@seq_ids, $single_aln->id);
		push(@seqs, $single_aln->seq);
	}
	
	# query: nr. 1, subj: nr. 2
	my $query_seq = $seqs[0];
	my $subject_seq = $seqs[1];
	
	# determine, where on the alignment to start with the reading frame
	# split headers of query and germline
	# extract starting positions
	my @query_split = split("_", $seq_ids[0]);
	my $query_start = $query_split[1];
	my @germ_split = split("_", $seq_ids[1]);
	my $germline_start = $germ_split[1];
	
	# determine frame and find out, where first codon starts
	my $frame = $germline_start % 3;
	my $frame_start;
	# the "frame" does not correspond to the position, where the first codon starts
	# need the variable $frame_start to
	if ($frame == 2) { $frame_start = 2; }
	elsif ($frame == 1) { $frame_start = 0; }
	elsif ($frame == 0) { $frame_start = 1; }
	
	# consecutive_in_del_status
	# +1 for insertions
	# -1 for deletions
	#my $consecutive_in_del_status = 0;
	my $in_status = 0;
	my $del_status = 0;
	
	
	#print "query\tsubject\tposi\tmut\trepl\tsilent\tins\tdel\tstatus\n";
	
	# SQL statement for insertion of mutations
	my $statement = "INSERT IGNORE INTO $conf{database}.mutations \
		(seq_id, position_codonstart_on_seq, replacement, silent, \
		insertion, deletion, undef_add_mutation, \
		stop_codon_germline, stop_codon_sequence, \
		in_status, del_status) \
		VALUES (?,?,?,?,?,?,?,?,?,?,?);";
	
	my $insert_mutation = $dbh->prepare($statement);
	
	# get the query id from the filename... maybe change that
	$input =~ m/(\d+)\.igblast\.aln/;
	my $seq_id = $1;
	
	# print seq_id into log table
	if ($conf{log_level} >= 4) { print "[todb_mutations_from_align.pl][DEBUG] Processing sequence $seq_id\n" };
	
	###
	### 4. For every codon look for mutations and stopcodons
	###
	# split the alignments into codons and check for mutations
	# start at the position previously determined
	for (my $i=$frame_start; $i<$aln->length(); $i=$i+3) {
		my $query_codon = substr($query_seq, $i, 3);
		my $subject_codon = substr($subject_seq, $i, 3);

		# reset boolean variables to check for stop codons
		my $stop_codon_germline = 0;
		my $stop_codon_sequence = 0;

		# reset mutation variables
		my $replacements = 0;
		my $silents = 0;
		my $add_mutations = 0;
		my $insertions = 0;
		my $deletions = 0;
	
		# is there a stop codon in the germline? --> then there likely is a problem with the frame...
		if ($subject_codon eq 'TAA' || $subject_codon eq 'TGA' || $subject_codon eq 'TAG') {
			if ($conf{log_level} >= 3) { print "[todb_mutations_from_align.pl][INFO] sequence $seq_id position $i query \"$query_codon\" germline \"$subject_codon\" : stop codon in germline sequence.\n" };
			$stop_codon_germline = 1;
		}
	
		if ($query_codon eq 'TAA' || $query_codon eq 'TGA' || $query_codon eq 'TAG') {
			if ($conf{log_level} >= 3) { print "[todb_mutations_from_align.pl][INFO] sequence $seq_id position $i query \"$query_codon\" germline \"$subject_codon\" : stop codon in query sequence.\n" };
			$stop_codon_sequence = 1;
		}

		# try to find mutations only, if the two codons are different
		if (!($query_codon eq $subject_codon) 	
			# make sure the codon is 3 nucl long
			&& length $query_codon eq 3 
			# also insert when there is any stop codon
			|| ($stop_codon_sequence eq 1 || $stop_codon_germline eq 1)
			) {

				#print "INSERTED\n";	

			# 
			if ( defined $mutation_table_hash{$query_codon}{$subject_codon}{'mutation'}) {

				# update counts only if the codons appear in mutation matrix
				# otherwise using undefined variables
				$replacements = $mutation_table_hash{$query_codon}{$subject_codon}{'n_repl'};
				$silents = $mutation_table_hash{$query_codon}{$subject_codon}{'n_silent'};
				$add_mutations = $mutation_table_hash{$query_codon}{$subject_codon}{'mutation'};
				$insertions = $mutation_table_hash{$query_codon}{$subject_codon}{'insertion'};
				$deletions = $mutation_table_hash{$query_codon}{$subject_codon}{'deletion'};


				#$consecutive_in_del_status += $insertions;
				#$consecutive_in_del_status -= $deletions;
				$in_status += $insertions;
				$del_status += $deletions;
			}

			
			# determine the position of the mutation in terms of absolute measure on the query sequence	
			my $position_codon_on_seq = $i + $query_start;			
		
			#print "$query_codon\t$subject_codon\t$position_codon_on_seq\t$mutation_table_hash{$query_codon}{$subject_codon}{'mutation'}\t";
			#print "$mutation_table_hash{$query_codon}{$subject_codon}{'n_repl'}\t";
			#print "$mutation_table_hash{$query_codon}{$subject_codon}{'n_silent'}\t";
			#print "$mutation_table_hash{$query_codon}{$subject_codon}{'insertion'}\t";
			#print "$mutation_table_hash{$query_codon}{$subject_codon}{'deletion'}\t";
			#print "$consecutive_in_del_status\n";
	
			# insert into mutations table of database
			my $temp_insert_return = $insert_mutation->execute(
				$seq_id, 
				$position_codon_on_seq, 
				$mutation_table_hash{$query_codon}{$subject_codon}{'n_repl'}, 
				$mutation_table_hash{$query_codon}{$subject_codon}{'n_silent'}, 
				$mutation_table_hash{$query_codon}{$subject_codon}{'insertion'}, 
				$mutation_table_hash{$query_codon}{$subject_codon}{'deletion'}, 
				$mutation_table_hash{$query_codon}{$subject_codon}{'mutation'}, 
				$stop_codon_germline,
				$stop_codon_sequence,
				$in_status,
				$del_status
			);
			if (! $temp_insert_return) {
				print("[todb_mutations_from_align.pl][ERROR] Could not insert into table. $insert_mutation->errstr \n") if ($conf{log_level} >= 1);
			} else {
				print("[todb_mutations_from_align.pl][DEBUG] Inserted $temp_insert_return lines into table.\n") if ($conf{log_level} >= 4);
			}
		}
	
	}
}

#print @seqs;

#print $mutation_table_hash{'AAA'}{'ATC'}{'mutation'};

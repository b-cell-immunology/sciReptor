#!/usr/bin/perl

=pod

=head1 NAME

todb_consensus_sequences.pl

=head1 SYNOPSIS

todb_consensus_sequences.pl -aln <musclealign> [-h]

=head1 DESCRIPTION

Read the alignment output of MUSCLE, write consensus and identity percentage for each position to database.

1. Prepare database: insert consensus to sequences, update seq_id in consensus_stats

2. Get Consensus from alignment. Consensus file must have the name matching 'cons_[consensus_id]'.

3. Write to database.

=head1 LOGGED INFORMATION

- sequence ambiguities with keys and values (if not more then 50% of sequences have the one nucleotide)
- SQL statement: select all consensi refering to that event
- insert sequence statement
- SQL statement: update sequence_id in consensus_stats table

=head1 KNOWN BUGS

If the MUSCLE output contains letters that are not [ACGT], the character is ignored. Capitalization matters.

=head1 AUTHOR

Katharina Imkeller - imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

Written Jan 2014
Update Sep 2014 - Logging and Documentation

=cut

use DBI;
use strict;
use warnings;
use bcelldb_init;
use Getopt::Long;
use Bio::AlignIO;
use Bio::SimpleAlign;
use List::Util qw(max);

my $help=0;
my $input="";

&GetOptions("h!" => \$help,
	"aln=s" => \$input,
);

$help=1 unless $input;
exec('perldoc',$0) if $help;

### 0. Logging

select LOG;


### 1. Prepare database for insertion of sequence

my $dbh = get_dbh($conf{database});

# insert sequence
my $ins_seq_st = "INSERT INTO $conf{database}.sequences (seq, length, quality, name, consensus_rank) \
  VALUES (?,?,?,?,?) ON DUPLICATE KEY \
  UPDATE seq=? AND length=? AND quality=? AND name=? AND consensus_rank=? AND seq_id = LAST_INSERT_ID(seq_id)";
my $ins_seq = $dbh->prepare($ins_seq_st);

# find out, whether it is 1. or 2. consensus
# select the row, col, locus and experiment_id and check, whether there is another one for that
my $sel_consensus_details = "SELECT row_tag, col_tag, experiment_id, locus \
  FROM $conf{database}.consensus_stats WHERE consensus_id = ?";
my $sel_details = $dbh->prepare($sel_consensus_details);

my $sel_all_consensi = "SELECT consensus_id, n_seq \
  FROM $conf{database}.consensus_stats 
  WHERE row_tag = ? AND col_tag = ? AND experiment_id = ? AND locus = ? \
  ORDER BY n_seq DESC";
my $sel_all = $dbh->prepare($sel_all_consensi);

# update consensus table, put seq_id
my $update_consensus_st = "UPDATE $conf{database}.consensus_stats \
  SET sequences_seq_id=? WHERE consensus_id=?";
my $update_consensus = $dbh->prepare($update_consensus_st);


### 2. get consensus from alignment

my $str = Bio::AlignIO->new(-file => "$input", -format => 'fasta') or die "$input could not be openened.";
my $aln = $str->next_aln();

# unique name: consensus_id
$input =~ m/cons_[0-9]*/;
my ($cons, $cons_id) = split("_", $&);


# Get all the sequences
# consensus length
my $cons_length = $aln -> length;

#### For each position get all the letters
my %position_count_hash = ();

foreach my $single_aln ($aln->each_seq()) {
	my $seq = $single_aln->seq;
	for (my $i=0; $i < $cons_length; $i++) {
		my $nucleo = substr($seq, $i, 1);
		$position_count_hash{$i}{$nucleo}++;
	}	
}

# find the most prominent letter
# if it is not A,C,G or T, dont write it

my $consensus = "";
my $consensus_quality = "";

for (my $i=0; $i < $cons_length; $i++) {
	# get all the characters at this position
	my @keys = keys %{$position_count_hash{$i}};
	# get counts at this position
	my @values = values %{$position_count_hash{$i}};
	# sort keys according to descending order of counts
	my @sorted_keys = sort{$position_count_hash{$i}{$b} <=> $position_count_hash{$i}{$a}} @keys;

	# append to consensus if it is [ACGT]
	if ($sorted_keys[0] =~ m/[ACTG]/) {
		$consensus .= $sorted_keys[0];
		my $max_value = max(@values);
		my $max_value_perc = int(100*$max_value/$aln->num_sequences);
		$consensus_quality .= "$max_value_perc ";
		if ($max_value < 0.5*$aln->num_sequences) {
			print "Consensus_id $cons_id: sequence ambiguity at position $i. $sorted_keys[0] has only $max_value in ".$aln->num_sequences."\n";
			print "keys: @keys\nvalues: @values\n";
		}
	}
}

#print "consensus\n$consensus\nquality\n$consensus_quality\n";

### 3. Find out whether it is 1. or 2. consensus rank
my $consensus_rank = 1;

$sel_details->execute($cons_id);
my ($row, $col, $experiment_id, $locus); 
while (my @cons_details = $sel_details->fetchrow_array) {
	($row, $col, $experiment_id, $locus) = @cons_details;
}

$sel_all->execute($row, $col, $experiment_id, $locus);
# log statement
print "Select all consensi statement: $sel_all->{Statement}\n";

while (my @possible_consensus = $sel_all->fetchrow_array) {
	my ($poss_cons_id, $poss_nseq) = @possible_consensus;
	if ($poss_cons_id eq $cons_id) {last;}
	else {$consensus_rank++};
}

### 3. Write to database.

$ins_seq->execute($consensus,length $consensus, $consensus_quality, $cons_id, $consensus_rank, $consensus,length $consensus, $consensus_quality, $cons_id, $consensus_rank);
# log insert statement
print "Insert sequence statement: $ins_seq->{Statement}\n";

my $seq_id = $dbh->{mysql_insertid};
$update_consensus->execute($seq_id, $cons_id);
# log update statement
print "Update seq_id statement: $update_consensus->{Statement}\n";


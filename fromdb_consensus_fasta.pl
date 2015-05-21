#!/usr/bin/perl

=pod

=head1 NAME

fromdb_consensus_fasta

=head1 SYNOPSIS

fromdb_consensus_fasta.pl -p <output_path> [-h <help>]

=head1 DESCRIPTION

Once the consensus_ids are assigned, this program is needed to generate one fasta file for each consensus. This file contains all the reads that belong to the consensus and will be used by MUSCLE for sequence alignment.

For each consensus, that does not yet have a sequence assigned:
	- get the corresponding reads
	- update information in consensus

1. Select consensus_ids and prepare selection for reads
2. Loop over consensi, for each of them select all the reads and write fasta
3. Logging counts

=head1 LOGGED INFORMATION
- total number of consensus_ids that where initially selected
- number of consensus_ids that had more then threshold number of reads

=head1 KNOWN BUGS

* Cannot write log to logtable, because there is too much output.
  Solved by inactivating log.
  Sep 2014 (KI): changed log output, now we only count the consensi.

=head1 TODO

It might be nice to directly cut away the tags here.

=head1 AUTHOR

Katharina Imkeller
	
=cut

use strict;
use warnings;
use Bio::SeqIO;
use Getopt::Long;
use bcelldb_init;
use DBI;

my $help=0;
my $outpath;

&GetOptions("h!" => \$help,
	"p=s" => \$outpath,
);

$help=1 unless $outpath;
exec('perldoc',$0) if $help;

### Functions

sub revcomp {
	# creates reverse complement, needed for reverse reads
	my $dna = shift;
	my $revcomp = reverse($dna);
	$revcomp =~ tr/ACGTacgt/TGCAtgca/;
	return $revcomp;
}


### 0. Logging and database init
#cannot write to log file because to much text for db log
select LOG;
my $dbh = get_dbh($conf{database});

### 1. Prepare select statements
# get all the consensus_ids, that do not have a matching sequence
my $sel_consensus_sth = $dbh->prepare("SELECT consensus_id \
  FROM $conf{database}.consensus_stats \
  WHERE sequences_seq_id IS NULL");
$sel_consensus_sth->execute;


# Prepare statement: get all the reads for this consensus_id
my $sel_reads_sth = $dbh->prepare("SELECT seq_id, orient, seq \
  FROM $conf{database}.reads \
  WHERE consensus_id = ?");


### 2. Loop over all consensi

# counters for consensi, depending on wherther they have enough reads or not
my $total_count = 0;	# total number of selected consensi
my $cons_count = 0;	# consensi that have more then threshold nb of reads

while ( my @row = $sel_consensus_sth->fetchrow_array ) {
	
	$total_count++;
	
	my ($consensus_id) = @row;	# @rows contains only one value

	# select the corresponding reads
	$sel_reads_sth->execute($consensus_id);

	# only build consensus, if more then n reads
	if ($sel_reads_sth->rows >= $conf{n_consensus}) {
		
		$cons_count++;

		# create output fasta
		#my $fasta_out = Bio::SeqIO->new(-file => ">cons_$consensus_id\_align.fa", -format => 'fasta');
		my $out_file = "$outpath/cons_$consensus_id\_seqs.cfasta";
		open(my $fastaout, ">$out_file") or die "fastaout $out_file not opened\n";
		# write selected reads to fasta file for muscle
		while ( my @read = $sel_reads_sth->fetchrow_array ) {
			my ($seq_id, $orient, $seq) = @read;

			# if necessary, reverse complement
			if ($orient eq "R") { $seq = revcomp($seq); }
			
			# print each read to the fasta file
			print $fastaout ">$seq_id\n$seq\n";

		}
		close($fastaout);
	}
}

### 3. Log information on consensi counts
print "In total, $total_count of consensus_ids without sequence where found.\n \
  $cons_count of them had more then $conf{n_consensus} reads and where thus considered \
  for multiple sequence alignment.\n"


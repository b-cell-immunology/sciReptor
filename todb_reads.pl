#!/usr/bin/perl

# Plain old documentation

=head1 NAME

todb_reads.pl - upload raw 454 sequencing data to bcelldb

=head1 SYNOPSIS

todb_reads.pl [-h <help>] -f <fastafile> -q <qualfile> -ri <seqrun_info> -m <matrix> 

=head1 ARGUMENTS 

-h	Open documentation.

-f, -q	Fasta file and quality file. Need same identifiers in both files.

-ri	Text file with information concerning the sequencing run.

-m	Experiment ID (formerly called matrix).

=head1 DESCRIPTION

Load the raw high-throughput sequences into the database, including quality 
information and information about sequencing run.

1.	Get sequences and qualities from input files and store them into hashes with identifier as keys. Create a list of all identifiers.

2.	Prepare statements to insert into reads and sequencing_run tables.

3.	Write sequencing run info into sequencing run table and get back the identifier.

4.	For each identifier write sequence, length, quality and sequencing_run identifier into reads table.

=head1 LOGGED INFORMATION

- information on insertion of sequencing_run
- number of reads that were inserted

=head1 AUTHOR

Katharina Imkeller - imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

Written Jan 2014

=cut

use DBI;
use strict;
use warnings;
use Getopt::Long;
use Bio::SeqIO;
use bcelldb_init;

my $help = 0;
my $output = "reads";
my $fastafile;
my $qualfile;
my $seqrun_infofile;
my $matrix = "";

&GetOptions("h!" => \$help,
	"f=s"	=> \$fastafile,
	"q=s"	=> \$qualfile,
	"ri=s" => \$seqrun_infofile,
	"m=s" => \$matrix 
);

$help=1 unless ($fastafile && $qualfile);
$help=1 unless $seqrun_infofile;
$help=1 unless $matrix;
exec('perldoc',$0) if $help;



### 0. Logging information

# all STDOUT will be logged to database
select LOG;
my $dbh = get_dbh($conf{database});


### 1. Get sequences and qualities from input files 
### and store them into hashes with identifier as keys. 
### Create a list of all identifiers.
### Does not make sure that for every identifier there exist sequence and quality!


# open file with sequence information
my $fasta_in = Bio::SeqIO->new(-file => $fastafile, -format => 'fasta') or die "could not open $fastafile";
my $qual_in = Bio::SeqIO->new(-file => $qualfile, -format => 'qual') or die "could not open $qualfile";

# hash for sequences
my %id_seq_hash;
# hash for quality
my %id_qual_hash;
# identifier list
my @identifiers = ();

# store sequence to hash
# seq_id used as key
my $seq_id;
while (my $seq = $fasta_in->next_seq()) {
	my $seq_id =  $seq->id;
	# take all letters in upper case
	$id_seq_hash{$seq_id} = uc $seq->seq;
	# list of all seq_id
	push(@identifiers, $seq_id);
}

# store quality to hash
# seq_id used as key
my $qual_id;
while (my $qual = $qual_in->next_seq()) {
	$qual_id = $qual->id;
	$id_qual_hash{$qual_id} = $qual->seq;
}



### 2. Prepare statements to insert into reads and sequencing_run tables.

# statement to write into reads table
my $statement1 = "INSERT IGNORE INTO $conf{database}.reads 
  (name, length, seq, quality, sequencing_run_id) 
  VALUES (?,?,?,?,?) ";
my $query1 = $dbh->prepare($statement1);

# statement to write into sequencing_run table
my $statement2 = "INSERT IGNORE INTO $conf{database}.sequencing_run 
  (date, name, processed_by, plate_layout_id, add_sequencing_info, experiment_id) 
  VALUES (?,?,?,?,?,?)";
my $query2 = $dbh->prepare($statement2);




### 3. Get sequencing run from infile and write into sequencing run table 
### Get back the identifier.

# get sequencingrun info from input file
open(my $seqrun_info, $seqrun_infofile);
my $runname;
my $rundate;
my $processed_by;
my $platelayout_id;
my $optional;

while(<$seqrun_info>) {
	chomp $_;
	unless ($_ =~ m/#/ || $_ eq "") {
		my ($name, $value) = split("=", $_);
		if ($name eq "runname") { $runname = $value; }
		elsif ($name eq "rundate") { $rundate = $value; }
		elsif ($name eq "processed_by") { $processed_by = $value; }
		elsif ($name eq "platelayout_id") { $platelayout_id = $value; }
		elsif ($name eq "optional") { $optional = $value; }
	}
}

# execute query
my $seq_run_bool = $query2->execute(
	$rundate, 
	$runname, 
	$processed_by, 
	$platelayout_id,
	$optional,
	$matrix
);

# get the last inserted id, which corresponds to sequencing_run_id
my $sequencing_run_id;
if ($seq_run_bool eq 1) {	# this is true when $query2 returned one, i.e. successfully inserted run
	$sequencing_run_id = $dbh->{'mysql_insertid'};
	# print run info to logfile
	print "Inserted sequencing run $sequencing_run_id, $runname, $rundate into sequencing_run table.\n";
}
else {
	print "Sequencing run allready exists. Please check the sequencing run settings (date and name), if that is not correct.";
}



### 4. For each identifier write sequence, length, 
### quality and sequencing_run_id into reads table.

# count the number of inserted reads
my $n_inserted = 0;
# count the total number of sequences
my $n_reads = 0;
print "Reads inserted into reads table:\nname\tread_id\n";
foreach (@identifiers) {
#	print "$_\t";
	$n_reads++;	# count total reads
	# update reads table and count the ones that where inserted
	$n_inserted += $query1->execute(
		$_,
		length($id_seq_hash{$_}),
		$id_seq_hash{$_},
		$id_qual_hash{$_},
		$sequencing_run_id
	);
#	print "$dbh->{'mysql_insertid'}\n";
}
print "total number of reads = $n_reads\n";
print "number of inserted reads = $n_inserted\n";
unless ($n_reads eq $n_inserted) {
	print STDOUT "Warning! Not all the reads in fasta file where inserted. Some or all already existed.";
}

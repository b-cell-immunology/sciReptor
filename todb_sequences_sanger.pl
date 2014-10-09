#!/usr/bin/perl

=pod

=head1 NAME

todb_sequences_sanger

=head1 SYNOPSIS

todb_sequences_sanger.pl [-h] -f <inputfasta> -q <inputqual> [-m <metainfo>]

=head1 DESCRIPTION

Write sequences from Sanger sequencing to the DB sequences table. 
Necessary input: 
	-f	fasta file with (numerical) unique identifiers
	-q 	qual file with (numerical) unique identifiers
Optional input:
	-m	csv file with information on event, sort, sample, donor of each sequence (use sanger_metainfo.csv as template)

1. If metainfo given, get the unique sequence names from the csv table. If no name is given (e.g. in case of scratchpad function of the pipeline), fasta identifier will be used as name. The sequences table uses the name column as unique key in order to prevent overwriting of sequences.

2. Prepare the database to insert into sequences table.

3. Open fasta and qual file.

4. Read sequences and qualities and store them in hashes according to their identifier. Store all fasta identifiers in a list, in order to go through this list when inserting into DB.

5. Insert sequence, quality, length, name into sequences table. Insertions are tracked in log table. If the name is allready present, sequence will not be inserted and a warning appears in STDOUT.

=head1 LOGGED INFORMATION

- total number of processed and inserted sequences
- identifiers that were not inserted, most likely because they were not unique

=head1 TO DO

Keep track of identifier duplicates, to more easily work with messy data. 
E.g. write all duplicates into a file in order to be later on be able to juge them manually.

=head1 AUTHOR

Katharina Imkeller, imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

written Jan 2014

=cut

use DBI;
use strict;
use warnings;
use Getopt::Long;
use Bio::SeqIO;
use bcelldb_init;

my $help=0;
my $input_fasta="";
my $input_qual="";
my $input_metainfo = "";

&GetOptions("h!" => \$help,
	"f=s" => \$input_fasta,
	"q=s" => \$input_qual,
	"m=s" => \$input_metainfo,
);

$help=1 unless $input_fasta;
$help=1 unless $input_qual;
exec('perldoc', $0) if $help;


### 0. Logging and database init

select LOG;
my $dbh = get_dbh($conf{database});


### 1. If present, get sequence names from the metainfo table 

my $count_line = 0;
# hash for storing unique name of the sequence
my %id_name_hash;

if ($input_metainfo) {
	open(my $meta, $input_metainfo) or die "metainfo $input_metainfo could not be openend";
	while (<$meta>) {
		print "$_\n";
		$count_line++;
		chomp $_;
		if ($count_line > 2) {
			my ($id, $name) = split("\t", $_);
			$id_name_hash{$id} = $name;
		}
	}
	close($meta);
}


### 2. Prepare database query

my $ins_sequence = $dbh->prepare("INSERT IGNORE INTO $conf{database}.sequences (name, length, seq, quality) values (?,?,?,?)");


### 3. Open input fasta and qual

my $fasta_in = Bio::SeqIO->new(-file => $input_fasta, -format => 'fasta') or die "could not open $input_fasta";
my $qual_in = Bio::SeqIO->new(-file => $input_qual, -format => 'qual') or die "could not open $input_qual";


### 4. For each identifier get sequence and quality (stored in hashes). 
### Store all identifiers that occured in the fasta file in a list.

my $seq_id;
# hash for sequences
my %id_seq_hash;
# hash for qualities
my %id_qual_hash;
# list of all seqs
my @identifiers = ();

# store sequence to hash
# seq_id used as key
my $seq_id;
while (my $seq = $fasta_in->next_seq()) {
	my $seq_id =  $seq->id;
	$id_seq_hash{$seq_id} = $seq->seq;
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


### 5. For each identifier write sequence, length, 
### quality and name

# count the number of inserted reads
my $n_inserted = 0;
# count the total number of sequences
my $n_reads = 0;
print "Sequences inserted into sequences table:\nname\tsequence_id\n";
foreach (@identifiers) {
	$n_reads++;	# count total reads
	my $last_insert_id = 0;	# reset

	# get the name if metainfo present, else name is seq_id
	my $name = $_;
	if ($input_metainfo) {$name = $id_name_hash{$_}};

	# update reads table and count the ones that where inserted
	$n_inserted += $ins_sequence->execute(
		$name,
		length($id_seq_hash{$_}),
		$id_seq_hash{$_},
		$id_qual_hash{$_},
	);
	my $last_insert_id = $dbh->{'mysql_insertid'};
	unless ($last_insert_id eq 0) {print "$_\t$last_insert_id\n";}
	else {print "There seems to be a non-unique identifier $_\t$last_insert_id\n";}
}
print "total number of sequences = $n_reads\n";
print "number of inserted sequences = $n_inserted\n";
unless ($n_reads eq $n_inserted) {
	print STDOUT "Warning! Not all the sequences in fasta file where inserted. Some or all already existed. The identifier needs to be unique in the sequences table of your database.";
}

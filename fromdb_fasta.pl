#!/usr/bin/perl

=pod

=head1 NAME

fromdb_fasta.pl - Get a fasta file from reads or sequences table.

=head1 SYNOPSIS

fromdb_fasta.pl -s <sourcetable> -t <targettable> -f <outfile> [-h]

=head1 DESCRIPTION

Get a fasta file of sequences in the sourcetable that do not have any correspondence in the targettable. Modulo and rest are used to distribute all the sequences to smaller files that can then be analysed by different processes.
Needed as a step before executing further analysis.
The fasta file will be used as source for IgBLAST, BLAST, RazerS and MUSCLE. The fasta file is written into the output subrepository.

0.	Logging

1.	Make a directory where fasta file will be stored.

2.	Connect to database. Select all entries of sourcetable that do not have corresponding entry in targettable.

3.	Write seq_id and seq of selected rows into fasta file.

=head1 LOGGED INFORMATION
- select statement for sequences
- total number of sequences that were selected

=head1 AUTHOR

Katharina Imkeller - imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

Written Jan 2014

=cut

use DBI;	# for using the database
use strict;
use warnings;
use Getopt::Long;
use bcelldb_init;	# for config values and logging

my $help=0;
my $input="";
my $output="";
my $outfile="";
my ($mod,$rest)=(1,0);

&GetOptions("h!" => \$help,
	"s=s" 	=> \$input,
	"t=s"	=> \$output,
	"f=s" => \$outfile,	
);

$help=1 unless $input;
$help=1 unless $output;
$help=1 unless $outfile;
exec('perldoc',$0) if $help;


### 0. Logging

# write all STDOUT to database
select LOG;

# get database handle
my $dbh = get_dbh($conf{database});



### 1. Make a fasta directory in the output directory if not exist

#my $tmpdir="../output_files/fasta";
#`mkdir -p $tmpdir`;


if ($outfile) {
	($mod, $rest) = $outfile =~ m/*.\/(\d+)_(\d+)\./
}



### 2. Get all entries from sourcetable that do not have correspondence in targettable

# prepare statement to get sequences
my $statement="SELECT input.seq_id, input.seq \
  FROM $conf{database}.$input AS input \
  LEFT JOIN $conf{database}.$output AS output ON output.seq_id=input.seq_id \
  WHERE output.seq_id IS NULL";

if ($mod>1){
    $statement .= " and MOD(input.seq_id,$mod) = $rest ";
}

# log the select statement
print "\n\nselect statement: $statement\n\n";


# get sequences
my $seq_count=0;

my $sth = $dbh->prepare($statement);
$sth->execute;

# write to output file

open(my $fasta, ">$outfile") or die "$outfile not openend";
while ( my @row = $sth->fetchrow_array ) {
    my ($id,$seq)= @row;
    $seq_count++;
    print $fasta ">$id\n$seq\n\n";
}
close($fasta);

print "\n\nGot $seq_count sequences\n\n";





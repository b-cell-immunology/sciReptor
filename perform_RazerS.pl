#!/usr/bin/perl

=pod

=head1 NAME

perform_RazerS.pl

=head1 SYNOPSIS

perform_RazerS [-h] -f <sequencefasta> -ro <razersoutput>

=head1 DESCRIPTION

Create a fasta file for tags and take a fasta file for reads.
Run RazerS on these files.
Insert the output to the database.

=head1 LOGGED INFORMATION
- tag select statement
- number of selected tags

=head1 AUTHOR

Katharina Imkeller - imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

Written Jan 2014
Modified Sep 2014 - moved razers path to config file

=cut

use DBI;
use strict;
use warnings;
use bcelldb_init;
use Getopt::Long;

my $help=0;
my $seqfasta="";
my $razersout="";

&GetOptions("h!" => \$help,
	"f=s" => \$seqfasta,
	"ro=s"=> \$razersout,
);

$help=1 unless $seqfasta;
$help=1 unless $razersout;
exec('perldoc',$0) if $help;

### 0. Logging and database initialization

# write to logfile
select LOG;

# get databse handle
my $dbh = get_dbh($conf{library});


### 2. Get tags from library and write to fasta file

# get tags from the database

my $get_tag_statement = "SELECT tag_id, sequence \
  FROM $conf{library}.tags_library \
  WHERE matrix=\"$conf{matrix}\" AND batch=\"$conf{tag_batch}\";";
my $get_tag = $dbh->prepare($get_tag_statement);
$get_tag->execute;

# log select
print "\nTag select statement: $get_tag_statement\n\n";

my $tag_count = 0;
open(my $tags,">$seqfasta.tags.fa") or die "failed opening tag file for writing";
while ( my @row = $get_tag->fetchrow_array ) {
	my ($tag_id, $sequence) = @row;
	$tag_count++;
	print $tags ">$tag_id\n$sequence\n";
}

print "\n\ngot $tag_count tags for the matrix $conf{matrix}\n\n";


# perform razers

# razers parameters
my $razers_percid = 90;    # minimal required percid between query and template
my $m = 100000000;         # maximal number of displayed results
my $s = 1111111;           # shape factor, seven ones mininal, means that there need to be seven in a row
my $pf = 1;                # way to present positions in string, 1 => first position=1 not 0


#chdir $razers_path or die "$!";
my $system_string = join(' ', 
	"razers3",  
	"-a",
	"-m", $m, 
	"-s", $s,
	"-i", $razers_percid,
	"-o", "$razersout", 
	"-pf", $pf,
	"$seqfasta", 
	"$seqfasta.tags.fa"
);

print "\n\n*** razers start *** \n";
system $system_string;
print "\n\n*** done *** \n";



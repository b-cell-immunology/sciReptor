#!/usr/bin/perl

=pod

=head1 NAME

todb_igblast_align - write alignment observed sequence/ germline to a file

=head1 SYNOPSIS

todb_igblast_align.pl [-h] -io <igblastoutput> -dir <directory_for_output>

=head1 DESCRIPTION

Write alignments from the IgBLAST output to database, i.e. observed sequence and germline sequence.
Write a file for each alignment, that can later be processed by the mutation count or used for other purposes.

=head1 LOGGED INFORMATION

- seq_ids that got alignment assigned

=head1 AUTHOR

Katharina Imkeller

=cut

use strict;
use warnings;
use Getopt::Long;
use bcelldb_init;

my $help=0;
my $igblastoutput="";
my $directory="";

&GetOptions("h!" => \$help,
	"io=s" => \$igblastoutput,
	"dir=s" => \$directory,
);

$help=1 unless $igblastoutput;
$help=1 unless $directory;
exec('perldoc', $0) if $help;

# logging
select LOG;


# open file
open(my $igout, $igblastoutput) or die "could not open $igblastoutput";


# define variables for parsing
my $query_id;
my $query_start;
my $germline_start;
my $query_seq;
my $germline_seq;
my $count_line = 0;
my $mark_hittable_start;

# predefine SQL statement for inserting alignments
my $dbh = get_dbh($conf{database});
my $ins_aln_statement = "INSERT IGNORE INTO $conf{database}.igblast_alignment 
  (seq_id, query_start, germline_start, query_seq, germline_seq) 
  VALUES (?,?,?,?,?)";
my $ins_aln = $dbh->prepare($ins_aln_statement);

# go through file

# start LOG
print "Following sequence ids got an IgBLAST alignment assigned:\n";

while (<$igout>) {
	chomp $_;
	$count_line++;
	#print $count_line;

	# hittable start
	if ($_ =~ m/Hit table/) {
		$mark_hittable_start = $count_line;	
		#$print $_;
	}

	# fields
	if (defined $mark_hittable_start) {
		if ($count_line == $mark_hittable_start + 1) {
			my @fields = split(",", $_);
			#print @fields;
			unless ($fields[0] =~ m/query id/ &&
				$fields[6] =~ m/q. start/ &&
				$fields[8] =~ m/s. start/ &&
				$fields[12] =~ m/query seq/ &&
				$fields[13] =~ m/subject seq/) {
				die "Fields in the hit table of IgBLAST output changed? Cannot parse.";
			}
		}
		if ($count_line == $mark_hittable_start + 3) {
			my @first_hit = split("\t", $_);
			$query_id = $first_hit[1];
			$query_start = $first_hit[7];
			$germline_start = $first_hit[9];
			$query_seq = $first_hit[13];
			$germline_seq = $first_hit[14];
			#print "$query_id\n";

			# insert into database
			$ins_aln->execute($query_id, $query_start, $germline_start, $query_seq, $germline_seq);

			# print into a file
			my $outfile;
			open($outfile, ">$directory/$query_id.igblast.aln") or die "could not open $outfile";
			print $outfile ">$query_id\_$query_start\_query\n$query_seq\n";
			print $outfile ">$query_id\_$germline_start\_germline\n$germline_seq\n";
			close($outfile);
		}
	}
}

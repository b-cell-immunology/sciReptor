#!/usr/bin/perl

=pod

=head1 NAME

todb_tags - write the tag information of each read to database

=head1 SYNOPSIS

todb_tags.pl -ro <razersoutput> [-h]

=head1 DESCRIPTION

Extract all the tags found by RazerS and write them to the database. Calculate number of insertions, deletions and mutations in the tag.

Necessary input:
-ro	RazerS output file.

Steps:
1. Prepare database to insert tag information
2. Open RazerS output
3. Parse tag information and write to database

=head1 LOGGED INFORMATION

- count of inserted tags

=head1 AUTHOR

Katharina Imkeller

=cut

use DBI;
use strict;
use warnings;
use bcelldb_init;
use Getopt::Long;

my $help=0;
my $razersout = "";

&GetOptions("h!" => \$help,
	"ro=s" => \$razersout,
);

$help=1 unless $razersout;
exec('perldoc',$0) if $help;



### 0. Logging

# write to logtable
select LOG;

# get database handle
my $dbh = get_dbh($conf{database});


### 1. Prepare database to insert tag information

# insert the tag information
my $insert_tags_statement = "INSERT IGNORE INTO $conf{database}.reads_tags 
	(seq_id, percid, direction, insertion, deletion, replacement, start, end, tag_id)
   	VALUES (?,?,?,?,?,?,?,?,?)";
my $insert_tags = $dbh->prepare($insert_tags_statement);


### 2. Open RazerS output

open(my $razer, $razersout) or die "opening razers output $razersout failed";



### 3. Parse tag information and write to database

# initialize variables for parsing tag information
my ($tag, $tag_start, $tag_end, $orient, $read, $read_start, $read_end, $percid);
my ($tag_seq, $read_seq);
my ($nins, $ndel, $nmut) = (0,0,0);
my $count_line = 0;
my $count_tags = 0;

# got through RazerS output line per line
while (<$razer>) {
	chomp $_;
	$count_line++;

	if ($_ =~ m/[0-9]/) {
		# get info for the next tag
		($tag,  $tag_start, $tag_end, $orient, $read, $read_start, $read_end,  $percid) = split("\t", $_);
	}
	elsif ($_ =~ m/Read/) {
		(my $text, $tag_seq) = split(":", $_);
	}
	elsif ($_ =~ m/Genome/) {
		(my $text, $read_seq) = split(":", $_);
		
		# calculate insertions, deletions, replacements
		unless ($percid == 100) {
			$nins = ($tag_seq =~ tr/-//);
			$ndel = ($read_seq =~ tr/-//);
			my $perc_nonid = 1 - $percid;
		    $nmut = length($tag_seq) * (1-$percid/100) - $nins - $ndel;
		}
		$insert_tags->execute(
				$read,
				$percid,
				$orient,
				$nins,
				$ndel,
				$nmut,
				$read_start,
				$read_end,
				$tag,
		);
		#reset to zero
		($nins, $ndel, $nmut) = (0,0,0);
		$count_tags++;

	}
}

print "\n\nA total number of $count_tags tags were inserted.\n\n";

close($razer);

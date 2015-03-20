#!/usr/bin/perl

=pod

=head1 NAME

=head1 SYNOPSIS

todb_sampleinfo_sanger.pl <-m> metainfo

=head1 DESCRIPTION

When uploading Sanger sequences to the DB this program inserts the provided event, sort, sample and donor information.
Necessary input file: 
	-m 	tsv table with the metainformation (use sanger_metainfo.tsv as template)

1. Prepare the database for insertion into event, sort, sample and donor tables. There are unique keys on each of these tables that prevent from overwriting or duplicating. If an entry already exists, it is not overwritten, but the corresponding id is still determined and can be inserted to the next table.

2. Parse information from the tsv table and insert into database. If the entry in species column does not correspond to the species identifiers "human" or "mouse", the program dies.

=head1 LOGGED INFORMATION

- donor, sample, sort and event

=head1 AUTHOR

Katharina Imkeller, imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

written Jan 2014

=cut

use strict;
use warnings;
use DBI;
use Getopt::Long;
use bcelldb_init;	# config variables and logging

my $help=0;
my $input_metainfo = "";

&GetOptions("h!" => \$help,
	"m=s" => \$input_metainfo,
);

$help=1 unless ($input_metainfo);
exec('perldoc',$0) if $help;


### 0. Logging

select LOG;
my $dbh = get_dbh($conf{database});


### 1. Prepare database for insertion

my $ins_donor = $dbh->prepare("INSERT INTO $conf{database}.donor 
  (donor_identifier, background_treatment, project, strain, add_donor_info, species_id) 
  VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE donor_id = LAST_INSERT_ID(donor_id)");

my $ins_sample = $dbh->prepare("INSERT INTO $conf{database}.sample 
  (tissue, sampling_date, add_sample_info, donor_id) 
  VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE sample_id=LAST_INSERT_ID(sample_id)");

my $ins_sort = $dbh->prepare("INSERT INTO $conf{database}.sort 
  (antigen, population, sorting_date, add_sort_info, sample_id) 
  VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE sort_id=LAST_INSERT_ID(sort_id)");

my $ins_event = $dbh->prepare("INSERT INTO $conf{database}.event 
  (well, plate, plate_barcode, sort_id) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE event_id=LAST_INSERT_ID(event_id)");

my $update_sequences = $dbh->prepare("UPDATE $conf{database}.sequences SET event_id=? WHERE name=?");


### 2. Extracting information from the metainfo table and inserting to DB

open(my $meta, $input_metainfo) or die "metainfo $input_metainfo could not be found";

my $count_line = 0;
while (<$meta>) {
	$count_line++;
	chomp $_;
	if ($count_line > 2) {
		my ($id, $name, $well, $plate, $plate_barcode, $seq_run_date, $add_event_info, $antigen, $population, $sorting_date, $add_sort_info, $tissue, $sampling_date, $add_sample_info, $donor_identifier, $background_treatment, $project, $strain, $add_donor_info, $species) = split("\t", $_);

		# check if species id correct
		unless ($species eq $conf{species}) {
			die "Species is $species. Must be human or mouse."
		}

		# insert donor
		$ins_donor->execute($donor_identifier, $background_treatment, $project, $strain, $add_donor_info, $species);
		my $donor_id = $dbh->{mysql_insertid};
		# log donor
		print "Donor: $ins_donor->{Statement}\n";

		# insert sample
		$ins_sample->execute($tissue, $sampling_date, $add_sample_info, $donor_id);
		my $sample_id = $dbh->{mysql_insertid};
		print "Sample: $ins_sample->{Statement}\n";

		# insert sort
		$ins_sort->execute($antigen, $population, $sorting_date, $add_sort_info, $sample_id);
		my $sort_id = $dbh->{mysql_insertid};
		print "Sort: $ins_sort->{Statement}\n";

		# insert event
		$ins_event->execute($well, $plate, $plate_barcode, $sort_id);
		my $event_id = $dbh->{mysql_insertid};
		print "Event: $ins_event->{Statement}";

		# update sequence table event id
		$update_sequences->execute($event_id, $name);
	}
}
close($meta);

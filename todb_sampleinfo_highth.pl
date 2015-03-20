#!/usr/bin/perl

=pod

=head1 NAME

todb_sampleinfo_highth

=head1 SYNOPSIS

todb_sampleinfo_highth <-p> plateinput <-m> metainfo <-pb> plate_barcodes [-h]

=head1 DESCRIPTION

Complete the donor, sample, sort and event tables for high-throughput experiments. To each scenario of donor, sample, etc... you assign a numerical identifier and can then specify the corresponding wells in the matrix.

Two necessary input files:
	-m	<experiment_id>_metainfo.tsv file, tab delimited (use template 48_48_ or 240_256_metainfo.xls->worksheet2 and store as tsv with tabs). The first column is the numerical identifier that will be used in the plate layout. The first two rows of the TSV will be ignored, since they contain the headers in the current spreadsheet.
	-p	<experiment_id>_plate.tsv file (use template 48_48_ or 240_256_metainfo.xls->worksheet1 and store as tsv with tabs). When parsing, first row and column are ignored, they contain row and col numbers. The other 48*48 or 240*256 cells contain the identifier that already appeared in metainfo.tsv to specify which well contains what.
	-pb	<experiment_id>_platebarcodes.tsv file with the plate barcode corresponding to each plate number.

1. Get information on matrix (48_48 e.g.) and plate layout (384 well plates, nrows, ncols e.g.)

2. Prepare database insertion, selection and update statements. Notably in the sequences table the event_id will be updated. Duplicates on unique keys will be ignored, not overwritten.

3. Open the input files.

4. From the plate_layout.tsv for each identifier, remember in a hash of arrays the corresponding wells (identified by row-col position). This allows you afterwards to find all wells and corresponding sequences with a certain sample, sort, donor... scenario. The event_id can then easily be updated in the sequences table. Only sequences that do not yet have an assigned event_id are updated (prevents problems when several matrices are stored in one database). From platebarcodes store platenr-barcode relations into hash.

5. Go through the metainfo.tsv and try to consecutively insert donor, sample, sort. On the event level, go through all corresponding wells, insert into event table and then update all correspnding sequences without event_id.

=head1 LOGGED INFORMATION

- donor, sample, sort information
- how many events belonged to the donor,sample,sort combi and how many sequences where found
- corrected tags in case applicable

=head1 AUTHOR

Katharina Imkeller, imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

written Jan 2014

=cut

use strict;
use warnings;
use DBI;
use POSIX;	#ceil function
use Getopt::Long;
use bcelldb_init;	
use correct_tagconfusion;

my $help=0;
my $plate_input="";
my $metainfo_input="";
my $plate_barcodes="";

&GetOptions("h!" => \$help,
	"p=s" => \$plate_input,
	"m=s" => \$metainfo_input,
	"pb=s" => \$plate_barcodes,
);

$help=1 unless $plate_input;
$help=1 unless $metainfo_input;
exec('perldoc',$0) if $help;

### 0. Logging

select LOG;
my $dbh = get_dbh($conf{database});


### 1. Get information on matrix and plate layout (how many wells to look for)

my ($col_num, $row_num) = split("_", $conf{matrix});
my $n_col_per_plate = $conf{ncols_per_plate};
my $n_row_per_plate = $conf{nrows_per_plate};


### 2. Prepare DB insertion statement

# prepare statements for donor
my $ins_donor = $dbh->prepare("INSERT INTO $conf{database}.donor 
  (donor_identifier, background_treatment, project, strain, add_donor_info, species_id) 
  VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE donor_id = LAST_INSERT_ID(donor_id)");

# sample
my $ins_sample = $dbh->prepare("INSERT INTO $conf{database}.sample 
  (tissue, sampling_date, add_sample_info, donor_id) 
  VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE sample_id=LAST_INSERT_ID(sample_id)");

# sort
my $ins_sort = $dbh->prepare("INSERT INTO $conf{database}.sort 
  (antigen, population, sorting_date, add_sort_info, sample_id) 
  VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE sort_id=LAST_INSERT_ID(sort_id)");

# event
my $ins_event = $dbh->prepare("INSERT INTO $conf{database}.event 
  (well, plate, row, col, sort_id, plate_layout_id, plate_barcode) VALUES (?,?,?,?,?,?,?) 
  ON DUPLICATE KEY UPDATE event_id=LAST_INSERT_ID(event_id)");

# select sequence id where event_id will be inserted
my $sel_seq_id = $dbh->prepare("SELECT seq_id FROM $conf{database}.sequences 
  JOIN $conf{database}.consensus_stats ON consensus_stats.sequences_seq_id = sequences.seq_id 
  WHERE event_id IS NULL AND row_tag=? and col_tag=? AND sequences.locus=?");

# update event_id
my $update_event = $dbh->prepare("UPDATE $conf{database}.sequences SET event_id=? where seq_id=?");


### 3. Open infiles

open(my $plate, $plate_input) or die "could not open $plate_input";
open(my $meta, $metainfo_input) or die "could not open $metainfo_input";
open(my $barcodes, $plate_barcodes) or die "could not open $plate_barcodes";


### 4. Extract id for each well from PLATE

# hash to store the id in each well
# e.g. $id_row_col_hash{id1} = "R1-C2"
my %id_row_col_hash;

my $count_line = 0;
while (<$plate>) {
    $count_line++;
    chomp $_;

    # get entries from 2. line on
    unless ($count_line <= 1 || $count_line > $row_num + 1) {
        my $row = $count_line - 1;
        my @entries = split("\t", $_);
        for ( my $i = 1; $i <= $col_num; $i++ ) {
			# for each id store the list of R-C pairs
			if ($entries[$i]) {
			      push(@{$id_row_col_hash{$entries[$i]}}, "R".sprintf("%03d", $row)."-C".sprintf("%03d", $i));
			}
        }   
    }
}
close($plate);


### Extract plate barcode
my %plate_barcode_hash;

$count_line = 0;
while (<$barcodes>) {
    $count_line++;
    chomp $_;
    unless ($count_line <= 1) {
	(my $plate_nr, my $plate_barcode) = split("\t", $_);
	$plate_barcode_hash{$plate_nr} = $plate_barcode;
    }
}


### 5. Extract sample information for each id from META

$count_line = 0;
while (<$meta>) {
	$count_line++;
	chomp $_;
	
	# exclude the headings
	unless ($count_line == 1 || $count_line == 2) {
		my ($identifier, $antigen, $population, $sorting_date, $add_sort_info, $tissue, $sampling_date, $add_sample_info, $donor_identifier, $background_treatment, $project, $strain, $add_donor_info) = split("\t", $_);

		unless ($population) {last;}	# dont take empty lines

		# insert donor
		$ins_donor->execute($donor_identifier, $background_treatment, $project, $strain, $add_donor_info, $conf{species});
		my $donor_id = $dbh->{mysql_insertid};
		# log donor
		print "-----------\n----------\n\n";
		print "Donor: $ins_donor->{Statement}\nWith values $donor_identifier, $background_treatment, $project, $strain, $add_donor_info, $conf{species}.\n\n";

		# insert sample
		$ins_sample->execute($tissue, $sampling_date, $add_sample_info, $donor_id);
		my $sample_id = $dbh->{mysql_insertid};
		# log sample
		print "Sample: $ins_sample->{Statement}\nWith values $tissue, $sampling_date, $add_sample_info, $donor_id.\n\n";

		# insert sort
		$ins_sort->execute($antigen, $population, $sorting_date, $add_sort_info, $sample_id);
		my $sort_id = $dbh->{mysql_insertid};
		# log sort
		print "Sort: $ins_sort->{Statement}\nWith values: $antigen, $population, $sorting_date, $add_sort_info, $sample_id.\n\n";
		
		# count events and sequences for that donor-sample-sort combi
		my $count_events = 0;
		my $count_sequences =0;
		# get the corresponding events
		my @wells = @{$id_row_col_hash{$identifier}};

		foreach (@wells) {
			my ($row_tag, $col_tag) = split("-", $_);
			my $row = substr $row_tag, 1, 3;
			my $col = substr $col_tag, 1, 3;
			
			# only if correct row and col have been found
			unless ($row > 0 && $col > 0) {last;}

			# convert row col information to well plate
			my $plate = ceil($col/$n_col_per_plate) + ((ceil($row/$n_row_per_plate) - 1 ) * $col_num/$n_col_per_plate);

			# for modulo calculation origin needs to be (0,0)
			my $new_row = $row -1;
			my $new_col = $col -1;
			my $well = ($new_col %= $n_col_per_plate) + (($new_row %= $n_row_per_plate)) * $n_col_per_plate +1;
 			
			$ins_event->execute($well, $plate, $row, $col, $sort_id, $conf{plate_layout}, $plate_barcode_hash{$plate});
			my $event_id = $dbh->{mysql_insertid};
			$count_events++;

			my @loci = ("H", "K", "L");

			foreach my $locus (@loci) {
				# correct for tag confusion
				my ($corr_col_tag, $corr_row_tag) = correct_tagconfusion::correct_tags($col_tag, $row_tag, $locus);
				
				# log the tag correction
				if (!($corr_col_tag eq $col_tag) && !($corr_row_tag eq $row_tag)) {
					print "Tag correction took place for the event $event_id on $locus locus:\n";
					print "Old tags $col_tag, $row_tag\nNew tags $corr_col_tag, $corr_row_tag\n";
				}
				# get the corresponding sequence id
				$sel_seq_id->execute($corr_row_tag, $corr_col_tag, $locus);
				while (my @row = $sel_seq_id->fetchrow_array) {
					my $seq_id = $row[0];
					$update_event->execute($event_id, $seq_id);
					$count_sequences++;
				}
			}
		}
		
		# log event and sequence count
		print "Number of events for this combi: $count_events\n";
		print "Number of sequences (H,K,L) for this combi: $count_sequences\n\n";
	}	
}
close($meta);

#!/usr/bin/perl

=pod

=head1 NAME

todb_VDJ - parse IgBLAST output and wirte to database

=head1 SYNOPSIS

todb_VDJ.pl [-h] -t <targettable> -io <igblastoutput> -ut <updatetable>

=head1 DESCRIPTION

From the IgBLAST output select the information on VDJ segments that will be written into the database.

Necessary input:

-t	Targettable, where VDJ info will be written. Can be reads_VDJ_segments or VDJ_segments according to where the sequences in the IgBLAST analysis came from.

-io	IgBLAST output file.

-ut 	Table that will be updated according to what was foun by IgBLAST (orientation, locus). Can be reads or sequences.


The program goes through the IgBLAST output and looks for each query identifier, which is identical with the seq_id in reads or sequences table. For each seq_id, it writes the corresponding segments of 1. and 2. IgBLAST rank to the database. The corresponding VDJ_ids from the library are also looked up and inserted. Orientation and locus are updated in the updatetable, according to whether IgBLAST used the reverse complement and what locus the 1. hit V segment has. Version: IGBLASTN 2.2.28+

1. Open IgBLAST output.

2. Set up the necessary DB queries: insert to VDJ table, select from VDJ_library and update in sequences/reads table.

3. Initialize variables needed to parse from IgBLAST output.

4. Go through each line of IgBLAST output and collect information.

=head1 LOGGED INFORMATION

nothing yet

=head1 AUTHOR

Katharina Imkeller

=cut

use DBI;
use strict;
use warnings;
use Getopt::Long;
use Bio::Seq;
use bcelldb_init;



my $help=0;
my $targettable="";
my $igblastoutput="";
my $updatetable="";

&GetOptions("h!" => \$help,
	"t=s" => \$targettable,
	"io=s"=> \$igblastoutput,
	"ut=s"=> \$updatetable,
);

$help=1 unless $targettable;
$help=1 unless $igblastoutput;
$help=1 unless $updatetable;
exec('perldoc',$0) if $help;



### 0. Logging and database init

select LOG;
my $dbh = get_dbh($conf{database});


### 1. Open IgBLAST output file

open(my $in_igblast,$igblastoutput) or die "opening $igblastoutput failed\n";


### 2. Set up database handles for inserting to VDJ table and updating position

# insert into VDJ table
my $ins_VDJ_sth = $dbh->prepare("INSERT IGNORE INTO $conf{database}.$targettable (seq_id, type, locus, igblast_rank, name, eval, score, VDJ_id) VALUES (?,?,?,?,?,?,?,?)");

# get segment_id and locus from the library
# the new igblast version does not output the locus anymore :(

my $sel_libr_sth = $dbh->prepare("SELECT VDJ_id, locus FROM $conf{library}.VDJ_library WHERE species_id=\"$conf{species}\" AND seg_name=?");

# update orientation and locus only 
my $upd_posloc_sth = $dbh->prepare("UPDATE $conf{database}.$updatetable SET orient=?, locus=?, igblast_productive=? WHERE seq_id=?");


### 3. Initialize the variables needed to parse

# variables needed for scanning through the IgBLAST output
my $count_line = 0;

# variables to store information for each query
my $query_id;
my $VDJ_type;
my $VDJ_locus;
my $igblast_productive = undef;   # This is the correct way to encode "NULL" for Perl DBI


### 4. Go through IgBLAST output and parse.

while(<$in_igblast>) {
	$count_line++;
	chomp;
	my $seq_orient = "F";

    # identify the query and extract id
	if (m/Query:/) {
        (my $comment, my $title, $query_id) = split(/ /, $_);
		next;
	}

	# identify start of rearrangement summary, parse following data
	if (m/rearrangement summary/) {
		$_ = <$in_igblast>;
		$count_line++;
		chomp;

		my @rea_fields = split(/\t/, $_);
		if ($rea_fields[-2] eq "Yes") {
			$igblast_productive = 1;
		} elsif ($rea_fields[-2] eq "No") {
			$igblast_productive = 0;
		}
		next;
	}

	# identify hit table and extract number of hits
	if (m/hits found/){
		my ($comment, $n_hits) = split(/ /, $_);
		my ($count_V, $count_D, $count_J) = (0, 0, 0);

		# read "hit lines" until max number of hits reached
		for (my $i=1; $i<=$n_hits; $i++) {
			$_ = <$in_igblast>;
			$count_line++;
			chomp;

			# split hit line to extract type, locus, segment, quality values
			my @fields = split(/\t/, $_);
			my $VDJ_type = $fields[0];
			my $seq_id = $fields[1];
			my $VDJ_name = $fields[2];
			my $evalue = $fields[11];
			my $score = $fields[12];

			if ($VDJ_name =~ m/:/) {  # needed for mouse GRCm38 database, where position information is part of the FASTA full name
				$VDJ_name = (split /:/, $VDJ_name, 2)[0];
			}
			if ($seq_id =~ m/reversed/) {
				$seq_orient = "R";
			}

			# collect 2 segments of each type
			if ($VDJ_type eq "V" && $count_V <= 1) {
				$count_V++;
				# select id and locus from library
				$sel_libr_sth->execute($VDJ_name);
				my ($VDJ_id, $VDJ_locus) = $sel_libr_sth->fetchrow_array;
				# insert into VDJ table
				$ins_VDJ_sth->execute($query_id, $VDJ_type, $VDJ_locus, $count_V, $VDJ_name, $evalue, $score, $VDJ_id);
				# First V segment is used to determine locus of the sequence update
				if ($count_V == 1) {
					$upd_posloc_sth->execute($seq_orient, $VDJ_locus, $igblast_productive, $query_id);
					$igblast_productive = undef;
				}
			} elsif ($VDJ_type eq "D" && $count_D <= 1) {
				$count_D++;
				$sel_libr_sth->execute($VDJ_name);
				my ($VDJ_id, $VDJ_locus) = $sel_libr_sth->fetchrow_array;
				$ins_VDJ_sth->execute($query_id, $VDJ_type, $VDJ_locus, $count_D, $VDJ_name, $evalue, $score, $VDJ_id);
			} elsif ($VDJ_type eq "J" && $count_J <= 1) {
				$count_J++;
				$sel_libr_sth->execute($VDJ_name);
				my ($VDJ_id, $VDJ_locus) = $sel_libr_sth->fetchrow_array;
				$ins_VDJ_sth->execute($query_id, $VDJ_type, $VDJ_locus, $count_J, $VDJ_name, $evalue, $score, $VDJ_id);
			} elsif ($VDJ_type !~ /[VDJ]/) {
				print "[todb_VDJ.pl][WARNING] Encountered unknown segment type ". $VDJ_type . " in line ". $count_line . " of input file.\n" if ($conf{log_level}>=2);;
			}
		}
	}
}

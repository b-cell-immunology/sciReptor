#!/usr/bin/perl

=pod

=head1 NAME

todb_consensus_tags

=head1 SYNOPSIS 

todb_consensus_tags.pl [-h <help>] -m <experiment_id> -l locus

=head1 DESCRIPTION

write the identifying tags to consensus stats and the corresponding to the reads table

- either all reads that do not yet have a consensus id
- or a list of reads (for updating consensus e.g.)

1. Get a list of all seq_ids that will be processed. This means select all the reads without well_id.

2. Prepare select statement: for a seq_id get the right identifying tags from the database.

3. Prepare database to insert well_id.

4. Go through all the reads, select tags and assign well_id.

5. Select all well_ids that do not yet have a consensus_id assigned.

6. Prepare database: for a certain well_id, select the most common and 2nd most common V-J combination

7. Prepare database: insert into consensus_stats, select all related seq_ids and update consensus_id for these.

8. Go through all the well_ids. Determine V-J combinations, insert to consensus_stats and update reads table consensus_id. 

=head1 LOGGED INFORMATION

- select statement for reads without consensus
- number of reads that will be processed
- reads where F/R tag mapping and orientation do not match
- reads without a correct orientation
- select statement for well ids
- count of well_ids that were processed
- count of sequence ids that resulted (it can be 2 sequences in one well, corresponding to 1. and 2. consensus)

=head1 KNOWN BUGS

=head1 AUTHOR

Katharina Imkeller - imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

Written Jan 2014
Modified Jun 2014 - take locus as argument, so that H,K,L can be run in parallel (faster)
Modified Sep 2014 - 'matrix' replaced by 'experiment_id'

=cut

use strict;
use warnings;
use DBI;
use bcelldb_init;
use Getopt::Long;

my $help=0;
my $experiment_id = "";
my $fixed_locus = "";

&GetOptions("h!" => \$help,
    "m=s" => \$experiment_id,
    "l=s" => \$fixed_locus,
);

$help=1 unless $experiment_id;
$help=1 unless $fixed_locus;
exec('perldoc',$0) if $help;


### 0. Logging and database init

select LOG;
my $dbh = get_dbh($conf{database});




### 1. Get a list of all seq_id that will be processed,
### i.e. all the ones that do not yet have a well id assigned.

my @seq_id_list;
my %seqid_orient_hash;	# to store the orientation of a read
my %seqid_locus_hash;	# to store the locus of a read

# the ones that do not yet have a consensus but at least two tags
my $sel_reads1_sth = $dbh->prepare("SELECT reads.seq_id, orient, locus FROM $conf{database}.reads
	JOIN 
	(SELECT reads_tags.seq_id, COUNT(reads_tags.seq_id) AS cnt FROM $conf{database}.reads_tags 
	GROUP BY reads_tags.seq_id) AS count_tags
	ON count_tags.seq_id = reads.seq_id
	WHERE reads.well_id IS NULL
	AND locus = '$fixed_locus'
	AND orient IS NOT NULL
	AND count_tags.cnt >=2;");
$sel_reads1_sth->execute;
# log select statement
print "Select reads statement: $sel_reads1_sth\n";

# store all ids in a list
# store orientation in a hash
my $count_seqs = 0;
while ( my @seq_id = $sel_reads1_sth->fetchrow_array ) {
	print STDOUT "@seq_id\n";
	my ($seq_id, $orient, $locus) = @seq_id;
	$seqid_orient_hash{$seq_id} = $orient;
	$seqid_locus_hash{$seq_id} = $locus;
	push(@seq_id_list, $seq_id);
	$count_seqs++;
}
# log how many sequences were found
print "$count_seqs reads will be processed.\n";

# status update to STDOUT
print STDOUT "Selected $count_seqs reads for assignment of well id....\n";




### 2. Prepare database query: for a certain seq_id get the right identifying tags from the database

# select all the tags from the database
# forward tag
# looking for max(percid) and min(start)
my $sel_Ftags_sth = $dbh->prepare("SELECT found.tag_id, lib.name
	FROM $conf{database}.reads_tags as found
	JOIN $conf{library}.tags_library as lib
	ON found.tag_id = lib.tag_id
	WHERE seq_id = ?
	AND direction = 'F'
	ORDER BY percid DESC, start ASC
	LIMIT 1;
	");
# forward tag
# looking for max(percid) and max(start)
my $sel_Rtags_sth = $dbh->prepare("SELECT found.tag_id, lib.name
	FROM $conf{database}.reads_tags as found
	JOIN $conf{library}.tags_library as lib
	ON found.tag_id = lib.tag_id
	WHERE seq_id = ?
	AND direction = 'R'
	AND start > $conf{tag_landing_zone}
	ORDER BY percid DESC, start DESC
	LIMIT 1;
	");


### 3. Prepare database to insert well_id
# assign the well id to each previously selected read
# the well id is composed by column and row tag and 1,2 or three for H, K, L
# i.e. CCCRRRL -> INT(7)

# update well_id in reads
my $update_reads_wellid = $dbh->prepare("UPDATE $conf{database}.reads SET well_id = ? WHERE seq_id = ?");



### 4. Go through list of seq_ids
### Select tags and assign well_id


foreach my $seq_id (@seq_id_list) {
	$sel_Ftags_sth->execute($seq_id);
	$sel_Rtags_sth->execute($seq_id);
	my @Ftag = $sel_Ftags_sth->fetchrow_array;
	my ($Ftag_id, $Ftag_name) = @Ftag;
	my @Rtag = $sel_Rtags_sth->fetchrow_array;
	my ($Rtag_id, $Rtag_name) = @Rtag;

	# find out which is row, which is col tag
	my ($rowtag, $coltag) = ("","");
	# warn if the expected orientation of read
	# does not fit the observation from the tags
	
	unless (!$Ftag_name || !$Rtag_name) {
		if (($Ftag_name =~ m/R/) && ($Rtag_name =~ m/C/)) {
			# if forward is R and reverse is C, read orientation should be reverse
			if ($seqid_orient_hash{$seq_id} eq "F") {
				# log: tags and orientation do not match
				print "read $seq_id has a Ftag $Ftag_name and a Rtag $Rtag_name, but an orientation $seqid_orient_hash{$seq_id}\n";
			}
			elsif ($seqid_orient_hash{$seq_id} eq "R") {
				# tags and orientation fit
				# take only the number
				$rowtag = substr $Ftag_name, 1, (length $Ftag_name) -1;
				$coltag = substr $Rtag_name, 1, (length $Rtag_name) -1;
			}
			else {print "read $seq_id has no correct orientation\n";}	# log: no assigned orientation
		}
		elsif (($Ftag_name =~ m/C/) && ($Rtag_name =~ m/R/)) {
			# if forw is C and rev is R, read orientation should be forward
			if ($seqid_orient_hash{$seq_id} eq "R") {
				# log: tags and orientation do not match
				print "read $seq_id has a Ftag $Ftag_name and a Rtag $Rtag_name, but an orientation $seqid_orient_hash{$seq_id}\n";
	
			}
			elsif ($seqid_orient_hash{$seq_id} eq "F") {
				$rowtag = substr $Rtag_name, 1, (length $Ftag_name) -1;
				$coltag = substr $Ftag_name, 1, (length $Rtag_name) -1;
			}
			else {print "read $seq_id has no correct orientation\n"}	# log: no assigned orientation
		}
		
		unless ($rowtag eq "" || $coltag eq "") {
			my %locus_num_hash = (H => '1', K => '2', L => '3');
			my $wellid_name = sprintf("%03d", $coltag) . sprintf("%03d", $rowtag) . "$locus_num_hash{$seqid_locus_hash{$seq_id}}";
			$update_reads_wellid->execute($wellid_name,$seq_id);
			# print "read $seq_id was matched to well_id $wellid_name\n";
		}
	}
}

# status update to STDOUT
print STDOUT "Assigned well ids....\n";

### 5. Now, select all occuring well_ids without consensus_id

my $sel_wellid = $dbh->prepare("SELECT well_id FROM $conf{database}.reads WHERE consensus_id IS NULL AND well_id is NOT NULL GROUP BY well_id;");
$sel_wellid->execute;

# log selection of well id
print "Select well id: $sel_wellid\n";

### 6. Prepare database: for a certain well_id, select the most common and 2nd most common V-J combination

# select 1. and 2. most occuring V_J combinations from sequences with same well_id but without consensus id
# make sure to select only the ones from respective experiment (link to sequencing run)
my $sel_VJs = $dbh->prepare("SELECT Vseg.VDJ_id, Jseg.VDJ_id, COUNT(*) as cnt
	FROM $conf{database}.reads
	JOIN $conf{database}.reads_VDJ_segments as Vseg ON reads.seq_id = Vseg.seq_id
	JOIN $conf{database}.reads_VDJ_segments as Jseg ON reads.seq_id = Jseg.seq_id
	JOIN $conf{database}.sequencing_run ON reads.sequencing_run_id = sequencing_run.sequencing_run_id
	WHERE Vseg.type='V' AND Jseg.type='J'
	AND Vseg.igblast_rank=1 AND Jseg.igblast_rank=1
	AND reads.well_id = ?
	AND sequencing_run.experiment_id = '$experiment_id'
	GROUP BY CONCAT(Vseg.VDJ_id, Jseg.VDJ_id)
	ORDER BY cnt DESC
	LIMIT 2;");


### 7. Prepare database: insert into consensus_stats, select all related seq_ids and update consensus_id for these.

# insert into consensus_stats 
my $ins_consensus = $dbh->prepare("INSERT IGNORE INTO $conf{database}.consensus_stats
	(locus, col_tag, row_tag, best_V, best_J, experiment_id) VALUES (?,?,?,?,?,?)
	ON DUPLICATE KEY UPDATE consensus_id = LAST_INSERT_ID(consensus_id)
	");

# update consensus_id of sequence with right well_id, V and J segment
my $sel_seqids = $dbh->prepare("SELECT reads.seq_id FROM $conf{database}.reads
	JOIN $conf{database}.reads_VDJ_segments as Vseg ON reads.seq_id = Vseg.seq_id
	JOIN $conf{database}.reads_VDJ_segments as Jseg ON reads.seq_id = Jseg.seq_id
	JOIN $conf{database}.sequencing_run ON reads.sequencing_run_id = sequencing_run.sequencing_run_id
	WHERE Vseg.type='V' AND Jseg.type='J'
	AND Vseg.igblast_rank=1 AND Jseg.igblast_rank=1
	AND reads.well_id = ?
	AND sequencing_run.experiment_id = '$experiment_id'
	AND Vseg.VDJ_id = ? AND Jseg.VDJ_id = ?
	AND reads.consensus_id IS NULL
	;");

my $update_consensus = $dbh->prepare("UPDATE $conf{database}.reads SET consensus_id = ? WHERE seq_id = ?;");
my $update_nseqs = $dbh->prepare("UPDATE $conf{database}.consensus_stats SET n_seq = n_seq+? WHERE consensus_id = ?;");


### 8. Go through all the well_ids. Determine V-J combinations, insert to consensus_stats and update reads table consensus_id.

my $count_wellids = 0;
my $count_seq_ids = 0;

while (my @wellid_row = $sel_wellid->fetchrow_array) {
	
	$count_wellids++;
	my $well_id = $wellid_row[0];
	print STDOUT "wellid @wellid_row and $well_id\n";
	
	# convert well_id back to locus, row and col
	my %num_locus_hash = ('1' => 'H', '2' => 'K', '3' => 'L');
	my $locus = $num_locus_hash{(substr $well_id, -1)};
	my $coltag = "C".(substr $well_id,0,3);
	my $rowtag = "R".(substr $well_id,3,3);

	print STDOUT "here $locus $coltag $rowtag\n";

	# get most occuring V_J combinations
	$sel_VJs->execute($well_id);
	while (my @VJ_row = $sel_VJs->fetchrow_array) {
		my ($Vsegm_id, $Jsegm_id) = ($VJ_row[0], $VJ_row[1]);
		
		# insert new consensus
		$ins_consensus->execute($locus, $coltag, $rowtag, $Vsegm_id, $Jsegm_id, $experiment_id);
		my $consensus_id = $dbh->{mysql_insertid};

		#select the corresponding seq_ids
		$sel_seqids->execute($well_id, $Vsegm_id, $Jsegm_id);
		
		my $n_seq = $sel_seqids->rows;
		print STDOUT "$consensus_id nseq $n_seq\n";
		# update the number of sequences in the consensus
		$update_nseqs->execute($n_seq, $consensus_id);

		while (my @seqid_row = $sel_seqids->fetchrow_array) {
			my $sel_seqid = $seqid_row[0]; 
			# update the reads table with consensus_id
			$update_consensus->execute($consensus_id, $sel_seqid);
			print STDOUT "$consensus_id for Vsegm $Vsegm_id, Jsegm $Jsegm_id in wells $well_id\n";
		}
	}
}

print "Total number of well_ids processed: $count_wellids\n";
print "Total number of assigned sequence ids: $count_seq_ids\n";

# status update to STDOUT
print STDOUT "Assigned $count_seq_ids sequence ids to $count_wellids well ids....\n";



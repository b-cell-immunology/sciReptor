#!/usr/bin/perl

=pod

=head1 NAME

todb_constant - insert constant segment usage information into database

=head1 SYNOPSIS

todb_constant.pl -bo <blastoutput> -t <targettable> [-h]

=head1 DESCRIPTION

Open a BLAST output file. Parse the necessary information and write to database.
The identifiers in the BLAST output need to be the same as the seq_id in reads or sequences table.

1. Prepare DB statements: insert into constant table, select id from constant library.

2. Open BLAST output.

3. Parse information from the output.

=head1 LOGGED INFORMATION

- blast output file (source)
- total count of sequences
- nb of inserted constant segments

=head1 AUTHOR

Katharina Imkeller

=cut

use DBI;	
use strict;
use warnings;
use Getopt::Long;
use bcelldb_init;	

my $help=0;
my $noclean=0;
my $blastoutput="";
my $targettable="";

&GetOptions("h!" => \$help,
	"bo=s"	=> \$blastoutput,
	"t=s"	=> \$targettable,
);

$help=1 unless $blastoutput;
$help=1 unless $targettable;
exec('perldoc',$0) if $help;


### 0. Logging

select LOG;
my $dbh = get_dbh($conf{database});
my $dbh_lib = get_dbh($conf{library});



### 1. Prepare statement to get constant_id from library and insert constant information 

# statement to find out which is the corresponding constant_id in the library
# name in the constant_library needs to be unique!!!
my $sel_statem = "SELECT constant_id 
  FROM $conf{library}.constant_library 
  WHERE species_id=\"$conf{species}\" AND name=?";
my $sel_query = $dbh_lib->prepare($sel_statem);

# statement to insert information into constant table
my $ins_statem = "INSERT IGNORE INTO $conf{database}.$targettable 
  (seq_id, name, percid, length, gapopens, readstart, readend, eval, score, constant_id) 
  VALUES (?,?,?,?,?,?,?,?,?,?)";
my $ins_query = $dbh->prepare($ins_statem);


### 2. Open BLAST output

open(my $blast, "<$blastoutput") or die 'BLAST output $blastoutput not found';
# logging
print "\n---------\n$blastoutput was used as blast output file.\n---------\n";


### 3. Parse information

# logging
#print "\n---------\nfollowing seq_id got an entry in $targettable table\n---------\n";
# count inserted seq_ids
my $count_ins = 0;
# count total number of seq_id in blastoutput
my $count_total = 0;

while (<$blast>){
    chomp $_;
    my($seq_id, $hit_name_big, $percid, $length, $mismatches, $gapopens, $readstart, $readend, $conststart, $constend, $evalue, $score) = split(/\t/, $_);
    
	# find out which constant segement was found
	my $hit_name;
	# in the mouse database, there is some extra information in the identifier
    if ($hit_name_big =~ m/:/) {
        my @hit_name_big = split(/:/, $hit_name_big);
        $hit_name = $hit_name_big[0];
    }
	# not in the human database
    else {$hit_name = $hit_name_big;}

	# select the corresponding constant_id from the database
	$sel_query->execute($hit_name);
	my $lib = $sel_query->fetchrow_hashref();
	my $constant_id = $lib->{constant_id};

	# insert into database
	my $ins_bool = $ins_query->execute(
        $seq_id,
        $hit_name,
        $percid,
        $length,
        $gapopens,
        $readstart,
        $readend,
        $evalue,
        $score,
	$constant_id,
    );
	# increase total counting
	$count_total++;
	# update inserted count
	$count_ins += $ins_bool;
	# log sequences that were not inserted
	#print "$seq_id bool $ins_bool\n";
	if ($ins_bool eq 1) {
		#print "$seq_id\n";
	}
	else {
		print "\nseq_id $seq_id constant was not inserted because it already is in the table!\n" unless $ins_bool;
	}
}

print "\n---------\ntotal $count_total sequences processed\n";
print "$count_ins inserted\n---------\n\n";

close($blast);

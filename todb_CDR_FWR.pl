#!/usr/bin/perl -w

=pod

=head1 NAME

todb_CDR_FWR

=head1 SYNOPSIS

todb_CDR_FWR.pl -io <igblastoutput> [-h]

=head1 DESCRIPTION

Write CDR/FWR DNA and protein sequences and length to the database. Also include warnings table.

Get input sequences of Ig genes from DB.sequences, get CDR/FWR positions from previous IgBLAST output. 
Up to CDR2 regions are directly identified using the positions indicated by IgBLAST. 
Additionally determine FWR3, CDR3, J and constant rest according to sequence motifs (regular expressions listed in config). From FWR3 end the region for motif search is (-15,100). Split into subsequences and write to database.

1. Prepare insert statements for CDR/FWRs, Prepare subroutines (they need the insert statements, thus the order!)
2. get query_ids and CDR/FWR positions from IgBLAST output, retrieve sequence from DB --> LOOP OVER IgBLAST OUTPUT
3. parse the positions from the IgBLAST output
4. Split sequence in regions and write to database

=head1 LOGGED INFORMATION

TO DO: Nb of queries for each chain, Nb of regions for each, but this can also later on be read from the db.

=head1 KNOWN BUGS

The regular expressions in the config file are critical, there is no warning in case they are modified.
They need to be compatible to perl regexp, but also not cause no problems when used as bash source.

=head1 AUTHOR

Katharina Imkeller - imkeller@mpiib-berlin.mpg.de

=head1 HISTORY

Written Dec 2013

=cut

use DBI;
use strict;
use Getopt::Long;
use Bio::SeqIO;
use Bio::Seq;
use bcelldb_init;

my $help=0;
my $igblast_output="";

&GetOptions("h!" => \$help,
	"io=s" => \$igblast_output,
);

$help=1 unless $igblast_output;
exec('perldoc',$0) if $help;


### 0. Logging

select LOG;
my $dbh = get_dbh($conf{database});

###
### 1. Prepare subroutines insertment statements to database 
###

# get sequence from database
my $sel_sequence = $dbh->prepare("SELECT locus, orient, seq \
  FROM $conf{database}.sequences WHERE seq_id = ?;");

# insert into CDR_FWR table
my $ins_regions = $dbh->prepare("INSERT IGNORE \
  INTO $conf{database}.CDR_FWR (seq_id, region, start, end, dna_seq, prot_seq, prot_length, stop_codon) \
  VALUES (?,?,?,?,?,?,?,?)");

# insert into warnings
my $ins_warnings = $dbh->prepare("INSERT IGNORE \
  INTO $conf{database}.warnings (seq_id, FWR3_igblast_output, CDR3_start_C, CDR3_end, alt_CDR3_end, J_end) \
  VALUES (?,?,?,?,?,?)");


### define subroutines

# initialize variables that are allready needed to define the subroutines
my %seq_id_sequence;
my %seq_id_locus;

sub revcomp {
	# creates the reverse complement of a dna sequence
	# 1 argument: dna sequence string
	# returns: reverse complement

    my $dna = shift;
    my $revcomp = reverse($dna);
    $revcomp =~ tr/ACGTacgt/TGCAtgca/;
    return $revcomp
}


sub get_regions {
	# inserts one region into the database
	# 4 argument:
	#	type	the type of region (e.g. CDR1)
	#	start	start position of the region (nucleotide level)
	#	stop	stop position of the region (nucleotide level)
	#	seq_id	sequence id according to the one in DB.sequences (to get actual sequence)
	 
	my $type = shift;
	my $start = shift;
	my $end = shift;
	my $seq_id = shift;
	my $sequence = $seq_id_sequence{$seq_id};
	my $dna_seq = substr($sequence, $start - 1, $end - $start + 1);
	my $nucobj = Bio::Seq->new(-seq => $dna_seq,
			-id => "nucleotides");
	my $protobj = $nucobj -> translate;
	my $prot_seq = $protobj -> seq;
	my $prot_length = length $prot_seq;
 	my $stop_codon;
	if (index($prot_seq, "*") != -1) {
		$stop_codon = "T";
	}
	else { $stop_codon = "F"; }

	$ins_regions->execute($seq_id,
		$type,
		$start,
		$end,
		$dna_seq,
		$prot_seq,
		$prot_length,
		$stop_codon);
}


###
### 2. get query_ids and CDR/FWR positions from IgBLAST output
###

open(IN_IgBLAST,$igblast_output) or die "opening $igblast_output failed\n";

# variables needed for scanning through the IgBLAST output
my $count_line = 0;
my $count_query = 0;
my $summary_mark = 0;

# variables to store information for each query
my $query_id;
my $query_length;
my $orient;
my @seq_array;
my ($FWR3_start, $FWR3_end, $CDR3_start, $CDR3_end);
my ($type, $start, $end);

# go through IgBLAST output and extract query_id and CDR/FWR positions
while(<IN_IgBLAST>) {
	$count_line++;
	chomp $_;

		# identify the query
	if ($_ =~ m/Query:/) {
		#print $_."\n";
		$count_query++;
		# split the query line to extract the id
		(my $comment, my $title, $query_id) = split(/ /, $_);
		# reset the variables
		# needed, in case IgBLAST output not complete for certain query	
		($type, $start, $end) = split(/ /, "N/A " x 3);	
		($FWR3_start, $FWR3_end, $CDR3_start, $CDR3_end) = split(/ /, "N/A " x 4);


		# get the corresponding sequence with orientation and locus
		$sel_sequence->execute($query_id);
		@seq_array = $sel_sequence->fetchrow_array;
		# locus
		$seq_id_locus{$query_id} = $seq_array[0];
		# orientation
		$orient = $seq_array[1];
		# sequence
		if ($orient eq "R") {$seq_id_sequence{$query_id} = revcomp($seq_array[2]);}
		elsif ($orient eq "F") {$seq_id_sequence{$query_id} = $seq_array[2];}
		# length of the query id sequence
		$query_length = length $seq_id_sequence{$query_id};	
	}

	# look where alignment summary starts
	elsif ($_ =~ m/Alignment summary/) {
		$summary_mark = $count_line;
	}

	###
	### 3. extract the positions from the alignment summary
	###
	elsif ($count_line >= $summary_mark + 1 && $count_line <= $summary_mark + 6 && $count_line >10) {
		# split the lines of the alignment summary and extract type, start and stop
		my @all = split(/\t/, $_);
		my $l = @all;
		if($l > 0){
	    	($type, $start, $end) = @all[0 .. 2];
	    	my @type = split(/ /, $type);
	    	$type = $type[0];
		}
		# write the positions and sequences for regions until CDR2 into output
		my @simple_regions = ("FWR1", "CDR1", "FWR2", "CDR2");
		if (grep { $_ eq $type } @simple_regions) {
			unless ($start eq "N/A") { 
				get_regions($type, $start, $end, $query_id);
			}
		}
		if ($type eq "FWR3") {
			# store the positions of FWR3
			# since looking for CDR3 is more difficult, it will be done separately
			# and using the information about FWR3
			$FWR3_start = $start;
			$FWR3_end = $end;
		}
	}
	
	
	###
	### 4. Split sequence in regions and write to database
	###
	elsif ($_ =~ m/IGBLAST/ && $count_line >=3 ) {
		# at the end of a new query (count_line>3 to skip the first line of IgBLAST output)
		# deal with the rest of the sequence to extract positions of CDR3, J, etc.
		# CDR3 positions have not been initialized yet, since they do not appear in the IgBLAST output 
		# or we like to define them differently

	    # for each locus a different AA motif indicates the end of CDR3 region
	    # locus, i.e. chain types: "h", "k", "l"
 		my %CDR3_end_motif = ( "H" => "$conf{h_CDR3_e}",
			"K" => "$conf{k_CDR3_e}",
			"L" => "$conf{l_CDR3_e}"
			);	
		# alternativ CDR3_end motif (if first one could not be found)
		my %alt_CDR3_end_motif = ( "H" => {1 => "$conf{h_altCDR3_e1}", 2 => "$conf{h_altCDR3_e2}", 3 => "$conf{h_altCDR3_e3}"},
			"K" => {1 => "$conf{k_altCDR3_e1}", 2 => "$conf{k_altCDR3_e2}", 3 => "$conf{k_altCDR3_e3}"},
			"L" => {1 => "$conf{l_altCDR3_e1}", 2 => "$conf{l_altCDR3_e2}", 3 => "$conf{l_altCDR3_e3}"}
			);
		# J segment end motif
		my %J_end_motif = ( "H" => "$conf{h_Jend}",
			"K" => "$conf{k_Jend}",
			"L" => "$conf{l_Jend}"
			);

		# initialize variables for warnings table
		my $FWR3_igblast_output = 0;
		my $CDR3_start_C = 0;
		my $CDR3_end_motif = 0;
		my $alt_CDR3_end = 0;
		my $J_end = 0;

		
		unless ($FWR3_start eq "N/A") { 
			$FWR3_igblast_output = 1;
		    	# find region that should contain the CDR3 
		    	my $FWR3dna_length = $FWR3_end-$FWR3_start + 1;
	    		my $frame_overhang = $FWR3dna_length % 3;
	    
	    		my $critregion_start = $FWR3_start + ($FWR3dna_length - $frame_overhang - 15);
			my $sequence = $seq_id_sequence{$query_id};
	    		my $critregion =  substr($sequence, $critregion_start - 1, 115);
	    		my $critdnaobj = Bio::Seq->new(-seq => $critregion,
					   -id => "nucleotides");
	    		my $critprotobj = $critdnaobj -> translate;
	    		my $critprot = $critprotobj -> seq;
	    
	    		# find actual CDR3 in terms of aa
	    		my $CDR3protend = "N/A";
	    		my $CDR3protstart = "N/A";
	    		if ($critprot =~ m/C/g) {
				$CDR3protstart = pos $critprot;
				$CDR3_start_C = 1;
	    		}

			# go on with looking for CDR3 end motif
	    		my ($rest_J_protstart, $rest_J_protend, $rest_const_protstart, $rest_const_protend) = ("N/A","N/A","N/A","N/A");
			if ($critprot =~ m/$CDR3_end_motif{$seq_id_locus{$query_id}}/g) {
		    		$CDR3protend = pos $critprot;
		    		$CDR3protend = $CDR3protend - 5;
		    		$rest_J_protstart = $CDR3protend+1;
				$CDR3_end_motif = 1;
			}
			if (($critprot =~ m/$alt_CDR3_end_motif{$seq_id_locus{$query_id}}{1}/g) || ($critprot =~ m/$alt_CDR3_end_motif{$seq_id_locus{$query_id}}{2}/g) || ($critprot =~ m/$alt_CDR3_end_motif{$seq_id_locus{$query_id}}{3}/g)) {
			    		$CDR3protend = pos $critprot;
			    		$CDR3protend = $CDR3protend - 5;
			    		$rest_J_protstart = $CDR3protend+1;
					$alt_CDR3_end = 1;
			}	
			# look for necessary AA motif and adjust rest protein positions
		    	if ($critprot =~ m/$J_end_motif{$seq_id_locus{$query_id}}/g) {
				$rest_const_protstart = pos($critprot);
				$rest_J_protend = $rest_const_protstart - 1; 
		   		$J_end = 1;
			}
		   	if ($CDR3_end_motif == 0 && ($alt_CDR3_end == 0 || $J_end ==0)) {
				$CDR3protend = "N/A";
				$rest_J_protstart = "N/A";
			}
		
			if ($CDR3protstart ne "N/A" && $CDR3protend ne "N/A"){
				my $CDR3 = substr($critprot, $CDR3protstart, ($CDR3protend-$CDR3protstart+1));
				my $CDR3_length = length $CDR3;
				my $CDR3dna_length = $CDR3_length * 3;
				# reset FWR3 end if necessary
				$FWR3_end = $critregion_start + 3*$CDR3protstart -1;
				$CDR3_start = $FWR3_end + 1;
				$CDR3_end = $CDR3_start + $CDR3dna_length - 1;
				get_regions("CDR3", $CDR3_start, $CDR3_end, $query_id);
		    	}	
			# write regions for FWR3 into output 
			# this is done here, due to optional reseting, after CDR3 was localized
			get_regions("FWR3", $FWR3_start, $FWR3_end, $query_id); 
			if (($rest_J_protstart ne "N/A") && ($rest_J_protend ne "N/A")) {
				my $rest_J_start = $critregion_start + 3*$rest_J_protstart;
				my $rest_J_end = $critregion_start + 3*($rest_J_protend+1) -1;
				get_regions("rest_J", $rest_J_start, $rest_J_end, $query_id);
		    	}
		    	if (($rest_const_protstart ne "N/A") && ($rest_J_protend ne "N/A")) {
				my $rest_const_start = $critregion_start + 3*$rest_const_protstart;
				my $rest_const_end = $query_length;
				get_regions("rest_const", $rest_const_start, $rest_const_end, $query_id);
		    	}
		}
		# print warning if its not empty
		$ins_warnings->execute($query_id, $FWR3_igblast_output ,$CDR3_start_C, $CDR3_end_motif, $alt_CDR3_end, $J_end);
	}
}


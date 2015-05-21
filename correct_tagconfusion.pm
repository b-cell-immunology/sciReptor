package correct_tagconfusion;

=pod

=head1 NAME

correct_tagconfusion

=head1 DESCRIPTION

This module is called by todb_sampleinfo_highth.pl in order to correctly assign the event_id, even when when tags are in the wrong positions (problems
in the primer matrix) or plates got mixed up during processing.

Use correct_tags($tag_column, $tag_row, $locus)) with $tag_(column|row) =~ [RC][0-9][0-9][0-9] and $locus =~ [HKL] to return correct tag name. The
information which of the following correction to apply is set via the "tag_correction" key in the config file:

B< none >	(implemented Jan 2014): No correction (default).

B< tag_batch >	(implemented Jan 2014):	Correct for a switch of lambda tags in the tag batch Mm_AGM_002 240x256 matrix. This switch occurred during
primer manufacturing and is already	present	in the primer master plate:
For plate rows 1-12 (physical rows 1-192), lambda reads located in the even physical rows and odd plate rows appear to be located one plate row 
(16 physical rows) below, while those located in even physical rows and even plate rows appear to be located one plate row above. Reads in odd physical
rows appear at the correct position.

B< D01_plateposition >	(implemented Feb 2014):	Correct for plate swapping in D01 experiment:
Kappa chain Row1-16:Col25-48 is exchanged by Row17-32:Col1-24 and vice versa.

=head1 AUTHOR

Katharina Imkeller

=cut

use DBI;
use POSIX;	#ceil function
use strict;
use warnings;
use Bio::Seq;
use bcelldb_init;


#### mouse matrix 240_256, tags mixed due to wrong pipetting

sub correct_tags_240_256_1 {

	my $old_tag_1 = shift;
	my $locus_1 = shift;
	our $new_tag_1;
	my $old_tag_num;
	my $new_tag_num;
	
	unless ($locus_1 eq "L") { # only lambda
		return $old_tag_1;
		last;
	}

	if ($old_tag_1 =~ m/R/) {	# only row tags
		
		$old_tag_num = substr $old_tag_1, 1, 3;
		$old_tag_num = int($old_tag_num);

		if ($old_tag_num <= 192 && $old_tag_num%2 == 0) {	# plates 1-12: every second row...
			if ( ceil($old_tag_num/16) % 2 == 0 ) {	# ... on a even plate number ...
				$new_tag_num = $old_tag_num - 16;	# ... is actually 16 rows up
			}
			else {	# ... on uneven plates ...
				$new_tag_num = $old_tag_num + 16;	# ... is actually 16 rows down
			}
		}

		else {	# row%2 != 0
			$new_tag_num = $old_tag_num;
		}
			
		$new_tag_1 = "R".sprintf("%03d", $new_tag_num);


	}
	
	else {	# col tag
		$new_tag_1 = $old_tag_1;
	}

	return $new_tag_1;
}


### Experiment D01

sub correct_tags_D01_2 {

	# Kappa chain Row1-16:Col25-48 is exchanged by Row17-32:Col1:24 and vice versa
	
	my $old_col_tag_2 = shift;
	my $old_row_tag_2 = shift;
	my $locus_2 = shift;
	our $new_col_tag_2;
	our $new_row_tag_2;

	my $old_col_tag_num;
	my $new_col_tag_num;	
	my $old_row_tag_num;
	my $new_row_tag_num;
	
	print STDOUT "old_col_tag_2: $old_col_tag_2\nold_row_tag_2: $old_row_tag_2\nlocus_2: $locus_2\n";


	if ($locus_2 ne 'K') { # confusion only kappa
		print STDOUT "locus not K\n\n";
		return ($old_col_tag_2, $old_row_tag_2);
	}
	
	else {
		$old_col_tag_num = substr $old_col_tag_2, 1, 3;
		$old_col_tag_num = int($old_col_tag_num);	
		$old_row_tag_num = substr $old_row_tag_2, 1, 3;
		$old_row_tag_num = int($old_row_tag_num);

		# plate 3
		if ($old_row_tag_num >= 0 && $old_row_tag_num <= 16 && $old_col_tag_num >= 25 && $old_col_tag_num <= 48) {
			# move up right to plate 2
			$new_row_tag_num = $old_row_tag_num + 16;
			$new_col_tag_num = $old_col_tag_num - 24;
		}
	
		# plate 2
		elsif ($old_row_tag_num >= 17 && $old_row_tag_num <= 32 && $old_col_tag_num >= 1 && $old_col_tag_num <= 24) {
			# move left down to plate 3
			$new_row_tag_num = $old_row_tag_num - 16;
			$new_col_tag_num = $old_col_tag_num + 24;
		}

		else {
			$new_row_tag_num = $old_row_tag_num;
			$new_col_tag_num = $old_col_tag_num;
		}
	
		$new_col_tag_2 = "C".sprintf("%03d", $new_col_tag_num);
		$new_row_tag_2 = "R".sprintf("%03d", $new_row_tag_num);

		print STDOUT "ELSE returning $new_col_tag_2, $new_row_tag_2\n\n";
		return ($new_col_tag_2, $new_row_tag_2);
	}
	
}

#####
# MAIN
#####

sub correct_tags {
	our $col_tag_main = shift;
	our $row_tag_main = shift;
	our $locus_main = shift;
	our $new_col_tag_main;
	our $new_row_tag_main;

	if ($conf{tag_correction} eq "tag_batch") {
		$new_row_tag_main = correct_tags_240_256_1($row_tag_main, $locus_main);
		$new_col_tag_main = $col_tag_main;
	}

	elsif ($conf{tag_correction} eq "D01_plateposition") {
		($new_col_tag_main, $new_row_tag_main) = correct_tags_D01_2($col_tag_main, $row_tag_main, $locus_main);
	}

	else {
		$new_col_tag_main = $col_tag_main;
		$new_row_tag_main = $row_tag_main;

	}	
	return ($new_col_tag_main, $new_row_tag_main);
}

1;

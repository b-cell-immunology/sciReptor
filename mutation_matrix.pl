#!/usr/bin/perl

=pod

=head1 NAME

mutation_matrix

=head1 SYNOPSIS

mutation_matrix.pl [-h]

=head1 DESCRIPTION

Generate a matrix of mutation counts between all possible codons. Each column/row of the matrix corresponds to one codon. The matrix entries indicate how many mutations are at least necessary to get from one codon to the other. The matrix is generated once and then used as reference by todb_mutations_from_align.

The underlying model for mutations assumes the lowest number of mutations and does not differentiate between nucleotides.

=head1 AUTHOR

Katharina Imkeller

=cut


use warnings;
use strict;
use Getopt::Long;
use Bio::Seq;

my $help=0;

&GetOptions("h!" => \$help,
);

exec('perldoc',$0) if $help;

# calculate hamming distance
sub hd {
    return ($_[0] ^ $_[1]) =~ tr/\001-\255//;
}

# return 1, if amino acids of two codons are not the same
sub aa_mutation {
	my $dna1 = Bio::Seq->new(-seq => $_[0], -alphabet => 'dna');
	my $dna2 = Bio::Seq->new(-seq => $_[1], -alphabet => 'dna');
	my $aa1 = $dna1->translate();
	my $aa2 = $dna2->translate();
	#print "dna".$dna1->seq.$dna2->seq."\nprot".$aa1->seq.$aa2->seq."\n";
	my $result = 0;
	$result = 1 unless ($aa1->seq eq $aa2->seq);
	return $result;
}


# generate matrix with all codons
my @characters = ("A", "C", "G", "T", "-");
my @codons = ();
my @poss_parents = ();
my @poss_daughters = ();


# open output file
open(my $mutation_table, ">mutation_matrix.txt");

# create a list with all possible nucleotides
foreach my $nuc1 (@characters) {
	foreach my $nuc2 (@characters) {
		foreach my $nuc3 (@characters) {
			my $codon = $nuc1.$nuc2.$nuc3;
			push(@codons, $codon);
		}
	}
}

print scalar @codons;

foreach my $obs_codon (@codons) {
	foreach my $germ_codon (@codons) {

		my ($insertion, $deletion, $mutation, $n_repl, $n_silent) = (0,0,0,0,0);
		my @weight = ();
		my @germ_nucl = (substr($germ_codon,0,1), substr($germ_codon,1,1), substr($germ_codon,2,1));

		my @obs_nucl = (substr($obs_codon,0,1), substr($obs_codon,1,1), substr($obs_codon,2,1));


		my $h_dist = hd($obs_codon,$germ_codon);
#		print "$germ_codon $obs_codon $h_dist\n";
		unless ($h_dist == 0) {
			if ($obs_codon =~ m/-/ || $germ_codon =~ m/-/) {
				# deletion: gap in observed
				$deletion = $obs_codon =~ tr\-\\;
				# insertion: gap in germline
				$insertion = $germ_codon =~ tr\-\\;
				# if the hamming distance is still bigger then max(ins,del), there is a mutation (no negative mutation count)
				for (my $i=0; $i < 3; $i++) {
					#print "$germ_nucl[$i] eq $obs_nucl[$i]\n";
					unless ($germ_nucl[$i] eq $obs_nucl[$i] || $germ_nucl[$i] eq "-" || $obs_nucl[$i] eq "-") {
						$mutation++;
					}
				}	
				
			}
			else {

				###
				### FIRST STEP
				###
				
				@poss_parents = (
					$germ_codon, 
					$germ_codon, 
					$germ_codon, 
					$germ_codon, 
					$germ_codon, 
					$germ_codon);

				@poss_daughters = (
					$obs_nucl[0].$germ_nucl[1].$germ_nucl[2],
					$obs_nucl[0].$germ_nucl[1].$germ_nucl[2],
					$germ_nucl[0].$obs_nucl[1].$germ_nucl[2],
					$germ_nucl[0].$obs_nucl[1].$germ_nucl[2],
					$germ_nucl[0].$germ_nucl[1].$obs_nucl[2],
					$germ_nucl[0].$germ_nucl[1].$obs_nucl[2]
				);
				
				#print "1.\n@poss_parents\n@poss_daughters\n";

				for (my $i = 0; $i < 6; $i++) {
					$weight[$i] += aa_mutation($poss_parents[$i],$poss_daughters[$i]);
				}

				###
				### SECOND STEP
				###

				@poss_parents = @poss_daughters;

				@poss_daughters = (
					$obs_nucl[0].$obs_nucl[1].$germ_nucl[2],
					$obs_nucl[0].$germ_nucl[1].$obs_nucl[2],
					$obs_nucl[0].$obs_nucl[1].$germ_nucl[2],
					$germ_nucl[0].$obs_nucl[1].$obs_nucl[2],
					$obs_nucl[0].$germ_nucl[1].$obs_nucl[2],
					$germ_nucl[0].$obs_nucl[1].$obs_nucl[2]
				);
				
				#print "2.\n@poss_parents\n@poss_daughters\n";

				for (my $i = 0; $i < 6; $i++) {
					$weight[$i] += aa_mutation($poss_parents[$i],$poss_daughters[$i]);
				}

				###
				### THIRD STEP
				###
				
				@poss_parents = @poss_daughters;

				my @poss_daughters = (
					$obs_codon, 
					$obs_codon, 
					$obs_codon, 
					$obs_codon, 
					$obs_codon, 
					$obs_codon 
				);
				
				#print "3.\n@poss_parents\n@poss_daughters\n";

				for (my $i = 0; $i < 6; $i++) {
					$weight[$i] += aa_mutation($poss_parents[$i],$poss_daughters[$i]);
				}


			my @weight_min = sort({$a <=> $b}@weight);
			$n_repl = $weight_min[0];
			$n_silent = $h_dist - $n_repl;

			}
		}
		print $mutation_table "$obs_codon\t$germ_codon\t$mutation\t$n_repl\t$n_silent\t$insertion\t$deletion\n";	
	}
}
 

#!/usr/bin/perl

=pod

=head1 NAME

=head1 SYNOPSIS

perform_muscle.pl -f <fastain> -aln <alignout>

=head1 DESCRIPTION

Call MUSCLE to perform multiple alignment. This is done in an extra perl script to be able to log to database.

=head1 AUTHOR

Katharina Imkeller

=head1 HISTORY

Written Jan 2014
Modified Mar 2014 (Documentation + logging with capture)

=cut

use strict;
use bcelldb_init;
use Getopt::Long;
use DBI;
use Capture::Tiny 'capture';

my $help=0;
my $fastain="";
my $alignout="";

&GetOptions("h!" => \$help,
	"f=s" => \$fastain,
	"aln=s"=> \$alignout,
);

$help=1 unless $fastain;
$help=1 unless $alignout;
exec('perldoc',$0) if $help;


### 0. Logging and database init

select LOG;

### 1. Call MUSCLE


my ($stdout, $stderr, $return) = capture {
  system "/usr/bin/muscle -in $fastain -maxiters 1 -quiet -out $alignout";
};

print "STDOUT: $stdout\n";
print "STDERR: $stderr\n";
print "Return: $return\n";




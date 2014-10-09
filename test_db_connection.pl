#!/usr/bin/perl
#
=pod

=head1 NAME

test_db_connection [-d database2 ]


=head1 DESCRIPTION

use bcell_init to connect to the database
in the config file and performs the logging.

shows a list of tables in database2

=head1 AUTHOR

Peter Arndt, arndt@molgen.mpg.de

=cut


use strict;
use DBI;
use Getopt::Long;
use bcelldb_init;



my $help=0;
my $db="";

&GetOptions("h!" => \$help,
		"db=s" => \$db,
);
exec('perldoc',$0) if $help;

print LOG "start\n";



my $dbh=get_dbh($db);
my $sth = $dbh->prepare("show tables;");
$sth->execute();

while (my @row = $sth->fetchrow_array ) {
	print "@row\n";
}
$dbh->disconnect;

print LOG "end\n";


# Perl module used for:
# 	- logging processes to the database; every calling of the module logs the calling main method (user, machine, command line arguments, ...)
# 	- returning database handles (with configurations in the .my.cnf file in your home directory)
#
# Author: Peter Arndt
# Date: Dec 2013
#


package bcelldb_init;
 
 
use strict;
use warnings;
use Getopt::Long qw(:config pass_through);
use DBI;

our $VERSION = '1.00';
use base 'Exporter';
our @EXPORT = qw(*LOG %conf $dry_run get_dbh);

my $log_buffer="";
my $log_id=0;
our %conf;
our $dry_run=0;



sub start_log
{
	open(LOG,'>',\$log_buffer);

	# log some basics

	print LOG "date:    ",`date`;
	print LOG "hostname:",`hostname`;
	print LOG "pwd:     ",`pwd`;
	print LOG "CPUs:    ",`grep -c processor /proc/cpuinfo`;
	my $command_line=$0 ." ". join " ",@main::ARGV;
	print LOG "$command_line\n";
	print LOG "-"x60 ,"\n";

	# search for a config file

	my $config_file="config";
	unless (-f $config_file){
		$config_file="../$config_file";
	}
	&GetOptions("config=s" => \$config_file); 

	# parse config file 

	my $CONF;
	open($CONF,"<$config_file") || die "no config file \"$config_file\"";
	while (<$CONF>){
		if ( (m/^\s*#/) || ( ! m/=/ )){
			print LOG $_;   	# write comments to the log
			next;					# but do nor parse them
		}
		my ($key,$value) = $_ =~ m/^\s*(\S+)\s*=\s*(.*?)\s*$/;
		$conf{$key}=$value;
		if ($key eq "dbpass"){
			s/=.*/= ***/;   # let the password disappear
		}
		print LOG $_;
	}
	close($CONF);	
	print LOG "-"x60 ,"\n";

	# check for dry_run

	&GetOptions("dry_run!" => \$dry_run); 

	# open a connection to the db and insert logging info into log_table
	
	if (!$dry_run){
		my $dbh = get_dbh();
		my $ra=$dbh->do("INSERT INTO log_table 
			values(0,NOW(),\"$conf{version}\",\"$ENV{USER}\",user(),\"$command_line\",\"\")");
		die "no insert possible" unless $ra==1;
		$log_id=$dbh->last_insert_id("","","","");
		$dbh->disconnect;
	}
}


sub stop_log
{
	if (!$dry_run){
		my $dbh = get_dbh();
		close(LOG);
		select STDOUT;
		my $ra=$dbh->do("UPDATE log_table SET output='$log_buffer' where log_id=$log_id");
		$dbh->disconnect;
	}else{
		close(LOG);
		select STDOUT;
		print "\nDRY_RUN\nLOG:\n$log_buffer\n\n";
	}
}


sub get_dbh
{
	my $database=shift; 
	$database = $conf{database} unless $database;

	my $dsn;
	my $dbh;
	my $msg;

	my $mycnf		=($conf{dbmycnf} ? $conf{dbmycnf}: "$ENV{HOME}/.my.cnf" );
	my $mysql_group	=($conf{dbmysql_group} ? $conf{dbmysql_group}:  'mysql_igdb');

	if (-f $mycnf){
		$dsn="DBI:mysql:$database;mysql_read_default_file=$mycnf"
    	.";mysql_read_default_group=$mysql_group;";
		#print STDERR "$dsn\n";
	
		$dbh = DBI->connect($dsn,undef,undef,{PrintError=>0});
		#warn "unable to connect using .my.cnf configuartion:$dsn\n" unless $dbh;
		$msg = "db connect through configuartion:$dsn\n"
	}
	unless ($dbh){
		#print STDERR "trying ...\n";
		my $host	=($conf{dbhost} ? $conf{dbhost}:  'curry-d130');
		my $user	=($conf{dbuser} ? $conf{dbuser}:  $ENV{USER});
		my $password=($conf{dbpass} ? $conf{dbpass}:  "");
		my $port	=($conf{dbport} ? $conf{dbport}:  3306);

		my $dsn="DBI:mysql:database=$database;host=$host;port=$port";
		#print STDERR "$dsn\n";
		$dbh = DBI->connect($dsn,$user,$password,{PrintError=>0}) ||
			die "unable to connect using dsn:$dsn";
		$msg = "db connect through user/password from config:$dsn\n";
		$msg.= "THIS WAY TO CONNECT TO THE DB IS DEPRECATED - use a ~/.my.cnf file! \n";
	}
	$dbh->{RaiseError}=1;
	$dbh->{PrintError}=1;
	print LOG $msg;
	return $dbh;
}


INIT{ start_log(); }


END{ stop_log(); } 

1;


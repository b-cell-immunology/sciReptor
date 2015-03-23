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

my $regexp_key_value = qr /^\s*([_A-Za-z][_0-9A-Za-z]+)=(.*?)\s*;?\s*$/;

sub start_log
{
	open(LOG,'>',\$log_buffer);

	# log some basics
	#
	print LOG "date:    ",`date`;
	print LOG "hostname:",`hostname`;
	print LOG "pwd:     ",`pwd`;
	print LOG "CPUs:    ",`grep -c processor /proc/cpuinfo`;
	my $command_line=$0 ." ". join " ",@main::ARGV;
	print LOG "$command_line\n";
	print LOG "-"x60 ,"\n";

	# search and open config file
	#
	my $config_file="config";
	unless (-f $config_file){
			$config_file="../$config_file";
	}
	&GetOptions("config=s" => \$config_file);

	my $fh_config;
	open($fh_config,"<$config_file") || die "ERROR:  no config file \"$config_file\"";

	# Parse the config file:
	# - comment lines (starting with "#") go to log, but are not processed
	# - lines which are empty or only contain white space characters are ignored
	# - <key>=<value> lines are parsed, including variable expansion
	# - all other lines will trigger a warning and will subsequently be ignored
	#
	while (<$fh_config>){
		chomp;
		if ( /^\s*#/ ) {
			print LOG $_ ."\n";
			next;
		} elsif ( /^\s*$/ ) {
			next;
		} elsif ( $regexp_key_value ) {
			my ($key,$value) = $_ =~ $regexp_key_value;
			
			# Expand BASH variables ("${VARIABLE}"). Give precedence to values from config file itself,
			# then look in the global environment.
			#
			while ($value =~ /\$\{([_A-Za-z][_0-9A-Za-z]+)\}/g) {
				my $env_name = $1;
				my $expanded_variable="";
				if (exists($conf{$env_name})){
					$expanded_variable=$conf{$env_name};
				} elsif (exists($ENV{$env_name})) {
					$expanded_variable=$ENV{$env_name};
				}
				$value =~ s/\$\{$env_name\}/$expanded_variable/;
			}
			$conf{$key} = $value;

			# Do not show the database password in log file
			#
			if ($key eq "dbpass"){
				s/=.*/= ***/;   
			}

			print LOG "Parsed: " . $key . "=" . $value . "\n"

		} else {
			print LOG "WARNING : Ignoring invalid config line: " . $_ . "\n";
		}
	}
	close($fh_config);
	print LOG "-"x60 ,"\n";

	# check for dry_run, if not open a connection to the db and insert logging info into log_table
	#
	&GetOptions("dry_run!" => \$dry_run);
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
#	(my $caller_package, my $caller_filename, my $caller_line) = caller;
#	print "[bcelldb_init.pm][DEBUG+] caller stop_log: package: $caller_package, filename: $caller_filename, line: $caller_line\n";
	if (!$dry_run){
		my $dbh = get_dbh();
		close(LOG);
		select STDOUT;
		my @array_log_buffer = split(/\n/, $log_buffer);
		print "[bcelldb_init.pm][DEBUG] Size of log_buffer: " . length($log_buffer) . " Lines of log_buffer: " . scalar @array_log_buffer . " \n" if ($conf{log_level}>=4);
		my $status_update = $dbh->do("UPDATE log_table SET output='$log_buffer' where log_id=$log_id");
		if ($status_update) {
			print "[bcelldb_init.pm][DEBUG] Number of rows updated in log_table: $status_update \n" if ($conf{log_level}>=4);
		} else {
			print "[bcelldb_init.pm][ERROR] Update of log_table failed: " . $dbh->errstr . "\n" if ($conf{log_level}>=1);
		}
		$dbh->disconnect;
	} else {
		close(LOG);
		select STDOUT;
		#print "\nDRY_RUN\nLOG:\n$log_buffer\n\n";
	}
}


sub get_dbh
{
#	(my $caller_package, my $caller_filename, my $caller_line) = caller;
#	print "[bcelldb_init.pm][DEBUG+] caller get_dbh: package: $caller_package, filename: $caller_filename, line: $caller_line\n";

	my $database=shift; 
	$database = $conf{database} unless $database;

	my $dsn;
	my $dbh;

	my $mycnf		=($conf{dbmycnf} ? $conf{dbmycnf}: "$ENV{HOME}/.my.cnf" );
	my $mysql_group	=($conf{dbmysql_group} ? $conf{dbmysql_group}:  'mysql_igdb');

	if (-f $mycnf){
		$dsn="DBI:mysql:$database;mysql_read_default_file=$mycnf;mysql_read_default_group=$mysql_group;";
	
		$dbh = DBI->connect($dsn,undef,undef,{PrintError=>0});
		print "[bcelldb_init.pm][DEBUG] db connect through configuartion:$dsn\n" if ($conf{log_level} >= 4);
	}

	#	# THE FOLLOWING BLOCK IS DEPRECATED AND ONLY MAINTAINED FOR LECAGY APPLICATIONS. USE PROPER AUTHENTICATION!
	#	# In case there is no DB connection until this point, fall back to user/password authentication. 
	#	# 
	#	#
	#	if (! $dbh){
	#		my $host	=($conf{dbhost} ? $conf{dbhost}:  'localhost');
	#		my $user	=($conf{dbuser} ? $conf{dbuser}:  $ENV{USER});
	#		my $password=($conf{dbpass} ? $conf{dbpass}:  "");
	#		my $port	=($conf{dbport} ? $conf{dbport}:  3306);
	#
	#		$dsn="DBI:mysql:database=$database;host=$host;port=$port";
	#		$dbh = DBI->connect($dsn,$user,$password,{PrintError=>0}) ||
	#
	#		print "[bcelldb_init.pm][WARN] Using a deprecated method (username) for database authentication\n" if ($conf{log_level} >= 2);
	#		print "[bcelldb_init.pm][DEBUG] db connect through username from config:$dsn\n" if ($conf{log_level} >= 4);
	#	}

	if (! $dbh) {
		print "[bcelldb_init.pm][FATAL] Could not connect to database\n" if ($conf{log_level} >= 0);
		die;
	}

	$dbh->{RaiseError}=1;
	$dbh->{PrintError}=1;
	return $dbh;
}


INIT{ 
#	(my $caller_package, my $caller_filename, my $caller_line) = caller;
#	print "[bcelldb_init.pm][DEBUG+] caller INIT: package: $caller_package, filename: $caller_filename, line: $caller_line\n";
	start_log(); 
}


END{ 
#	(my $caller_package, my $caller_filename, my $caller_line) = caller;
#	print "[bcelldb_init.pm][DEBUG+] caller END: package: $caller_package, filename: $caller_filename, line: $caller_line\n";
	stop_log(); 
} 

1;


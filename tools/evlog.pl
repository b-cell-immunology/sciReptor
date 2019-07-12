#!/usr/bin/perl
use strict;
use warnings;

my %hash_stat;
my @array_cl;

foreach my $logline (<>) {
	chomp $logline;
	next if ( $logline =~ /^(STAT|INFO)\s+/ );
	if ( $logline =~ /^ARG\[([0-9]+)\]\s+(.*)/ ) {
		$array_cl[$1] = $2;
		next;
	}
	if ( $logline =~ /^0x[0-9a-f]+:[0-9]+\s+(.*)/ ) {
		$logline = $1;
	}
	if ( $logline =~ /^([A-Z]+)\s+([A-Z]+)\s+(.*)$/ ){
		(my $logtype, my $logkey, $logline ) = ($1, $2, $3);
		if ($logtype eq "STAT") {
			next if ($logkey =~ /(READS|ELAPSED|TIME)/); # Ignore keys that are dynamically updated and can appear multiple times per thread
			next if ($logkey =~ /(OVERLAPS)/); # Ignore keys that do not provide a simple number
			if ( $logline =~ /^[0-9]+$/ ) {
				$hash_stat{$logkey} += $logline;
			} else {
				print STDERR "Could not parse line $. (no integer):   type: $logtype   key: $logkey line: $logline\n";
			}
		}
	} else {
		print STDERR "Could not parse line $. (unknown error): $logline\n";
	}
}

my $bool_skip_next = 0;
my $bool_include_next = 0;
my $cnt_args = 0;
my @array_cl_filtered;
foreach my $tmp ( @array_cl ){
	$cnt_args++;
	if ($bool_skip_next) {
		$bool_skip_next = 0;
		next;
	}
	if ($bool_include_next) {
		push @array_cl_filtered, $tmp;
		$bool_include_next = 0;
		next;
	}
	next if ($cnt_args == 1);			# Skip command name
	if ( $tmp =~ /^-[6BFj]$/ ) {		# Switches to skip
		next;
	}
	if ( $tmp =~ /^-[dfgGrTuUwW]$/ ) {	# Parameters to skip
		$bool_skip_next = 1;
		next;
	}
	if ( $tmp =~ /^-[aN]$/ ) {			# Switches to include
		push @array_cl_filtered, $tmp;
		next;
	}
	if ( $tmp =~ /^-[ACDklLoOpqt]$/ ) {	# Parameters to include
		push @array_cl_filtered, $tmp;
		$bool_include_next = 1;
		next;
	}
	printf STDERR "Could not parse commandline argument %i: \"%s\".\n", $cnt_args, $tmp;
}

printf "(relevant commandline arguments: \"%s\")\n", join( " ", @array_cl_filtered );

my $tmptotal = 0;
my $tmpslow = 0;
foreach my $tmpkey (sort keys %hash_stat ) {
	# Handle non-additive keys separately
	if ( $tmpkey eq "SLOW" ) {
		$tmpslow = $hash_stat{$tmpkey};
	} else {
		printf "%-11s : %8i\n", $tmpkey, $hash_stat{$tmpkey};
		$tmptotal += $hash_stat{$tmpkey};
	}
}
printf "%-11s : %8i (%i marked as \"SLOW\")\n", "total", $tmptotal, $tmpslow;

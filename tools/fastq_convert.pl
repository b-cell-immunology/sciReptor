#!/usr/bin/perl
use warnings;
use strict;
use Bio::SeqIO;
use Parallel::ForkManager;
use Getopt::Long;
use Fcntl;

sub func_child_finish($$$$$){
	my $option_mode = shift;
	my $ptr_hash_proc_ctrl = shift;
	my $key_proc_curr = shift;
	my $fh_out_primary = shift;
	my $fh_out_secondary = shift;

	my $tmp_fh;

	printf "func_child_finish: Entering with option mode \"%s\"\n", $option_mode;
	printf "func_child_finish: Primary\n";
	if ($option_mode ne "qual") {
		$tmp_fh = $ptr_hash_proc_ctrl->{$key_proc_curr}{pipe_seq}{out};
	} else {
		$tmp_fh = $ptr_hash_proc_ctrl->{$key_proc_curr}{pipe_qual}{out};
	}
	while (<$tmp_fh>) {
		print $fh_out_primary $_;
	}

	printf "func_child_finish: Secondary\n";
	if ($option_mode eq "dual") {
		$tmp_fh = $ptr_hash_proc_ctrl->{$key_proc_curr}{pipe_qual}{out};
		while (<$tmp_fh>) {
			print $fh_out_secondary $_;
		}
	}

	printf "func_child_finish: Clean-up\n";
	foreach my $tmp_key ( qw / pipe_seq pipe_qual pipe_status / ) {
		close $ptr_hash_proc_ctrl->{$key_proc_curr}{$tmp_key}{out};
	}
	delete $ptr_hash_proc_ctrl->{$key_proc_curr};
	printf "func_child_finish: Exiting\n";
}

my $static_process_cap = 64; # WARNING: Too many processes will crash your system. Only change this value if you know what you are doing!
my $static_block_entries = 10000;

my $option_process_max = 1;
my $option_infile = '';
my $option_mode = 'seq';
my $option_outfile_primary = '';
my $option_outfile_secondary = '';
my $option_show_help = '';

my $fh_infile;
my $fh_outfile_primary;
my $fh_outfile_secondary;

my %hash_proc_ctrl;
my $key_slice_curr;
#my @array_pipe_seq_out, my $pipe_seq_in, my $pipe_seq_out;
#my @array_pipe_qual_out, my $pipe_qual_in, my $pipe_qual_out;
#my @array_pipe_status_out, my $pipe_status_in, my $pipe_status_out;
my $count_slice = 0;
my $count_processes = 0;


GetOptions (
	'cores=i' => \$option_process_max,
	'mode=s' =>  \$option_mode,
	'in=s' => \$option_infile,
	'out=s' => \$option_outfile_primary,
	'out_sec=s' => \$option_outfile_secondary,
	'help' => \$option_show_help
);

if ($option_show_help) {
	print "Usage: fastq_convert.pl [--cores=n] [--mode=(seq|qual|dual)] [--in=<infile>] [--out=<outfile>] [--out_sec=<qual_outfile>]\n";
	print "  --mode: seq, only sequences (default); qual, only decimal quality scores; dual, both\n";
	print "  <infile> defaults to STDIN all modes\n";
	print "  <outfile> defaults to STDOUT for \"seq\" and \"qual\" mode\n";
	print "  <qual_outfile> is required for \"dual\" mode, which always requires two files, i.e. no default to STDOUT\n";
	exit 1;
}


if ( $option_process_max < 1 ) {
	print "Warning: Ignoring \"--cores\" value below 1.\n";
	$option_process_max = 1;
} elsif ( $option_process_max > $static_process_cap ) {
	print "Warning: Capping \"--cores\" value to the current limit of ${static_process_cap}.\n";
	$option_process_max = $static_process_cap;
}
my $pm=new Parallel::ForkManager($option_process_max);


if ($option_infile) {
	open $fh_infile, "<", $option_infile;
} else {
	$fh_infile = \*STDIN;
}


$option_mode = lc $option_mode;
if (($option_mode eq "seq") || ($option_mode eq "qual")) {
	if ($option_outfile_primary) {
		open $fh_outfile_primary, ">", $option_outfile_primary;
	} else {
		$fh_outfile_primary = \*STDOUT;
	}
} elsif ($option_mode eq "dual" ) {
	if (($option_outfile_primary) && ($option_outfile_secondary)) {
		open $fh_outfile_primary, ">", $option_outfile_primary;
		open $fh_outfile_secondary, ">", $option_outfile_secondary;
	} else {
		print "ERROR: \"--mode=dual\" requires two output files!\n";
	}
} else {
	print "ERROR: Invalid \"--mode\" option!\n";
	exit 1;
}


while (! eof $fh_infile){
	printf "PARENT   : Entering main\n";
	my @array_entries = ();
	my $count_entry = 0;

	# If there are entries from a previous iteration, do some cleanup
	if (defined $key_slice_curr){
		foreach my $tmp_key ( qw / pipe_seq pipe_qual pipe_status / ) {
			close $hash_proc_ctrl{$key_slice_curr}{$tmp_key}{in};
			$hash_proc_ctrl{$key_slice_curr}{$tmp_key}{in} = 0;
		}
	}
	printf "PARENT   : Finished re-entry clean-up\n";

	# Wait for processes to complete, as they require readout of the data
	while ($count_processes >= $option_process_max) {
		print "PARENT   : WAITING FOR NEW PROCESS SLOTS\n";
		my $key_proc_curr;
		my $status_curr;
		foreach (sort keys %hash_proc_ctrl) {
			$key_proc_curr = $_;
			my $tmp_pipe_status_out = $hash_proc_ctrl{$key_proc_curr}{pipe_status}{out};
			$status_curr = <$tmp_pipe_status_out>;
			$status_curr = "N/A" if ! $status_curr;
			printf "PARENT   : CHILD %s pipe %s status %s\n", $key_proc_curr, $tmp_pipe_status_out, $status_curr;
			last if ($status_curr eq "DONE");
		}
		printf "PARENT   : Status checked, last %s in child %s\n", $status_curr, $key_proc_curr;
		if ($status_curr eq "DONE") {
			&func_child_finish($option_mode, \%hash_proc_ctrl, $key_proc_curr, $fh_outfile_primary, $fh_outfile_secondary);
			$count_processes--;
		} else {
			sleep(1);
		}
	}

	# Read next slice
	$key_slice_curr = sprintf( "SLICE_%05i", $count_slice++);
	printf "PARENT   : Attempting to read from input file (slice %s, processes %3i),\n", $key_slice_curr, $count_processes;
	while ((! eof $fh_infile) && ($count_entry < $static_block_entries)) {
		my @array_entry_current;
		foreach (0..3) {
			$array_entry_current[$_] = <$fh_infile>;
		}
		push @array_entries, join('', @array_entry_current);
		$count_entry++;
	}
	printf "PARENT   : array_entries size: %i\n", scalar(@array_entries);
	my $entries_concat = join('', @array_entries);

	# create a new record for the to-be-forked process
	$hash_proc_ctrl{$key_slice_curr} = {
					pipe_seq	=> { },
					pipe_qual	=> { },
					pipe_status	=> { }
	};

	pipe($hash_proc_ctrl{$key_slice_curr}->{pipe_seq}->{out}, $hash_proc_ctrl{$key_slice_curr}->{pipe_seq}->{in});
	pipe($hash_proc_ctrl{$key_slice_curr}->{pipe_qual}->{out}, $hash_proc_ctrl{$key_slice_curr}->{pipe_qual}->{in});
	pipe($hash_proc_ctrl{$key_slice_curr}->{pipe_status}->{out}, $hash_proc_ctrl{$key_slice_curr}->{pipe_status}->{in});

	my $flags = 0;
	my $tmp_status_out = $hash_proc_ctrl{$key_slice_curr}{pipe_status}{out};
	fcntl($tmp_status_out, F_GETFL, $flags) or die "Couldn't get flags for HANDLE : $!\n";
	$flags |= O_NONBLOCK;
	fcntl($tmp_status_out, F_SETFL, $flags) or die "Couldn't set flags for HANDLE: $!\n";

	printf "PARENT   : Child %s will output status on pipe_status_out %s.\n", $key_slice_curr, $hash_proc_ctrl{$key_slice_curr}{pipe_status}{out};
	$count_processes++;
	$pm->start and next;

	# Start forked process
	printf "CHILD %s: Started\n", $key_slice_curr;
	foreach my $tmp_key ( qw / pipe_seq pipe_qual pipe_status / ) {
		close $hash_proc_ctrl{$key_slice_curr}{$tmp_key}{out};
		$hash_proc_ctrl{$key_slice_curr}{$tmp_key}{out} = 0;
	}

	my $obj_fastq = Bio::SeqIO->new(-string => $entries_concat, -format => 'fastq');
	my $tmp_string_seq = "";
	my $tmp_string_qual = "";

	while (my $seq_fastq = $obj_fastq->next_seq) {
		if ($option_mode eq "seq") {
			$tmp_string_seq  .= sprintf(">%s\n%s\n", $seq_fastq->id, $seq_fastq->seq);
		} elsif ($option_mode eq "qual") {
			$tmp_string_qual .= sprintf(">%s\n%s\n", $seq_fastq->id, $seq_fastq->qual_text());
		} elsif ($option_mode eq "dual") {
			$tmp_string_seq  .= sprintf(">%s\n%s\n", $seq_fastq->id, $seq_fastq->seq);
			$tmp_string_qual .= sprintf(">%s\n%s\n", $seq_fastq->id, $seq_fastq->qual_text());
		}
	}

	printf "CHILD %s: Processed\n", $key_slice_curr;

	print {$hash_proc_ctrl{$key_slice_curr}{pipe_status}{in}} "DONE";
	close $hash_proc_ctrl{$key_slice_curr}{pipe_status}{in};
	printf "CHILD %s: Sent status\n", $key_slice_curr;

	if ($option_mode eq "seq") {
		print {$hash_proc_ctrl{$key_slice_curr}{pipe_seq}{in}} $tmp_string_seq;
		printf "CHILD %s: Sent seq data\n", $key_slice_curr;
		close $hash_proc_ctrl{$key_slice_curr}{pipe_seq}{in};
	} elsif ($option_mode eq "qual") {
		print {$hash_proc_ctrl{$key_slice_curr}{pipe_qual}{in}} $tmp_string_qual;
		printf "CHILD %s: Sent qual data\n", $key_slice_curr;
		close $hash_proc_ctrl{$key_slice_curr}{pipe_qual}{in};
	} elsif ($option_mode eq "dual") {
		print {$hash_proc_ctrl{$key_slice_curr}{pipe_seq}{in}} $tmp_string_seq;
		printf "CHILD %s: Sent seq data\n", $key_slice_curr;
		close $hash_proc_ctrl{$key_slice_curr}{pipe_seq}{in};
		print {$hash_proc_ctrl{$key_slice_curr}{pipe_qual}{in}} $tmp_string_qual;
		printf "CHILD %s: Sent qual data\n", $key_slice_curr;
		close $hash_proc_ctrl{$key_slice_curr}{pipe_qual}{in};
	}

	printf "CHILD %s: Exiting\n", $key_slice_curr;
	$pm->finish;
	# End forked process
}

foreach my $tmp_key ( qw / pipe_seq pipe_qual pipe_status / ) {
	close $hash_proc_ctrl{$key_slice_curr}{$tmp_key}{in};
	$hash_proc_ctrl{$key_slice_curr}{$tmp_key}{in} = 0;
}
close $fh_infile if ($option_infile);

print "PARENT   : No more input data\n";
while ($count_processes > 0) {
	print "PARENT   : WAITING FOR PROCESSES TO COMPLETE\n";
	my $key_proc_curr;
	my $status_curr;
	foreach (sort keys %hash_proc_ctrl) {
		$key_proc_curr = $_;
		my $tmp_pipe_status_out = $hash_proc_ctrl{$key_proc_curr}{pipe_status}{out};
		$status_curr = <$tmp_pipe_status_out>;
		$status_curr = "N/A" if ! $status_curr;
		printf "PARENT   : CHILD %s pipe %s status %s\n", $key_proc_curr, $tmp_pipe_status_out, $status_curr;
		last if ($status_curr eq "DONE");
	}
	printf "PARENT   : Status checked, last %s in child %s\n", $status_curr, $key_proc_curr;
	if ($status_curr eq "DONE") {
		&func_child_finish($option_mode, \%hash_proc_ctrl, $key_proc_curr, $fh_outfile_primary, $fh_outfile_secondary);
		$count_processes--;
	} else {
		sleep(1);
	}
}

close $fh_outfile_primary if ($option_outfile_primary);
close $fh_outfile_secondary if ($option_mode eq "dual");
print "PARENT   : Waiting for child processes to end...\n";
$pm->wait_all_children;


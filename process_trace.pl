#!/usr/bin/perl

use warnings;
use strict;

sub linear_search($$);
sub get_nmdata($);

my $dumpfile = "trace.dump";
my $mapsfile = "trace.maps";
my $outfile = "trace.report";

my @maps;

if ( (! -f $dumpfile) or (! -f $mapsfile) ) {
	print STDERR "trace.dump and trace.maps not found\n";
	die "Run gettrace.sh first!\n";
}

open (my $fh, $mapsfile) || die "OPEN: $!\n";
print "Processing input\n";
printf "  %-50s  ", $mapsfile;

while (my $line = <$fh>) {

	chomp($line);

	unless ($line =~ /r-xp/) {
		next;
	}

	my @tokens = split(/\s+/, $line);

	my ($lowaddr, $highaddr) = split(/-/, $tokens[0]);

	my $lib = $tokens[$#tokens];

	push @maps, [ $lowaddr, $highaddr, $lib, 0, {}, [] ];
}

print "done\n";

close($fh) || die "CLOSE: $!";

open ($fh, "sort $dumpfile | uniq -c |") || die "OPEN: $!";
printf "  %-50s  ", $dumpfile;

while (my $line = <$fh>) {

	chomp($line);


	($line =~ /^\s*([^\s]+)\s+([^\s]+)$/) or die;
	my $count = $1;
	my $vaddr = $2;

	foreach my $map (@maps)
	{
		if ((hex $vaddr >= hex $$map[0]) && (hex $vaddr < hex $$map[1])) {

			$$map[3] += $count;


			my $addr;

			if ($vaddr =~ /^8/) # FIXME Hackish
			{
				$addr = $vaddr;
			} else {

				$addr = hex($vaddr) - hex($$map[0]);
				$addr = sprintf("%x", $addr);
			}

			push @{$$map[5]}, [ $addr, $count ];

			last;
		}
	}
}

print "done\n";

close($fh) || die "CLOSE: $!";

print "\nResolving symbols\n";
foreach my $map (@maps)
{
	printf "  %-50s  ", $$map[2];

	my $nmdata_lrefs = get_nmdata($$map[2]);

	my $func_href = $$map[4];

	foreach my $addr_count_list (@{$$map[5]})
	{
		my $addr = $$addr_count_list[0];
		my $count = $$addr_count_list[1];
		my $func = "<unresolved_symbol>";

		# Search the lists in the nmdata structure

		foreach my $listref (@{$nmdata_lrefs})
		{
			my @addr_list = @{$$listref[0]};
			my @func_list = @{$$listref[1]};

			my $result_index = linear_search(\@addr_list, $addr);

			next if (! defined $result_index);

			my $result_addr = $addr_list[$result_index];
			die if (hex($result_addr) > hex($addr));

			$func = $func_list[$result_index];

			last;
		}

		if (defined($$func_href{$func})) {
			$$func_href{$func} += $count;
		} else {
			$$func_href{$func} = $count;
		}

	}

	print "done\n";
}

# Print report

open ($fh, ">", $outfile) || die "OPEN: $!\n";

print $fh "All Libraries\n\n";

my $instr_total = 0;

my @maps_sorted_by_instr = sort { $$b[3] <=> $$a[3] } @maps;

foreach my $map (@maps_sorted_by_instr)
{
	my $instrs = $$map[3];

	next if ($instrs == 0);
	printf $fh ("%10d %s\n", $instrs, $$map[2]);
	$instr_total += $instrs;
}

printf $fh ("\n%10d %s\n", $instr_total, "TOTAL");

foreach my $map (@maps_sorted_by_instr)
{
	my $instrs = $$map[3];

	next if ($instrs == 0);

	printf $fh ("\n$$map[2]\n\n");

	my $func_href = $$map[4];

	foreach my $func (sort { $$func_href{$b} <=> $$func_href{$a} } keys %{$func_href})
	{
		printf $fh ("%10s %s\n", $$func_href{$func}, $func);
	}
}

close ($fh);

print "\nReport written to $outfile\n";

exit 0;


# Read from stdout of nm command and populate the nm data structure
sub get_nmdata($)
{
	my $binary = $_[0];

	my @nm_cmds = (
		"nm -nD --defined-only $binary 2>/dev/null",
		"nm -n --defined-only $binary 2>/dev/null"
	);

	my @nm_data;

	foreach my $nm_cmd (@nm_cmds)
	{
		my @addr_list;
		my @func_list;

		open (NM_OUT, "$nm_cmd |") or die "Unable to execute nm: $!\n";

		while (defined(my $line = <NM_OUT>))
		{
			chomp($line);
		
			my ($addr, $type, $name) = split(/\s+/, $line);

			push @addr_list, $addr;
			push @func_list, $name;
		}

		close NM_OUT;

		push @nm_data, [\@addr_list, \@func_list];
	}

	return \@nm_data;
}



sub linear_search($$)
{
	my ($sorted_list_ref, $key) = @_;

	my $index = 0;
	my $prev_index = 0;

	while ($index < scalar @{$sorted_list_ref})
	{
		my $addr = $$sorted_list_ref[$index];

		if (hex($addr) == hex($key)) {
			return $index;
		}

		if (hex($addr) > hex($key)) {
			return ($index - 1) if ($index > 0);
			return undef;
		}

		$index++;
	}

	return undef
}


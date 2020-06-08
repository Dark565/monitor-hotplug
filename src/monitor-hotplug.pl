#!/usr/bin/perl

# Copyright (C) 2020 Grzegorz Kociołek
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Register changes in monitor connections

use strict;
use warnings;
use v5.14;

use File::Which;
use Cwd 'abs_path';
use Time::HiRes qw(usleep);
#use Data::Dumper;

sub not_installed($) {
	die shift . " is not installed in your system. Aborted";
}
which("udevadm") 	or not_installed "udevadm";
which("lspci") 		or not_installed "lspci";
which("parse-edid")	or not_installed "parse-edid"; 

my $sysdir = "/sys/class/drm";

sub get_return_val {
	return ($? >> 8);
}

sub get_monitor_name($) {
	my $monitor = shift;

	my $edid_file;
	open ($edid_file, "parse-edid 2>&- <$monitor/edid |") or return undef;

	wait;
	return undef if (get_return_val() == 1);

	my $model_name = ( grep(/ModelName/, <$edid_file>) )[0] =~ s/^.* "(.+)"\n$/$1/r;
	close $edid_file;
	return $model_name;
}

sub get_monitor_status($) {
	my $monitor = shift;

	my $status_file;
	unless (open $status_file, "<", "$monitor/status") {
		warn "Cannot read the status of '$monitor'. Defaulting to 0.";
		return 0;
	}

	my $status = <$status_file> eq "connected\n" ? 1 : 0;
	close $status_file;
	return $status;
}


sub get_card_name($) {
	my $card = shift;

	my $linkto = readlink $card;
	my $pci_address = ( reverse(split(/\//, $linkto)) )[2];

	my $lspci_file;
	unless (open $lspci_file, "lspci -s '$pci_address' 2>&- |") {
	ERROR:
		warn "Cannot get the name of '$card'";
		return undef;
	}

	wait;
	goto ERROR if (get_return_val);

	my $model_name = <$lspci_file> =~ s/^.*?: (.+) \(.*\)\n$/$1/r;
	close $lspci_file;
	return $model_name;

}



# Detect monitors of a specific card and return a hash with info
sub detect_monitors($) {
	my $card = shift;
	my @monitors = glob("$card/$card-*");
	my @monitors_array;

	if (@monitors == 0) {
		warn "No monitors found for $card";
		return undef;
	}

	for my $mon ( @monitors ) {
		my $base_mon = $mon =~ s/^.*\/(.*)$/$1/r;

		my %mon_hash;
		my $mon_status = get_monitor_status($mon);


		$mon_hash{'status'} = $mon_status;
		$mon_hash{'path'} = $base_mon;
		$mon_hash{'name'} = (get_monitor_name($mon) or '') if ( $mon_status == 1);

		push @monitors_array, \%mon_hash;
	}

	return \@monitors_array;

}

sub parse_udevadm_line($) {
	my $line = shift;
	if ($line =~ /^\S+ change/) {
		$line =~ /\/(\w+) \(drm\)\n$/;
		return $1;
	}
	return undef;
}

sub exec_cmd {
	my $exec = shift;
	say "Exec: $exec";
	(-x $exec && -r $exec) or die "Action program is not executable. Aborted";

	if (fork() == 0) {
		exec $exec, @_;
	}
}

# Command which will be run on monitor hotplug
my $hotplug_cmd;

# Global hash of card data
my %card_data;

sub detect_monitor_change($) {
	my $card = shift;
	my $card_hash = $card_data{$card};

	my $card_name = $card_hash->{'name'};
	my $mon_array = $card_hash->{'monitors'};

	for my $mon_hash ( @$mon_array ) {

		my $mon_path = $mon_hash->{'path'};
		my $mon_old_status = $mon_hash->{'status'};

		my $mon_new_status = get_monitor_status($mon_path);
		#say "Monitor $mon_path";
		#say "Old status: $mon_old_status";
		#say "New status: $mon_new_status";	

		if ($mon_new_status != $mon_old_status) {
			my $mon_name;
			if ($mon_new_status == 1) {
				$mon_name = ( get_monitor_name($mon_path) or '' );
				$mon_hash->{'name'} = $mon_name;
			}
			else {
				$mon_name = $mon_hash->{'name'};
			}

			$mon_hash->{'status'} = $mon_new_status;
			exec_cmd($hotplug_cmd, $card, $card_name, $mon_path, $mon_name, $mon_new_status);
			return;
		}

	}


}

my $script_dir = $0 =~ /^(.*)\/.*$/ ? $1 : ".";
$script_dir = abs_path($script_dir);

sub usage {
	say STDERR "$0 [-h][--help] [action-program]";
	say STDERR "Arguments for the action program are aligned as in example: 'program card0 \"graphics_card\" DVI-D-1 \"monitor\" 1'.";
	say STDERR "card, card_name, monitor, monitor_name, status (plugged/unplugged - 1/0).";
}

sub parse_args {
	if (@ARGV > 0) {
		for ($ARGV[0]) {
			if (/^-(h|-help)$/) { 
				usage();
				exit 0;
			}
			default {	
				$hotplug_cmd = abs_path($_);
			}
		}
	}
	else {	
		$hotplug_cmd = "$script_dir/hotplug-action";
	}

	(-x $hotplug_cmd && -r $hotplug_cmd) or die "Action program '$hotplug_cmd' is not executable. Aborted"; 
	say STDERR "Hotplug action program is '$hotplug_cmd'";
}

# Main subroutine
sub main {
	parse_args();

	( -r $sysdir && -x $sysdir ) or die "'$sysdir' is not readable";

	chdir $sysdir;

	for my $card ( grep(/^card\d+$/, glob("*")) ) {
		my %card_hash;

		my $full_card = "$sysdir/$card";
		$card_hash{'name'} = get_card_name($full_card);
		$card_hash{'monitors'} = detect_monitors($card);

		$card_data{$card} = \%card_hash;
	}

	#say STDERR Dumper(\%card_data);

	say STDERR "Cards and monitors detected.";
	say STDERR "Polling for changes.."; 

	my $udevadm_file;
	open $udevadm_file, "udevadm monitor -k -s drm 2>/dev/null |" or die "Cannot execute udevadm. Aborted";
	<$udevadm_file> for (1..3);

	while (my $udevadm_line = <$udevadm_file>) {
		my $chg_card = parse_udevadm_line($udevadm_line);
		say STDERR "Detected change for $chg_card";

		usleep 500000; # Sync interval; kernel informs faster about changes in monitor connections than it seriously prepares that information to read, so we have to wait
		detect_monitor_change($chg_card);
		#say STDERR Dumper(\%card_data);
	}

}

main();

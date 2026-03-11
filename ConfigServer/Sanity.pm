###############################################################################
# Copyright (C) 2006-2025 Jonathan Michaelson
#
# https://github.com/waytotheweb/scripts
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, see <https://www.gnu.org/licenses>.
###############################################################################
## no critic (RequireUseWarnings, ProhibitExplicitReturnUndef, ProhibitMixedBooleanOperators, RequireBriefOpen)
package ConfigServer::Sanity;

use strict;
use lib '/usr/local/csf/lib';
use Fcntl qw(:DEFAULT :flock);
use Carp;
use ConfigServer::Config;

use Exporter qw(import);
our $VERSION   = 1.02;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(sanity);

# Cached validation metadata loaded from sanity.txt.
#
# Each file entry is expected to be in the form:
#   NAME=ALLOWED=DEFAULT
#
# Examples:
#   AT_INTERVAL=10-3600=60
#   DROP=DROP|TARPIT|REJECT=DROP
#   CT_LIMIT=0|10-1000=0
#
# %sanity stores the allowed-value expression for each setting and
# %sanitydefault stores the recommended default value.
our %sanity;
our %sanitydefault;
our $loaded     = 0;
our $sanityfile = "/usr/local/csf/lib/sanity.txt";

sub sanity {
	my $sanity_item  = shift;
	my $sanity_value = shift;
	my $insane       = 0;

	# Preserve historical behaviour for undefined input and avoid loading the
	# validation table when there is no value to validate.
	return 0 unless defined $sanity_value;

	# Load the validation table on first use and keep it cached for the rest of
	# the process lifetime. This keeps module load cheap and makes the runtime
	# behaviour deterministic after the first lookup.
	if (!$loaded) {
		open my $IN, '<', $sanityfile or croak "Cannot open $sanityfile: $!";
		flock $IN, LOCK_SH;
		chomp(my @data = <$IN>);
		close $IN;

		%sanity        = ();
		%sanitydefault = ();

		foreach my $line (@data) {
			my ($name, $value, $def) = split(/\=/, $line, 3);
			$sanity{$name}        = $value;
			$sanitydefault{$name} = $def;
		}

		my $config_obj = ConfigServer::Config->loadconfig();
		my %config_values = $config_obj->config();

		# When IPSET is enabled, DENY_IP_LIMIT no longer applies, so remove its
		# rule from the cached table before any validations are performed.
		if ($config_values{IPSET}) {
			delete $sanity{DENY_IP_LIMIT};
			delete $sanitydefault{DENY_IP_LIMIT};
		}

		$loaded = 1;
	}

	$sanity_item = '' unless defined $sanity_item;
	$sanity_item =~ s/\s//g;
	$sanity_value =~ s/\s//g;

	# Rules support both numeric ranges (10-3600) and exact tokens
	# (DROP|TARPIT|REJECT). A setting is marked insane until one branch matches.
	if (defined $sanity{$sanity_item}) {
		$insane = 1;
		foreach my $check (split(/\|/, $sanity{$sanity_item})) {
			if ($check =~ /-/) {
				my ($from, $to) = split(/\-/, $check);
				if (($sanity_value >= $from) and ($sanity_value <= $to)) { $insane = 0 }
			}
			else {
				if ($sanity_value eq $check) { $insane = 0 }
			}
		}
	}

	# Keep cached rule text untouched and only format a display copy for callers.
	my $acceptable_display = defined $sanity{$sanity_item} ? $sanity{$sanity_item} : undef;
	$acceptable_display =~ s/\|/ or /g if defined $acceptable_display;

	# Return value tuple:
	#   0/1  => sane or insane
	#   text => acceptable values for display
	#   text => recommended default value
	return ($insane, $acceptable_display, $sanitydefault{$sanity_item});
}

1;

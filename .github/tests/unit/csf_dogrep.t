#!/usr/bin/env perl

BEGIN {
    *CORE::GLOBAL::exit = sub { die "unexpected exit(@_)" };
}

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->catdir( $Bin, '..', 'lib' );

use Test::More;
use TestCSFScript qw(load_csf_pl);

load_csf_pl();

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

{
    no warnings 'once';
    no warnings 'redefine';

    local %sbin::csf::config = (
        IPTABLES     => '/sbin/iptables',
        IPTABLESWAIT => '',
        NAT          => 0,
        MANGLE       => 0,
        RAW          => 0,
        IPV6         => 0,
        LF_IPSET     => 0,
    );
    local $sbin::csf::verbose = 0;
    local $sbin::csf::cleanreg = qr/[\r\n]+/;

    local *sbin::csf::run_open3 = sub {
        my $output = "Chain INPUT (policy ACCEPT)\n";
        open my $fh, '<', \$output or die $!;
        $_[0] = undef;
        $_[1] = $fh;
        $_[2] = $fh;
        return -1;
    };

    local *sbin::csf::slurpee = sub {
        my ($path) = @_;
        return ( '', '0|1.2.3.4|80|in|600|note' ) if $path =~ /csf\.tempallow$/;
        return ( '', '0|1.2.3.4|80|in|600|note' ) if $path =~ /csf\.tempban$/;
        return ('') if $path =~ /csf\.(allow|deny)$/;
        return;
    };

    local *sbin::csf::slurp = sub {
        my ($path) = @_;
        return ('') if $path =~ /csf\.(allow|deny)$/;
        return;
    };

    local *sbin::csf::checkip = sub { return };

    my $ok = eval { sbin::csf::dogrep('1.2.3.4'); 1 };
    ok( $ok, 'dogrep handles blank temp allow/deny lines without dying' ) or diag $@;
}

is_deeply( \@warnings, [], 'dogrep emits no warnings for blank temp allow/deny lines' );

done_testing;

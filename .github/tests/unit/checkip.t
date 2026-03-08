#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();
use ConfigServer::CheckIP qw(checkip cccheckip);

subtest 'checkip accepts supported addresses' => sub {
    is( checkip('8.8.8.8'), 4, 'accepts a valid IPv4 address' );
    is( checkip('8.8.8.8/24'), 4, 'accepts a valid IPv4 CIDR' );
    is( checkip('8.8.8.8/32'), 4, 'accepts the IPv4 upper CIDR boundary' );
    is( checkip('2001:4860:4860::8888'), 6, 'accepts a valid IPv6 address' );
    is( checkip('2001:4860:4860::8888/64'), 6, 'accepts a valid IPv6 CIDR' );
    is( checkip('2001:4860:4860::8888/128'), 6, 'accepts the IPv6 upper CIDR boundary' );
};

subtest 'checkip rejects malformed or blocked inputs' => sub {
    is( checkip('not-an-ip'), 0, 'rejects a non-IP string' );
    is( checkip('8.8.8.8/not-a-mask'), 0, 'rejects a non-numeric IPv4 mask' );
    is( checkip('8.8.8.8/33'), 0, 'rejects an IPv4 mask above 32' );
    is( checkip('8.8.8.8/999'), 0, 'rejects a clearly invalid IPv4 mask' );
    is( checkip('127.0.0.1'), 0, 'rejects IPv4 loopback' );
    is( checkip('::1'), 0, 'rejects IPv6 loopback' );
    is( checkip('2001:4860:4860::8888/129'), 0, 'rejects an IPv6 mask above 128' );
};

subtest 'checkip handles empty input safely' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    is( checkip(''), 0, 'rejects an empty string' );
    is( checkip(undef), 0, 'rejects undef input' );
    is( scalar @warnings, 0, 'does not warn for empty or undef input' );
};

subtest 'checkip normalises IPv6 references in place' => sub {
    my $ipv6 = '2001:4860:0000:0000:0000:0000:0000:8888';

    is( checkip(\$ipv6), 6, 'reference input is accepted as IPv6' );
    is( $ipv6, '2001:4860::8888', 'reference input is shortened in place' );
};

subtest 'cccheckip keeps the stricter public IPv4 behaviour' => sub {
    is( cccheckip('8.8.8.8'), 4, 'accepts a public IPv4 address' );
    is( cccheckip('10.0.0.1'), 0, 'rejects a private IPv4 address' );
    is( cccheckip('127.0.0.1'), 0, 'rejects IPv4 loopback' );
};

subtest 'cccheckip accepts IPv6 scalars and references' => sub {
    my $ipv6 = '2001:4860:0000:0000:0000:0000:0000:8844';

    is( cccheckip('2001:4860:4860::8844'), 6, 'accepts plain IPv6 scalar input' );
    is( cccheckip(\$ipv6), 6, 'accepts IPv6 reference input' );
    is( $ipv6, '2001:4860::8844', 'normalises IPv6 reference input in place' );
};

done_testing;

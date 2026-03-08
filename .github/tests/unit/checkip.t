#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();
use ConfigServer::CheckIP qw(checkip cccheckip);

sub assert_cases {
    my ( $fn, $cases ) = @_;

    for my $case ( @{$cases} ) {
        my ( $input, $expected, $label ) = @{$case};
        is( $fn->($input), $expected, $label );
    }

    return;
}

subtest 'checkip accepts canonical, boundary, and alternate address forms' => sub {
    assert_cases(
        \&checkip,
        [
            [ '192.168.1.1',                             4, 'accepts a private IPv4 address' ],
            [ '8.8.8.8',                                 4, 'accepts a public IPv4 address' ],
            [ '8.8.8.8/24',                              4, 'accepts an IPv4 CIDR block' ],
            [ '8.8.8.8/32',                              4, 'accepts the IPv4 upper CIDR boundary' ],
            [ '0.0.0.0',                                 4, 'accepts the IPv4 all-zero address' ],
            [ '255.255.255.255',                         4, 'accepts the IPv4 all-ones address' ],
            [ '2001:4860:4860::8888',                    6, 'accepts a compressed IPv6 address' ],
            [ '2001:4860:4860::8888/64',                 6, 'accepts an IPv6 CIDR block' ],
            [ '2001:4860:4860::8888/128',                6, 'accepts the IPv6 upper CIDR boundary' ],
            [ '2001:0db8:0000:0000:0000:ff00:0042:8329', 6, 'accepts a fully expanded IPv6 address' ],
            [ 'fe80::1',                                 6, 'accepts a link-local IPv6 address' ],
            [ '::ffff:192.0.2.1',                        6, 'accepts an IPv4-mapped IPv6 address' ],
        ]
    );
};

subtest 'checkip rejects malformed, polluted, or out-of-range input' => sub {
    assert_cases(
        \&checkip,
        [
            [ '',                            0, 'rejects an empty string' ],
            [ 'not-an-ip',                   0, 'rejects a non-IP string' ],
            [ '999.999.999.999',             0, 'rejects an out-of-range IPv4 address' ],
            [ '192.168.1',                   0, 'rejects an IPv4 address with too few octets' ],
            [ '192.168.1.1.1',               0, 'rejects an IPv4 address with too many octets' ],
            [ '8.8.8.8/not-a-mask',          0, 'rejects a non-numeric IPv4 mask' ],
            [ '8.8.8.8/33',                  0, 'rejects an IPv4 mask above 32' ],
            [ '8.8.8.8/999',                 0, 'rejects a clearly invalid IPv4 mask' ],
            [ '2001:4860:4860::8888/129',    0, 'rejects an IPv6 mask above 128' ],
            [ ' 8.8.8.8',                    0, 'rejects a leading-space IPv4 string' ],
            [ '8.8.8.8 ',                    0, 'rejects a trailing-space IPv4 string' ],
            [ '8.8.8.8; echo hacked',        0, 'rejects IPv4 input polluted with shell text' ],
            [ '8.8.8.8|cat',                 0, 'rejects IPv4 input polluted with pipe characters' ],
        ]
    );
};

subtest 'checkip rejects loopback addresses in both families' => sub {
    assert_cases(
        \&checkip,
        [
            [ '127.0.0.1',                                 0, 'rejects IPv4 loopback' ],
            [ '127.0.0.1/8',                               0, 'rejects IPv4 loopback with CIDR' ],
            [ '::1',                                       0, 'rejects compressed IPv6 loopback' ],
            [ '0000:0000:0000:0000:0000:0000:0000:0001',   0, 'rejects expanded IPv6 loopback' ],
        ]
    );
};

subtest 'checkip handles undefined and empty scalar inputs without warnings' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    my $undef_scalar;
    my $empty_scalar = q{};

    is( checkip(undef),          0, 'rejects undef scalar input' );
    is( checkip(\$undef_scalar), 0, 'rejects undef scalar reference input' );
    is( checkip(\$empty_scalar), 0, 'rejects empty scalar reference input' );
    is( scalar @warnings,        0, 'does not emit warnings for undefined or empty input' );
};

subtest 'IPv6 reference inputs are normalised in place and preserve CIDR suffixes' => sub {
    my $ipv6      = '2001:4860:0000:0000:0000:0000:0000:8888';
    my $ipv6_cidr = '2001:4860:0000:0000:0000:0000:0000:8844/64';

    is( checkip(\$ipv6), 6, 'plain IPv6 reference input is accepted' );
    is( $ipv6, '2001:4860::8888', 'plain IPv6 reference input is shortened in place' );

    is( checkip(\$ipv6_cidr), 6, 'IPv6 reference input with CIDR is accepted' );
    is( $ipv6_cidr, '2001:4860::8844/64', 'IPv6 reference input keeps its CIDR suffix after normalisation' );
};

subtest 'cccheckip keeps the stricter public/private IPv4 split' => sub {
    assert_cases(
        \&cccheckip,
        [
            [ '8.8.8.8',          4, 'accepts a public IPv4 address' ],
            [ '1.1.1.1',          4, 'accepts another public IPv4 address' ],
            [ '8.8.8.0/24',       4, 'accepts a public IPv4 CIDR block' ],
            [ '192.168.1.1',      0, 'rejects a 192.168.x.x private IPv4 address' ],
            [ '10.0.0.1',         0, 'rejects a 10.x.x.x private IPv4 address' ],
            [ '172.16.0.1',       0, 'rejects a 172.16.x.x private IPv4 address' ],
            [ '127.0.0.1',        0, 'rejects IPv4 loopback' ],
            [ '0.0.0.0',          0, 'rejects a non-public all-zero IPv4 address' ],
            [ '8.8.8.8/33',       0, 'rejects an out-of-range public IPv4 mask' ],
            [ 'not-an-ip',        0, 'rejects malformed scalar input' ],
            [ '',                 0, 'rejects an empty string' ],
        ]
    );
};

subtest 'cccheckip accepts IPv6 scalars and references while still rejecting loopback' => sub {
    my $ipv6      = '2001:4860:0000:0000:0000:0000:0000:8844';
    my $ipv6_cidr = '2001:4860:0000:0000:0000:0000:0000:8844/64';

    assert_cases(
        \&cccheckip,
        [
            [ '2001:4860:4860::8844',      6, 'accepts a plain IPv6 scalar' ],
            [ '2001:4860:4860::8844/128',  6, 'accepts an IPv6 scalar with upper CIDR boundary' ],
            [ 'fe80::1',                   6, 'accepts a link-local IPv6 scalar' ],
            [ '::1',                       0, 'rejects compressed IPv6 loopback' ],
            [ '::1/128',                   0, 'rejects IPv6 loopback with CIDR' ],
            [ '2001:4860:4860::8844/129',  0, 'rejects an out-of-range IPv6 mask' ],
        ]
    );

    is( cccheckip(\$ipv6), 6, 'accepts an IPv6 reference input' );
    is( $ipv6, '2001:4860::8844', 'normalises IPv6 reference input in place' );

    is( cccheckip(\$ipv6_cidr), 6, 'accepts an IPv6 reference input with CIDR' );
    is( $ipv6_cidr, '2001:4860::8844/64', 'preserves CIDR on cccheckip IPv6 reference input' );
};

subtest 'legacy CIDR /0 behaviour is documented as a known quirk' => sub {
    local $TODO = 'Legacy truthiness logic currently allows /0 CIDR masks';

    is( checkip('8.8.8.8/0'), 0, 'checkip should reject IPv4 /0 once the legacy quirk is fixed' );
    is( checkip('2001:4860:4860::8888/0'), 0, 'checkip should reject IPv6 /0 once the legacy quirk is fixed' );
    is( cccheckip('8.8.8.8/0'), 0, 'cccheckip should reject IPv4 /0 once the legacy quirk is fixed' );
    is( cccheckip('2001:4860:4860::8888/0'), 0, 'cccheckip should reject IPv6 /0 once the legacy quirk is fixed' );
};

done_testing;

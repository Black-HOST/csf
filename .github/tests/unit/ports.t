#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();
use ConfigServer::Ports ();

{
    package Local::PortsConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

sub with_mock_config {
    my ($config, $code) = @_;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::PortsConfig->new($config);
    };

    return $code->();
}

subtest 'openports expands configured port lists across all protocol families' => sub {
    my %ports = with_mock_config(
        {
            TCP_IN  => '22,80,3000:3002',
            TCP6_IN => '443,8443:8444',
            UDP_IN  => '53,6000:6001',
            UDP6_IN => '123,51820:51821',
        },
        sub { return ConfigServer::Ports::openports(); },
    );

    is_deeply(
        [ sort { $a <=> $b } keys %{ $ports{tcp} } ],
        [ 22, 80, 3000, 3001, 3002 ],
        'TCP ranges are expanded inclusively alongside single ports',
    );

    is_deeply(
        [ sort { $a <=> $b } keys %{ $ports{tcp6} } ],
        [ 443, 8443, 8444 ],
        'TCP6 entries include the upper bound of each range',
    );

    is_deeply(
        [ sort { $a <=> $b } keys %{ $ports{udp} } ],
        [ 53, 6000, 6001 ],
        'UDP ranges are expanded inclusively',
    );

    is_deeply(
        [ sort { $a <=> $b } keys %{ $ports{udp6} } ],
        [ 123, 51820, 51821 ],
        'UDP6 ranges are expanded inclusively',
    );
};

subtest 'openports strips whitespace, skips empty entries, and de-duplicates overlaps' => sub {
    my %ports = with_mock_config(
        {
            TCP_IN  => ' 22 , , 80 , 80 , 1000:1002 , 1002 ',
            TCP6_IN => ' , 443 , , ',
            UDP_IN  => ' 53 , , ',
            UDP6_IN => '',
        },
        sub { return ConfigServer::Ports::openports(); },
    );

    is_deeply(
        [ sort { $a <=> $b } grep { length } keys %{ $ports{tcp} } ],
        [ 22, 80, 1000, 1001, 1002 ],
        'whitespace and duplicate entries collapse into a clean TCP set',
    );

    ok(!exists $ports{tcp}{''}, 'TCP config does not create an empty pseudo-port');
    ok(!exists $ports{tcp6}{''}, 'TCP6 config does not create an empty pseudo-port');
    ok(!exists $ports{udp}{''}, 'UDP config does not create an empty pseudo-port');
    ok(!exists $ports{udp6}{''}, 'UDP6 config does not create an empty pseudo-port');

    is_deeply(
        [ sort { $a <=> $b } keys %{ $ports{tcp6} } ],
        [ 443 ],
        'TCP6 whitespace-only noise is ignored',
    );

    is_deeply(
        [ sort { $a <=> $b } keys %{ $ports{udp} } ],
        [ 53 ],
        'UDP whitespace-only noise is ignored',
    );

    is(scalar keys %{ $ports{udp6} }, 0, 'empty UDP6 config yields no entries');
};

subtest 'hex2ip decodes proc-style IPv4 and IPv6 addresses' => sub {
    is(
        ConfigServer::Ports::hex2ip('0100007F'),
        '127.0.0.1',
        'decodes little-endian IPv4 hex from procfs format',
    );

    is(
        ConfigServer::Ports::hex2ip('00000000000000000000000001000000'),
        '0:0:0:0:0:0:0:1',
        'decodes proc-style IPv6 loopback',
    );

    is(
        ConfigServer::Ports::hex2ip('B80D01200000000067452301EFCDAB89'),
        '2001:db8:0:0:123:4567:89ab:cdef',
        'decodes a representative IPv6 address from procfs layout',
    );
};

done_testing;

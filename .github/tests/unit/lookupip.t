#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

{
    package Local::LookUpIPConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

{
    package Local::LookUpIPURLGet;

    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }

    sub urlget {
        my ($self, $url) = @_;
        $self->{seen_urls} ||= [];
        push @{ $self->{seen_urls} }, $url;
        return @{ $self->{response} };
    }

    sub seen_urls {
        my ($self) = @_;
        return @{ $self->{seen_urls} || [] };
    }
}

sub reload_lookupip_module {
    my ($config, %opts) = @_;

    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::LookUpIPConfig->new($config);
    };

    delete $INC{'ConfigServer/URLGet.pm'};
    require ConfigServer::URLGet;

    if (exists $opts{urlget_client}) {
        local *ConfigServer::URLGet::new = sub {
            return $opts{urlget_client};
        };

        delete $INC{'ConfigServer/LookUpIP.pm'};
        require ConfigServer::LookUpIP;
        return 1;
    }

    delete $INC{'ConfigServer/LookUpIP.pm'};
    require ConfigServer::LookUpIP;
    return 1;
}

subtest 'iplookup returns the raw IP when host and country lookups are disabled' => sub {
    reload_lookupip_module({
        LF_LOOKUPS  => 0,
        CC_LOOKUPS  => 0,
        CC6_LOOKUPS => 0,
        HOST        => '/definitely/missing/host',
        URLGET      => 1,
        URLPROXY    => '',
        CC_SRC      => 1,
    });

    is(
        ConfigServer::LookUpIP::iplookup('203.0.113.5'),
        '203.0.113.5',
        'disabled lookups fall back to the original IP string',
    );
};

subtest 'iplookup formats country lookups in CC_LOOKUPS=1 mode and strips quotes from display output' => sub {
    reload_lookupip_module({
        LF_LOOKUPS  => 0,
        CC_LOOKUPS  => 1,
        CC6_LOOKUPS => 1,
        HOST        => '/definitely/missing/host',
        URLGET      => 1,
        URLPROXY    => '',
        CC_SRC      => 1,
    });

    no warnings qw(redefine once);
    local *ConfigServer::LookUpIP::geo_binary = sub {
        return ('U"S', 'United "States"');
    };

    is(
        ConfigServer::LookUpIP::iplookup('203.0.113.5'),
        '203.0.113.5 (US/United States/-)',
        'country-only lookup renders the compact display format and removes quotes',
    );
};

subtest 'iplookup formats city lookups in CC_LOOKUPS=2 mode and cconly returns just the country code' => sub {
    reload_lookupip_module({
        LF_LOOKUPS  => 0,
        CC_LOOKUPS  => 2,
        CC6_LOOKUPS => 1,
        HOST        => '/definitely/missing/host',
        URLGET      => 1,
        URLPROXY    => '',
        CC_SRC      => 1,
    });

    no warnings qw(redefine once);
    local *ConfigServer::LookUpIP::geo_binary = sub {
        return ('DE', 'Germany', 'Bavaria', 'Munich');
    };

    is(
        ConfigServer::LookUpIP::iplookup('203.0.113.5'),
        '203.0.113.5 (DE/Germany/Bavaria/Munich/-)',
        'city lookup renders the expanded CC_LOOKUPS=2 display format',
    );

    is(
        ConfigServer::LookUpIP::iplookup('203.0.113.5', 1),
        'DE',
        'cconly mode returns only the country code in CC_LOOKUPS=2 mode',
    );
};

subtest 'iplookup returns the raw ASN tuple in cconly mode and the bracketed ASN in CC_LOOKUPS=3 display mode' => sub {
    reload_lookupip_module({
        LF_LOOKUPS  => 0,
        CC_LOOKUPS  => 3,
        CC6_LOOKUPS => 1,
        HOST        => '/definitely/missing/host',
        URLGET      => 1,
        URLPROXY    => '',
        CC_SRC      => 1,
    });

    no warnings qw(redefine once);
    local *ConfigServer::LookUpIP::geo_binary = sub {
        return ('GB', 'United Kingdom', 'England', 'London', 'AS64496 Example "Net"');
    };

    my ($cc, $asn) = ConfigServer::LookUpIP::iplookup('203.0.113.5', 1);
    is($cc, 'GB', 'cconly CC_LOOKUPS=3 returns the country code');
    is($asn, 'AS64496 Example "Net"', 'cconly CC_LOOKUPS=3 returns the raw ASN text without display decoration');

    is(
        ConfigServer::LookUpIP::iplookup('203.0.113.5'),
        '203.0.113.5 (GB/United Kingdom/England/London/-/[AS64496 Example Net])',
        'full CC_LOOKUPS=3 display output includes the bracketed ASN and strips quotes',
    );
};

subtest 'geo_binary returns nothing for private addresses before any database lookup work' => sub {
    reload_lookupip_module({
        LF_LOOKUPS  => 0,
        CC_LOOKUPS  => 1,
        CC6_LOOKUPS => 1,
        HOST        => '/definitely/missing/host',
        URLGET      => 1,
        URLPROXY    => '',
        CC_SRC      => 1,
    });

    my @result = ConfigServer::LookUpIP::geo_binary('192.168.1.10', 4);
    is_deeply(
        \@result,
        [],
        'private addresses short-circuit without attempting Geo database lookups',
    );
};

subtest 'geo_binary uses the db-ip API client in CC_LOOKUPS=4 mode and decodes JSON fields' => sub {
    my $client = Local::LookUpIPURLGet->new(
        response => [
            0,
            '{"countryCode":"MK","countryName":"North Macedonia","stateProv":"Skopje","city":"Skopje"}',
        ],
    );

    reload_lookupip_module(
        {
            LF_LOOKUPS  => 0,
            CC_LOOKUPS  => 4,
            CC6_LOOKUPS => 1,
            HOST        => '/definitely/missing/host',
            URLGET      => 1,
            URLPROXY    => 'http://proxy.test:8080',
            CC_SRC      => 1,
        },
        urlget_client => $client,
    );

    my @result = ConfigServer::LookUpIP::geo_binary('8.8.8.8', 4);

    is_deeply(
        \@result,
        [ 'MK', 'North Macedonia', 'Skopje', 'Skopje' ],
        'db-ip API responses are decoded into country, name, region, and city fields',
    );
    is_deeply(
        [ $client->seen_urls() ],
        ['http://api.db-ip.com/v2/free/8.8.8.8'],
        'db-ip API client is called with the requested IP address',
    );
};

subtest 'geo_binary returns nothing when the db-ip API client reports failure or empty content' => sub {
    my $failing_client = Local::LookUpIPURLGet->new(response => [1, 'upstream failed']);

    reload_lookupip_module(
        {
            LF_LOOKUPS  => 0,
            CC_LOOKUPS  => 4,
            CC6_LOOKUPS => 1,
            HOST        => '/definitely/missing/host',
            URLGET      => 1,
            URLPROXY    => '',
            CC_SRC      => 1,
        },
        urlget_client => $failing_client,
    );

    my @failed = ConfigServer::LookUpIP::geo_binary('1.1.1.1', 4);
    is_deeply(\@failed, [], 'failed db-ip requests return no geo data');

    my $empty_client = Local::LookUpIPURLGet->new(response => [0, '']);

    reload_lookupip_module(
        {
            LF_LOOKUPS  => 0,
            CC_LOOKUPS  => 4,
            CC6_LOOKUPS => 1,
            HOST        => '/definitely/missing/host',
            URLGET      => 1,
            URLPROXY    => '',
            CC_SRC      => 1,
        },
        urlget_client => $empty_client,
    );

    my @empty = ConfigServer::LookUpIP::geo_binary('1.0.0.1', 4);
    is_deeply(\@empty, [], 'empty db-ip responses also return no geo data');
};

done_testing;

#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

{
    package Local::GetEthDevConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }

    sub ipv4reg {
        require ConfigServer::Config;
        return ConfigServer::Config::ipv4reg();
    }

    sub ipv6reg {
        require ConfigServer::Config;
        return ConfigServer::Config::ipv6reg();
    }
}

sub with_mock_getethdev {
    my ($config, $code) = @_;

    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::GetEthDevConfig->new($config);
    };

    delete $INC{'ConfigServer/GetEthDev.pm'};
    require ConfigServer::GetEthDev;

    return $code->();
}

sub build_fake_command {
    my ($dir, $name, $output) = @_;

    my $script = File::Spec->catfile($dir, $name);

    open(my $fh, '>', $script) or die "Unable to create $script: $!";
    print {$fh} "#!/bin/sh\n";
    print {$fh} "cat <<'OUT'\n";
    print {$fh} $output;
    print {$fh} "OUT\n";
    close($fh);

    chmod 0755, $script or die "Unable to chmod $script: $!";
    return $script;
}

subtest 'new() parses ip -oneline addr output into interface, IPv4, IPv6, and broadcast sets' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $ip_bin = build_fake_command(
        $dir,
        'fake-ip',
        <<'OUT',
1: lo    inet 127.0.0.1/8 scope host lo
1: lo    inet6 ::1/128 scope host 
2: eth0    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth0
2: eth0    inet6 2001:db8::10/64 scope global 
3: eth0.100    inet 198.51.100.5/27 brd 198.51.100.31 scope global eth0.100
OUT
    );

    with_mock_getethdev(
        {
            IP       => $ip_bin,
            IFCONFIG => '/definitely/missing/ifconfig',
        },
        sub {
            my $ethdev = ConfigServer::GetEthDev->new();
            my %ifaces = $ethdev->ifaces();
            my %ipv4   = $ethdev->ipv4();
            my %ipv6   = $ethdev->ipv6();
            my %brd    = $ethdev->brd();

            is($ethdev->{status}, 0, 'ip helper path returns a successful status');
            is_deeply(
                [ sort keys %ifaces ],
                [ 'eth0', 'eth0.100', 'lo' ],
                'all interfaces from ip output are discovered',
            );
            is_deeply(
                [ sort keys %ipv4 ],
                [ '192.0.2.10', '198.51.100.5' ],
                'non-loopback IPv4 addresses are collected from ip output',
            );
            is_deeply(
                [ sort keys %ipv6 ],
                [ '2001:db8::10/128' ],
                'IPv6 addresses are normalised and stored with a /128 suffix',
            );
            ok($brd{'255.255.255.255'}, 'default broadcast address is always present');
            ok($brd{'192.0.2.255'}, 'broadcast address from ip output is collected');
            ok($brd{'198.51.100.31'}, 'additional broadcast addresses are collected');
        },
    );
};

subtest 'new() falls back to ifconfig output when ip is unavailable' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $ifconfig_bin = build_fake_command(
        $dir,
        'fake-ifconfig',
        <<'OUT',
eth1      Link encap:Ethernet  HWaddr 52:54:00:12:34:56
          inet addr:203.0.113.9  Bcast:203.0.113.255  Mask:255.255.255.0
          inet6 addr: 2001:db8:1::25/64 Scope:Global
lo        Link encap:Local Loopback
          inet addr:127.0.0.1  Mask:255.0.0.0
OUT
    );

    with_mock_getethdev(
        {
            IP       => '/definitely/missing/ip',
            IFCONFIG => $ifconfig_bin,
        },
        sub {
            my $ethdev = ConfigServer::GetEthDev->new();
            my %ifaces = $ethdev->ifaces();
            my %ipv4   = $ethdev->ipv4();
            my %ipv6   = $ethdev->ipv6();
            my %brd    = $ethdev->brd();

            is($ethdev->{status}, 0, 'ifconfig fallback also reports success');
            is_deeply(
                [ sort keys %ifaces ],
                [ 'eth1', 'lo' ],
                'interface names are parsed from ifconfig output',
            );
            is_deeply(
                [ sort keys %ipv4 ],
                ['203.0.113.9'],
                'ifconfig fallback collects non-loopback IPv4 addresses',
            );
            is_deeply(
                [ sort keys %ipv6 ],
                ['2001:db8:1::25/128'],
                'ifconfig fallback collects and normalises IPv6 addresses',
            );
            ok($brd{'255.255.255.255'}, 'default broadcast address survives the fallback path');
            ok($brd{'203.0.113.255'}, 'broadcast address is parsed from ifconfig output');
        },
    );
};

subtest 'new() reports status 1 when neither ip nor ifconfig is available' => sub {
    with_mock_getethdev(
        {
            IP       => '/definitely/missing/ip',
            IFCONFIG => '/definitely/missing/ifconfig',
        },
        sub {
            my $ethdev = ConfigServer::GetEthDev->new();
            my %ifaces = $ethdev->ifaces();
            my %ipv4   = $ethdev->ipv4();
            my %ipv6   = $ethdev->ipv6();
            my %brd    = $ethdev->brd();

            is($ethdev->{status}, 1, 'missing helpers report a non-zero status');
            is_deeply([ sort keys %ifaces ], [], 'no interfaces are discovered without helpers');
            is_deeply([ sort keys %ipv4 ],   [], 'no IPv4 addresses are discovered without helpers');
            is_deeply([ sort keys %ipv6 ],   [], 'no IPv6 addresses are discovered without helpers');
            is_deeply(
                [ sort keys %brd ],
                ['255.255.255.255'],
                'default broadcast address is still initialised without helpers',
            );
        },
    );
};

done_testing;

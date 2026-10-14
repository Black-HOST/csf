#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

# ServerCheck pulls in ConfigServer::Service, which caches loadconfig() at
# import time and rejects an empty IPTABLES path. Prime the module chain with
# a benign mocked config before any other test code touches it.
#
# NOTE: ServerCheck.pm intentionally has a small unit-test surface here.
# Almost every public sub (report, firewallcheck, servicescheck, mailcheck,
# apachecheck, phpcheck, whmcheck, sshtelnetcheck, dacheck) opens hardcoded
# paths under /etc/csf, /proc, and various control-panel install prefixes,
# shells out to iptables/systemctl/chkconfig, and writes results to a
# file-scope $output lexical. Without refactor-time seams these cannot be
# driven from a unit test on this machine. Phase B should extract the
# parsing helpers (firewall config line parser, services list filter,
# /proc/net port scan) into pure modules.
BEGIN {
    TestBootstrap::reload_module_with_config(
        'ConfigServer::ServerCheck',
        { IPTABLES => '/bin/true', HOST => '/bin/true', IPV6 => 0, DEBUG => 0 },
        also_delete => [qw(ConfigServer::Service ConfigServer::GetIPs)],
    );
}

subtest 'module loads cleanly and exposes the documented check entry points' => sub {
    can_ok(
        'ConfigServer::ServerCheck',
        qw(
            report startoutput endoutput addline addtitle
            firewallcheck servercheck mailcheck apachecheck phpcheck
            whmcheck dacheck sshtelnetcheck servicescheck getportinfo
        ),
    );
};

subtest 'ipv4reg and ipv6reg class methods return non-empty regex strings' => sub {
    require ConfigServer::Config;

    my $v4 = ConfigServer::Config->ipv4reg;
    my $v6 = ConfigServer::Config->ipv6reg;

    ok(defined $v4 && length $v4, 'ipv4reg returns a non-empty regex string');
    ok(defined $v6 && length $v6, 'ipv6reg returns a non-empty regex string');
    like('192.0.2.10', qr/^$v4$/, 'ipv4reg matches a dotted-quad IPv4 address');
    like('2001:db8::1', qr/^$v6$/, 'ipv6reg matches a compact IPv6 address');
};

subtest 'getportinfo returns 0 for ports that cannot occur in /proc/net' => sub {
    SKIP: {
        skip 'Linux /proc/net is required for getportinfo', 2
            unless -r '/proc/net/tcp';

        # Port numbers above 65535 cannot be present in any /proc/net file, so
        # getportinfo must return 0 regardless of what is actually bound.
        my $hit = ConfigServer::ServerCheck::getportinfo(99999);
        is($hit, 0, 'out-of-range port number is reported as not listening');

        my $hit_neg = ConfigServer::ServerCheck::getportinfo(-1);
        is($hit_neg, 0, 'negative port number is reported as not listening');
    }
};

done_testing;

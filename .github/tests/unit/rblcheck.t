#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

# RBLCheck pulls in GetIPs and RBLLookup, which both validate IPTABLES/HOST in
# Config::loadconfig at import time. Load the whole chain once with a benign
# mocked config before any other test code touches the module.
BEGIN {
    TestBootstrap::reload_module_with_config(
        'ConfigServer::RBLCheck',
        { IPTABLES => '/bin/true', HOST => '/bin/true', IPV6 => 0, DEBUG => 0 },
        also_delete => [qw(ConfigServer::GetIPs ConfigServer::RBLLookup)],
    );
}

{
    package Local::FakeEthDev;

    sub new {
        my ($class, %args) = @_;
        return bless { ipv4 => $args{ipv4} || {} }, $class;
    }

    sub ipv4   { return %{ $_[0]->{ipv4} } }
    sub ipv6   { return () }
    sub ifaces { return () }
}

sub run_report_with_ips {
    my ($ipv4) = @_;

    # RBLCheck caches $output as a file-scope lexical that persists across
    # report() calls. Reload the module so each test sees a fresh output buffer.
    TestBootstrap::reload_module_with_config(
        'ConfigServer::RBLCheck',
        { IPTABLES => '/bin/true', HOST => '/bin/true', IPV6 => 0, DEBUG => 0 },
    );

    no warnings qw(redefine once);
    local *ConfigServer::GetEthDev::new = sub {
        return Local::FakeEthDev->new(ipv4 => $ipv4);
    };
    local *ConfigServer::RBLCheck::slurp = sub { return () };
    local *ConfigServer::RBLCheck::rbllookup = sub { return ('', '') };

    my @result;
    TestBootstrap::with_mock_config(
        { IPTABLES => '/bin/true', HOST => '/bin/true', IPV6 => 0, DEBUG => 0 },
        sub { @result = ConfigServer::RBLCheck::report(0, 0, 0) },
    );
    return @result;
}

subtest 'module loads cleanly and exposes the public reporting surface' => sub {
    can_ok('ConfigServer::RBLCheck', qw(report addline addtitle startoutput endoutput getethdev));
};

subtest 'report() returns zero failures and a minimal output when no IPs are discovered' => sub {
    my ($failures, $output) = run_report_with_ips({});

    is($failures, 0, 'no IPs means no failures are recorded');
    ok(defined $output && length $output, 'report still emits the endoutput marker even with no IPs');
    like($output, qr/<br>/, 'output contains the closing <br> from endoutput');
    unlike($output, qr/Not Checked/, 'no IPs means no per-IP "Not Checked" placeholder is added');
};

subtest 'report() marks a fresh PUBLIC IP as Not Checked in non-verbose mode' => sub {
    my $ip = '8.8.8.8';

    SKIP: {
        skip "cached RBL state for $ip already exists on this host", 3
            if -e "/var/lib/csf/$ip.rbls";

        eval { require Net::IP; 1 } or skip 'Net::IP is not available', 3;
        my $type = eval { Net::IP->new($ip)->iptype };
        skip "Net::IP classifies $ip as $type (expected PUBLIC)", 3
            unless defined $type && $type eq 'PUBLIC';

        my ($failures, $output) = run_report_with_ips({ $ip => 1 });

        is($failures, 0, 'a non-verbose Not Checked entry does not count as a failure');
        like($output, qr/\QNew $ip (PUBLIC)\E/, 'addtitle announces the new public IP that has no cached result');
        like($output, qr/Not Checked/, 'placeholder confirms the IP has not been actively checked');
    }
};

subtest 'report() silently skips non-PUBLIC IPs when verbose is off' => sub {
    my ($failures, $output) = run_report_with_ips({ '10.0.0.1' => 1 });

    is($failures, 0, 'a skipped private IP does not raise the failure count');
    unlike($output, qr/10\.0\.0\.1/, 'a non-PUBLIC IP produces no titled output in non-verbose mode');
    unlike($output, qr/Not Checked/, 'no Not Checked placeholder is emitted for skipped IPs');
};

done_testing;

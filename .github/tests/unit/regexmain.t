#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

{
    package Local::RegexMainConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }

    sub ipv4reg {
        return q/(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3}/;
    }

    sub ipv6reg {
        return q/[0-9a-fA-F:]+/;
    }
}

{
    package Local::RegexMainEthDev;

    sub new {
        return bless {}, shift;
    }

    sub brd {
        return;
    }

    sub ipv4 {
        return;
    }
}

sub reload_regexmain_module {
    my ($config_override) = @_;

    my %config = (
        LF_APACHE_ERRPORT   => 1,
        LF_SSHD             => 1,
        LF_SSH_EMAIL_ALERT  => 1,
        %{ $config_override || {} },
    );

    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::RegexMainConfig->new(\%config);
    };
    local $INC{'ConfigServer/Logger.pm'}    = __FILE__;
    local $INC{'ConfigServer/GetEthDev.pm'} = __FILE__;
    local *ConfigServer::Logger::import = sub { return; };
    local *ConfigServer::GetEthDev::import = sub { return; };
    local *ConfigServer::Logger::logfile = sub {
        return;
    };
    local *ConfigServer::GetEthDev::new = sub {
        return Local::RegexMainEthDev->new();
    };

    delete $INC{'ConfigServer/RegexMain.pm'};
    require ConfigServer::RegexMain;

    return 1;
}

sub call_processline {
    my (%opts) = @_;

    my $line = $opts{line};
    my $lgfile = $opts{lgfile} // '/var/log/secure';
    my %globlogs = %{ $opts{globlogs} || {} };

    local %ConfigServer::RegexMain::config = (
        %ConfigServer::RegexMain::config,
        %{ $opts{config} || {} },
    );

    return ConfigServer::RegexMain::processline($line, $lgfile, \%globlogs);
}

sub call_processsshline {
    my (%opts) = @_;

    local %ConfigServer::RegexMain::config = (
        %ConfigServer::RegexMain::config,
        %{ $opts{config} || {} },
    );

    return ConfigServer::RegexMain::processsshline($opts{line});
}

sub assert_no_event {
    my ($label, @result) = @_;

    my $first = @result ? $result[0] : undef;
    ok(!$first, $label);
}

reload_regexmain_module();

subtest 'processline parses all SSH failure branch formats deterministically' => sub {
    my @cases = (
        {
            name => 'pam_unix auth failure line',
            line => 'Jan 5 10:00:00 host sshd[1000]: pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=203.0.113.10 user=alice',
            want => [ 'Failed SSH login from', '203.0.113.10|alice', 'sshd' ],
        },
        {
            name => 'pam_unix auth failure line from sshd-session strips ::ffff prefix',
            line => 'Jan 5 10:00:01 host sshd-session[1001]: pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=::ffff:203.0.113.11 user=bob',
            want => [ 'Failed SSH login from', '203.0.113.11|bob', 'sshd' ],
        },
        {
            name => 'Failed none branch',
            line => 'Jan 5 10:00:02 host sshd[1002]: Failed none for root from 203.0.113.12 port 22 ssh2',
            want => [ 'Failed SSH login from', '203.0.113.12|root', 'sshd' ],
        },
        {
            name => 'Failed password branch strips ::ffff prefix',
            line => 'Jan 5 10:00:03 host sshd[1003]: Failed password for root from ::ffff:203.0.113.13 port 22 ssh2',
            want => [ 'Failed SSH login from', '203.0.113.13|root', 'sshd' ],
        },
        {
            name => 'Failed keyboard-interactive branch',
            line => 'Jan 5 10:00:04 host sshd[1004]: Failed keyboard-interactive/pam for invalid user guest from 198.51.100.14 port 22 ssh2',
            want => [ 'Failed SSH login from', '198.51.100.14|invalid user ', 'sshd' ],
        },
        {
            name => 'Invalid user branch with single-token timestamp format',
            line => '2026-01-05T10:00:05+00:00 host sshd[1005]: Invalid user admin from 198.51.100.15',
            want => [ 'Failed SSH login from', '198.51.100.15|admin', 'sshd' ],
        },
        {
            name => 'AllowUsers restriction branch',
            line => 'Jan 5 10:00:06 host sshd[1006]: User deploy from 198.51.100.16 not allowed because not listed in AllowUsers',
            want => [ 'Failed SSH login from', '198.51.100.16|deploy', 'sshd' ],
        },
        {
            name => 'missing identification string branch',
            line => 'Jan 5 10:00:07 host sshd[1007]: Did not receive identification string from 198.51.100.17',
            want => [ 'Failed SSH login from', '198.51.100.17|', 'sshd' ],
        },
        {
            name => 'refused connect branch',
            line => 'Jan 5 10:00:08 host sshd[1008]: refused connect from 198.51.100.18',
            want => [ 'Failed SSH login from', '198.51.100.18|', 'sshd' ],
        },
        {
            name => 'maximum authentication attempts exceeded branch',
            line => 'Jan 5 10:00:09 host sshd[1009]: error: maximum authentication attempts exceeded for root from 198.51.100.19',
            want => [ 'Failed SSH login from', '198.51.100.19|', 'sshd' ],
        },
        {
            name => 'Illegal user branch',
            line => 'Jan 5 10:00:10 host sshd[1010]: Illegal user test from 198.51.100.20',
            want => [ 'Failed SSH login from', '198.51.100.20|test', 'sshd' ],
        },
        {
            name => 'Gentoo PAM authentication failure branch',
            line => 'Jan 5 10:00:11 host sshd[1011]: error: PAM: Authentication failure for ops from 198.51.100.21',
            want => [ 'Failed SSH login from', '198.51.100.21|ops', 'sshd' ],
        },
    );

    for my $case (@cases) {
        my @got = call_processline(line => $case->{line});
        is_deeply(\@got, $case->{want}, $case->{name});
    }
};

subtest 'processline SSH gating uses LF_SSHD, log-path allowlist, and checkip validation' => sub {
    my $line = 'Jan 5 10:01:00 host sshd[1100]: Failed password for root from 203.0.113.50 port 22 ssh2';

    my @disabled = call_processline(
        line => $line,
        config => { LF_SSHD => 0 },
    );
    assert_no_event('LF_SSHD=0 disables SSH processline detection', @disabled);

    my @wrong_file = call_processline(
        line => $line,
        lgfile => '/var/log/auth.log',
    );
    assert_no_event('non-SSHD logfile does not match by default', @wrong_file);

    my @globlog_match = call_processline(
        line => $line,
        lgfile => '/custom/ssh.log',
        globlogs => { SSHD_LOG => { '/custom/ssh.log' => 1 } },
    );
    is_deeply(
        \@globlog_match,
        [ 'Failed SSH login from', '203.0.113.50|root', 'sshd' ],
        'SSHD_LOG map enables custom log path matching',
    );

    my @loopback = call_processline(
        line => 'Jan 5 10:01:01 host sshd[1101]: Failed password for root from 127.0.0.1 port 22 ssh2',
    );
    assert_no_event('loopback addresses are rejected by checkip and return no event', @loopback);

    my @unrelated = call_processline(
        line => 'Jan 5 10:01:02 host sshd[1102]: Accepted password for root from 203.0.113.51 port 22 ssh2',
    );
    assert_no_event('non-failure SSH lines are ignored by processline', @unrelated);
};

subtest 'processsshline helper parses accepted logins and enforces guards' => sub {
    my @password = call_processsshline(
        line => 'Jan 5 10:02:00 host sshd[1200]: Accepted password for root from ::ffff:203.0.113.60 port 22 ssh2',
    );
    is_deeply(
        \@password,
        [ 'root', '203.0.113.60', 'password' ],
        'Accepted password events return account, normalized IP, and method',
    );

    my @pubkey = call_processsshline(
        line => 'Jan 5 10:02:01 host sshd[1201]: Accepted publickey for deploy from 198.51.100.61 port 2222 ssh2',
    );
    is_deeply(
        \@pubkey,
        [ 'deploy', '198.51.100.61', 'publickey' ],
        'Accepted publickey events are parsed correctly',
    );

    my @disabled = call_processsshline(
        line => 'Jan 5 10:02:02 host sshd[1202]: Accepted password for root from 203.0.113.62 port 22 ssh2',
        config => { LF_SSH_EMAIL_ALERT => 0 },
    );
    assert_no_event('LF_SSH_EMAIL_ALERT=0 disables processsshline output', @disabled);

    my @loopback = call_processsshline(
        line => 'Jan 5 10:02:03 host sshd[1203]: Accepted password for root from 127.0.0.1 port 22 ssh2',
    );
    assert_no_event('loopback addresses are rejected for accepted-login alerts', @loopback);

    my @session_binary = call_processsshline(
        line => 'Jan 5 10:02:04 host sshd-session[1204]: Accepted password for root from 203.0.113.63 port 22 ssh2',
    );
    assert_no_event('sshd-session accepted lines are not matched by processsshline', @session_binary);
};

done_testing;

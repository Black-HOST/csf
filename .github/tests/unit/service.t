#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Temp qw(tempfile);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

{
    package Local::ServiceConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

sub with_mock_service_module {
    my ($config, %opts) = @_;
    my $code = delete $opts{code} or die 'code callback is required';
    my $sysinit = $opts{sysinit} // 'init';

    require ConfigServer::Config;

    my ($fh, $path) = tempfile();
    print {$fh} "$sysinit\n";
    close($fh);

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::ServiceConfig->new($config);
    };

    local *CORE::GLOBAL::open = sub(*;$@) {
        if (@_ >= 3 && defined $_[2] && $_[2] eq '/proc/1/comm') {
            return CORE::open($_[0], $_[1], $path);
        }
        return CORE::open($_[0], $_[1], @_[2 .. $#_]);
    };

    delete $INC{'ConfigServer/Service.pm'};
    require ConfigServer::Service;

    return $code->();
}

subtest 'type reports the detected init system from /proc/1/comm' => sub {
    with_mock_service_module(
        { SYSTEMCTL => '/bin/systemctl', DIRECTADMIN => 0 },
        sysinit => 'systemd',
        code => sub {
            is(ConfigServer::Service::type(), 'systemd', 'systemd is preserved when detected');
        },
    );

    with_mock_service_module(
        { SYSTEMCTL => '/bin/systemctl', DIRECTADMIN => 0 },
        sysinit => 'launchd',
        code => sub {
            is(ConfigServer::Service::type(), 'init', 'non-systemd values collapse to init mode');
        },
    );
};

subtest 'service actions dispatch the expected commands in systemd mode' => sub {
    with_mock_service_module(
        { SYSTEMCTL => '/usr/bin/systemctl', DIRECTADMIN => 0 },
        sysinit => 'systemd',
        code => sub {
            my @calls;

            no warnings qw(redefine once);
            local *ConfigServer::Service::printcmd = sub {
                push @calls, [@_];
                return;
            };

            ConfigServer::Service::startlfd();
            ConfigServer::Service::stoplfd();
            ConfigServer::Service::restartlfd();
            is(ConfigServer::Service::statuslfd(), 0, 'statuslfd returns 0 in systemd mode');

            is_deeply(
                \@calls,
                [
                    ['/usr/bin/systemctl', 'start',   'lfd.service'],
                    ['/usr/bin/systemctl', 'status',  'lfd.service'],
                    ['/usr/bin/systemctl', 'stop',    'lfd.service'],
                    ['/usr/bin/systemctl', 'restart', 'lfd.service'],
                    ['/usr/bin/systemctl', 'status',  'lfd.service'],
                    ['/usr/bin/systemctl', 'status',  'lfd.service'],
                ],
                'systemd mode uses systemctl for start/stop/restart/status operations',
            );
        },
    );
};

subtest 'service actions dispatch the expected commands in init mode' => sub {
    with_mock_service_module(
        { SYSTEMCTL => '/usr/bin/systemctl', DIRECTADMIN => 0 },
        sysinit => 'init',
        code => sub {
            my @calls;

            no warnings qw(redefine once);
            local *ConfigServer::Service::printcmd = sub {
                push @calls, [@_];
                return;
            };

            ConfigServer::Service::startlfd();
            ConfigServer::Service::stoplfd();
            ConfigServer::Service::restartlfd();
            is(ConfigServer::Service::statuslfd(), 0, 'statuslfd returns 0 in init mode');

            is_deeply(
                \@calls,
                [
                    ['/etc/init.d/lfd', 'start'],
                    ['/etc/init.d/lfd', 'stop'],
                    ['/etc/init.d/lfd', 'restart'],
                    ['/etc/init.d/lfd', 'status'],
                ],
                'init mode uses the legacy init script for service operations',
            );
        },
    );
};

done_testing;

#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();
use Fcntl qw(:DEFAULT);

{
    package Local::LoggerConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

sub with_mock_logger_module {
    my ($config, %opts) = @_;
    my $code = delete $opts{code} or die 'code callback is required';

    require ConfigServer::Config;

    my ($host_fh, $host_path) = tempfile();
    print {$host_fh} (($opts{hostname} // 'unit-host.example.test') . "\n");
    close($host_fh);

    my $dir = tempdir(CLEANUP => 1);
    my $captured_log = File::Spec->catfile($dir, 'captured.log');
    my $requested_path;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::LoggerConfig->new($config);
    };

    local *CORE::GLOBAL::open = sub(*;$@) {
        if (@_ >= 3 && defined $_[2] && $_[2] eq '/proc/sys/kernel/hostname') {
            return CORE::open($_[0], $_[1], $host_path);
        }
        return CORE::open($_[0], $_[1], @_[2 .. $#_]);
    };

    local *CORE::GLOBAL::sysopen = sub(*$$;$) {
        $requested_path = $_[1];
        return CORE::open($_[0], '>>', $captured_log);
    };

    my @inc = @INC;
    if ($opts{missing_syslog}) {
        delete $INC{'Sys/Syslog.pm'};
        unshift @inc, sub {
            my (undef, $file) = @_;
            die "mock missing $file\n" if $file eq 'Sys/Syslog.pm';
            return;
        };
    }
    local @INC = @inc;

    local $SIG{__WARN__} = sub {
        return if $_[0] =~ /Subroutine .* redefined/;
        return if $_[0] =~ /Constant subroutine .* redefined/;
        warn @_;
    };

    delete $INC{'ConfigServer/Logger.pm'};
    require ConfigServer::Logger;

    return $code->($captured_log, \$requested_path);
}

sub slurp_file {
    my ($path) = @_;

    open(my $fh, '<', $path) or die "Unable to read $path: $!";
    local $/;
    my $content = <$fh>;
    close($fh);
    return $content;
}

sub expected_log_path {
    return $< == 0 ? '/var/log/lfd.log' : '/var/log/lfd_messenger.log';
}

sub expected_hostshort {
    my ($wanted) = @_;
    return -e '/proc/sys/kernel/hostname' ? $wanted : 'unknown';
}

subtest 'logfile writes a formatted log line to the expected log target' => sub {
    with_mock_logger_module(
        { SYSLOG => 0 },
        hostname => 'spark.box.test',
        code => sub {
            my ($captured_log, $requested_path_ref) = @_;

            ConfigServer::Logger::logfile('unit test message');

            is($$requested_path_ref, expected_log_path(), 'logger selects the expected logfile path for the current uid');

            my $content = slurp_file($captured_log);
            like(
                $content,
                qr/^\w{3}\s+\d+\s+\d\d:\d\d:\d\d \Q@{[expected_hostshort('spark')]}\E lfd\[\d+\]: unit test message\n$/,
                'written log line includes timestamp, short hostname, pid, and message',
            );
        },
    );
};

subtest 'logfile does not touch syslog helpers when SYSLOG is disabled' => sub {
    with_mock_logger_module(
        { SYSLOG => 0 },
        hostname => 'quiet.example.test',
        code => sub {
            my ($captured_log, undef) = @_;
            my $called = 0;

            no warnings qw(redefine once);
            local *ConfigServer::Logger::openlog = sub { $called++ };
            local *ConfigServer::Logger::syslog = sub { $called++ };
            local *ConfigServer::Logger::closelog = sub { $called++ };

            ConfigServer::Logger::logfile('file only');

            is($called, 0, 'syslog helpers are skipped entirely when SYSLOG is disabled');
            like(slurp_file($captured_log), qr/file only\n$/, 'local file logging still occurs');
        },
    );
};

subtest 'logfile mirrors messages to syslog when SYSLOG is enabled' => sub {
    with_mock_logger_module(
        { SYSLOG => 1 },
        hostname => 'volt.example.test',
        code => sub {
            my ($captured_log, $requested_path_ref) = @_;
            my @openlog_args;
            my @syslog_args;
            my $closelog_called = 0;

            no warnings qw(redefine once);
            local *ConfigServer::Logger::openlog = sub { @openlog_args = @_ };
            local *ConfigServer::Logger::syslog  = sub { @syslog_args  = @_ };
            local *ConfigServer::Logger::closelog = sub { $closelog_called++ };

            ConfigServer::Logger::logfile('ship to syslog');

            is($$requested_path_ref, expected_log_path(), 'file logging still uses the expected logfile path when syslog is enabled');
            is_deeply(\@openlog_args, ['lfd', 'ndelay,pid', 'user'], 'syslog is opened with the expected ident and facility');
            is_deeply(\@syslog_args, ['info', 'ship to syslog'], 'syslog receives the info-level message');
            is($closelog_called, 1, 'syslog session is closed after writing');

            my $content = slurp_file($captured_log);
            like($content, qr/\Q@{[expected_hostshort('volt')]}\E lfd\[\d+\]: ship to syslog\n$/, 'file logging still records the message locally');
        },
    );
};

subtest 'logfile skips syslog calls when Sys::Syslog could not be loaded at module init time' => sub {
    with_mock_logger_module(
        { SYSLOG => 1 },
        hostname => 'missing-syslog.example.test',
        missing_syslog => 1,
        code => sub {
            my ($captured_log, undef) = @_;
            my $called = 0;

            no warnings qw(redefine once);
            local *ConfigServer::Logger::openlog = sub { $called++ };
            local *ConfigServer::Logger::syslog = sub { $called++ };
            local *ConfigServer::Logger::closelog = sub { $called++ };

            ConfigServer::Logger::logfile('no syslog backend');

            is($called, 0, 'syslog helpers are not invoked when Sys::Syslog failed to load');
            like(slurp_file($captured_log), qr/no syslog backend\n$/, 'local file logging still happens without the syslog backend');
        },
    );
};

subtest 'logfile swallows syslog exceptions and still writes the local log entry' => sub {
    with_mock_logger_module(
        { SYSLOG => 1 },
        hostname => 'arc.example.test',
        code => sub {
            my ($captured_log, undef) = @_;

            no warnings qw(redefine once);
            local *ConfigServer::Logger::openlog = sub { die 'simulated syslog failure' };
            local *ConfigServer::Logger::syslog = sub { die 'should not reach syslog' };
            local *ConfigServer::Logger::closelog = sub { die 'should not reach closelog' };

            my $ok = eval { ConfigServer::Logger::logfile('local survives'); 1 };
            ok($ok, 'logger does not die when syslog integration throws an exception');

            my $content = slurp_file($captured_log);
            like($content, qr/\Q@{[expected_hostshort('arc')]}\E lfd\[\d+\]: local survives\n$/, 'local file logging still succeeds when syslog fails');
        },
    );
};

subtest 'logfile uses the short hostname prefix when /proc hostname is available' => sub {
    SKIP: {
        skip 'hostname branch requires /proc/sys/kernel/hostname to exist on this host', 2
            unless -e '/proc/sys/kernel/hostname';

        with_mock_logger_module(
            { SYSLOG => 0 },
            hostname => 'neon.edge.example.test',
            code => sub {
                my ($captured_log, undef) = @_;

                ConfigServer::Logger::logfile('short host');

                my $content = slurp_file($captured_log);
                like($content, qr/ neon lfd\[\d+\]: short host\n$/, 'only the first hostname label is written to the log line');
                unlike($content, qr/neon\.edge\.example\.test/, 'full dotted hostname is not written to the log line');
            },
        );
    }
};

done_testing;

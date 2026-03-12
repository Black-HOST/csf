#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once';

use FindBin qw($Bin);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

{
    package Local::KillSSHConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

sub reload_killssh_module {
    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::KillSSHConfig->new({ SYSLOG => 0 });
    };

    delete $INC{'ConfigServer/Logger.pm'};
    delete $INC{'ConfigServer/KillSSH.pm'};
    require ConfigServer::KillSSH;
    return 1;
}

sub write_text_file {
    my ($path, $content) = @_;
    my (undef, $dir) = File::Spec->splitpath($path);
    make_path($dir) unless -d $dir;

    open(my $fh, '>', $path) or die "Unable to write $path: $!";
    print {$fh} $content;
    close($fh);
    return;
}

sub create_proc_process {
    my ($root, %opts) = @_;

    my $pid = $opts{pid};
    my $fd_dir = File::Spec->catdir($root, $pid, 'fd');
    make_path($fd_dir);

    symlink($opts{exe}, File::Spec->catfile($root, $pid, 'exe'))
        or die "Unable to create exe symlink for $pid: $!";

    my $fd_name = $opts{fd_name} // '5';
    symlink($opts{socket_target}, File::Spec->catfile($fd_dir, $fd_name))
        or die "Unable to create fd symlink for $pid: $!";

    return;
}

sub with_mock_proc_root {
    my (%opts) = @_;
    my $code = delete $opts{code} or die 'code callback is required';

    my $root = tempdir(CLEANUP => 1);
    make_path(File::Spec->catdir($root, 'net'));

    write_text_file(File::Spec->catfile($root, 'net', 'tcp'),  $opts{tcp}  // "sl local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n");
    write_text_file(File::Spec->catfile($root, 'net', 'tcp6'), $opts{tcp6} // "sl local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n");

    for my $proc (@{ $opts{procs} || [] }) {
        create_proc_process($root, %{$proc});
    }

    local *CORE::GLOBAL::open = sub(*;$@) {
        if (@_ >= 3 && defined $_[2] && $_[2] =~ m{^/proc/}) {
            my $mapped = $_[2];
            $mapped =~ s{^/proc}{$root};
            return CORE::open($_[0], $_[1], $mapped);
        }
        return CORE::open($_[0], $_[1], @_[2 .. $#_]);
    };

    local *CORE::GLOBAL::opendir = sub(*$) {
        my $path = $_[1];
        if (defined $path && $path =~ m{^/proc(?:/|$)}) {
            $path =~ s{^/proc}{$root};
        }

        if (defined $_[0] && !ref($_[0])) {
            my $pkg = caller();
            my $glob = $_[0] =~ /::/ ? $_[0] : "${pkg}::$_[0]";
            no strict 'refs';
            return CORE::opendir(*{ $glob }, $path);
        }

        return CORE::opendir($_[0], $path);
    };

    local *CORE::GLOBAL::readlink = sub($) {
        my ($path) = @_;
        if (defined $path && $path =~ m{^/proc(?:/|$)}) {
            $path =~ s{^/proc}{$root};
        }
        return CORE::readlink($path);
    };

    return $code->($root);
}

subtest 'hex2ip decodes proc-style IPv4 and IPv6 socket addresses' => sub {
    reload_killssh_module();

    is(
        ConfigServer::KillSSH::hex2ip('0100007F'),
        '127.0.0.1',
        'decodes little-endian procfs IPv4 addresses',
    );

    is(
        ConfigServer::KillSSH::hex2ip('B80D01200000000067452301EFCDAB89'),
        '2001:db8:0:0:123:4567:89ab:cdef',
        'decodes procfs IPv6 addresses',
    );
};

subtest 'find returns immediately when the target IP or ports list is empty' => sub {
    reload_killssh_module();

    my @killed;
    my @logs;

    no warnings qw(redefine once);
    local *CORE::GLOBAL::kill = sub { push @killed, [@_]; return 1 };
    local *ConfigServer::Logger::logfile = sub { push @logs, @_ };

    is(ConfigServer::KillSSH::find('', '22'), undef, 'empty IP returns immediately');
    is(ConfigServer::KillSSH::find('203.0.113.10', ''), undef, 'empty port list returns immediately');
    is_deeply(\@killed, [], 'no processes are killed on early-return paths');
    is_deeply(\@logs,   [], 'no log messages are emitted on early-return paths');
};

subtest 'find kills only sshd processes whose socket inode matches the blocked IP and watched local port' => sub {
    my $tcp = <<'EOF';
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:0016 0A7100CB:9C40 01 00000000:00000000 00:00000000 00000000 0 0 12345 1 0000000000000000 100 0 0 10 0
   1: 0100007F:08AE 146433C6:9C41 01 00000000:00000000 00:00000000 00000000 0 0 22222 1 0000000000000000 100 0 0 10 0
EOF

    my @killed;
    my @logs;

    no warnings qw(redefine once);
    local *CORE::GLOBAL::kill = sub { push @killed, [@_]; return 1 };

    with_mock_proc_root(
        tcp => $tcp,
        procs => [
            {
                pid           => 101,
                exe           => '/usr/sbin/sshd',
                socket_target => 'socket:[12345]',
            },
            {
                pid           => 202,
                exe           => '/usr/bin/nginx',
                socket_target => 'socket:[12345]',
            },
            {
                pid           => 303,
                exe           => '/usr/sbin/sshd',
                socket_target => 'socket:[22222]',
            },
        ],
        code => sub {
            reload_killssh_module();
            local *ConfigServer::Logger::logfile = sub { push @logs, @_ };

            is(
                ConfigServer::KillSSH::find('203.0.113.10', '22,2222'),
                undef,
                'find completes without returning a value',
            );
        },
    );

    is_deeply(\@killed, [[9, 101]], 'only the matching sshd PID is killed');
    is_deeply(
        \@logs,
        ['*PT_SSHDKILL*: Process PID:[101] killed for blocked IP:[203.0.113.10]'],
        'a single kill event is logged for the matching sshd process',
    );
};

subtest 'find skips records whose local address decodes to the special 0.0.0.1 sentinel' => sub {
    my $tcp = <<'EOF';
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 01000000:0016 0A7100CB:9C40 01 00000000:00000000 00:00000000 00000000 0 0 12345 1 0000000000000000 100 0 0 10 0
EOF

    my @killed;
    my @logs;

    no warnings qw(redefine once);
    local *CORE::GLOBAL::kill = sub { push @killed, [@_]; return 1 };

    with_mock_proc_root(
        tcp => $tcp,
        procs => [
            {
                pid           => 404,
                exe           => '/usr/sbin/sshd',
                socket_target => 'socket:[12345]',
            },
        ],
        code => sub {
            reload_killssh_module();
            local *ConfigServer::Logger::logfile = sub { push @logs, @_ };
            ConfigServer::KillSSH::find('203.0.113.10', '22');
        },
    );

    is_deeply(\@killed, [], 'sentinel local-address entries are ignored and do not trigger kills');
    is_deeply(\@logs,   [], 'ignored sentinel entries do not generate log messages');
};

done_testing;

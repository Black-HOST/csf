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
    package Local::GetIPsConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

sub reload_getips_module {
    my ($config) = @_;

    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::GetIPsConfig->new($config);
    };

    delete $INC{'ConfigServer/GetIPs.pm'};
    require ConfigServer::GetIPs;
    return 1;
}

sub build_fake_host_binary {
    my ($dir, %opts) = @_;

    my $script   = File::Spec->catfile($dir, 'fake-host.pl');
    my $args_log = File::Spec->catfile($dir, 'fake-host-args.txt');
    my $output   = $opts{output} // "";

    open(my $fh, '>', $script) or die "Unable to create $script: $!";
    print {$fh} <<EOF;
#!/usr/bin/env perl
use strict;
use warnings;

open(my \$log, '>', q($args_log)) or die "Unable to write $args_log: \$!";
print {\$log} join("\n", \@ARGV), "\n";
close(\$log);

print <<'OUT';
$output
OUT
EOF
    close($fh);

    chmod 0755, $script or die "Unable to chmod $script: $!";
    return ($script, $args_log);
}

sub slurp_file {
    my ($path) = @_;

    open(my $fh, '<', $path) or die "Unable to open $path: $!";
    my @lines = <$fh>;
    close($fh);
    chomp @lines;
    return @lines;
}

subtest 'getips uses the configured host binary and extracts IPv4 and IPv6 results' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        output => <<'OUT',
example.test has address 192.0.2.10
example.test has IPv6 address 2001:db8::20
this line contains no address
OUT
    );

    reload_getips_module({ HOST => $host_bin });
    my @ips = ConfigServer::GetIPs::getips('example.test');

    is_deeply(
        \@ips,
        ['192.0.2.10', '2001:db8::20'],
        'host command output is parsed into IPv4 and IPv6 results in order',
    );

    is_deeply(
        [ slurp_file($args_log) ],
        ['-W', '5', 'example.test'],
        'host binary is invoked with the expected timeout arguments and hostname',
    );
};

subtest 'getips returns an empty list when the host command yields no addresses' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($host_bin, undef) = build_fake_host_binary(
        $dir,
        output => <<'OUT',
example.test has no A record
example.test is unreachable
OUT
    );

    reload_getips_module({ HOST => $host_bin });
    my @ips = ConfigServer::GetIPs::getips('example.test');

    is_deeply(\@ips, [], 'non-address output produces no results');
};

subtest 'getips falls back to local resolver logic when no host binary is available' => sub {
    reload_getips_module({ HOST => '/definitely/missing/host-binary' });
    my @ips = ConfigServer::GetIPs::getips('localhost');

    ok(@ips >= 1, 'resolver fallback returns at least one address for localhost');
    ok(
        scalar(grep { $_ eq '127.0.0.1' || $_ eq '::1' } @ips),
        'resolver fallback includes a loopback address',
    );
};

done_testing;

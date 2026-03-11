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
    package Local::AbuseIPConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

sub reload_abuseip_module {
    my ($config) = @_;

    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::AbuseIPConfig->new($config);
    };

    delete $INC{'ConfigServer/AbuseIP.pm'};
    require ConfigServer::AbuseIP;
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

subtest 'abuseip resolves an IPv4 abuse contact and builds the human message' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $lookup = '10.2.0.192.abuse-contacts.abusix.org';
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        output => qq{$lookup has TXT record "abuse\@example.test"\n},
    );

    reload_abuseip_module({ HOST => $host_bin });
    my ($contact, $message) = ConfigServer::AbuseIP::abuseip('192.0.2.10');

    is($contact, 'abuse@example.test', 'IPv4 lookup returns the TXT contact value');
    like($message, qr/Abuse Contact for 192\.0\.2\.10: \[abuse\@example\.test\]/, 'message includes the IP and abuse contact');
    like($message, qr/abusix\.com/, 'message includes the explanatory abuse-contact text');
    is_deeply(
        [ slurp_file($args_log) ],
        ['-W', '5', '-t', 'TXT', $lookup],
        'host binary receives the expected IPv4 reverse lookup target',
    );
};

subtest 'abuseip resolves an IPv6 abuse contact' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $lookup = '0.2.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.abuse-contacts.abusix.org';
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        output => qq{$lookup has TXT record "ipv6-contact\@example.test"\n},
    );

    reload_abuseip_module({ HOST => $host_bin });
    my ($contact, $message) = ConfigServer::AbuseIP::abuseip('2001:db8::20');

    is($contact, 'ipv6-contact@example.test', 'IPv6 lookup returns the TXT contact value');
    like($message, qr/Abuse Contact for 2001:db8::20: \[ipv6-contact\@example\.test\]/, 'message includes the IPv6 address and contact');
    is_deeply(
        [ slurp_file($args_log) ],
        ['-W', '5', '-t', 'TXT', $lookup],
        'host binary receives the expected IPv6 reverse lookup target',
    );
};

subtest 'abuseip returns nothing for invalid input and skips the host lookup entirely' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        output => qq{should not be used\n},
    );

    reload_abuseip_module({ HOST => $host_bin });
    my $result = ConfigServer::AbuseIP::abuseip('not-an-ip');

    ok(!$result, 'invalid input returns a false value');
    ok(!-e $args_log, 'host binary is not invoked for invalid input');
};

subtest 'abuseip returns nothing when the lookup output contains no quoted contact' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $lookup = '10.2.0.192.abuse-contacts.abusix.org';
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        output => qq{$lookup lookup failed\n},
    );

    reload_abuseip_module({ HOST => $host_bin });
    my $result = ConfigServer::AbuseIP::abuseip('192.0.2.10');

    ok(!$result, 'missing TXT contact produces a false value');
    is_deeply(
        [ slurp_file($args_log) ],
        ['-W', '5', '-t', 'TXT', $lookup],
        'host lookup still runs even when no contact is found',
    );
};

done_testing;

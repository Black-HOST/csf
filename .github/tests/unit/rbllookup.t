#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

sub build_fake_host_binary {
    my ($dir, %opts) = @_;

    my $script      = File::Spec->catfile($dir, 'fake-host.pl');
    my $args_log    = File::Spec->catfile($dir, 'fake-host-args.txt');
    my $a_output    = $opts{a_output} // '';
    my $txt_output  = $opts{txt_output} // '';
    my $timeout_a   = $opts{timeout_a} ? 1 : 0;

    open(my $fh, '>', $script) or die "Unable to create $script: $!";
    print {$fh} <<EOF;
#!/usr/bin/env perl
use strict;
use warnings;

open(my \$log, '>>', q($args_log)) or die "Unable to write $args_log: \$!";
print {\$log} join("\t", \@ARGV), "\n";
close(\$log);

my \$type = '';
for (my \$i = 0; \$i < \@ARGV; \$i++) {
    if (\$ARGV[\$i] eq '-t') {
        \$type = \$ARGV[\$i + 1] // '';
        last;
    }
}

if ($timeout_a && \$type eq 'A') {
    sleep 6;
    exit 0;
}

if (\$type eq 'A') {
    print <<'AOUT';
$a_output
AOUT
}
elsif (\$type eq 'TXT') {
    print <<'TXTOUT';
$txt_output
TXTOUT
}
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

subtest 'rbllookup resolves an IPv4 RBL hit and collects TXT details' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $lookup = '10.2.0.192.zen.example.test';
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        a_output   => qq{$lookup has address 127.0.0.2\n},
        txt_output => qq{$lookup has TXT record "Listed for spam"\n$lookup has TXT record "See https://example.test/rbl"\n},
    );

    TestBootstrap::reload_module_with_config('ConfigServer::RBLLookup',{ HOST => $host_bin });
    my ($hit, $text) = ConfigServer::RBLLookup::rbllookup('192.0.2.10', 'zen.example.test');

    is($hit, '127.0.0.2', 'IPv4 lookup returns the matched RBL address');
    is($text, "Listed for spam\nSee https://example.test/rbl\n", 'TXT details are concatenated with trailing newlines');
    is_deeply(
        [ slurp_file($args_log) ],
        ["-t\tA\t$lookup", "-t\tTXT\t$lookup"],
        'host binary receives the expected IPv4 A and TXT lookup sequence',
    );
};

subtest 'rbllookup resolves an IPv6 RBL hit' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $lookup = '0.2.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.dnsbl.example.test';
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        a_output   => qq{$lookup has address 127.0.0.4\n},
        txt_output => qq{$lookup has TXT record "IPv6 source listed"\n},
    );

    TestBootstrap::reload_module_with_config('ConfigServer::RBLLookup',{ HOST => $host_bin });
    my ($hit, $text) = ConfigServer::RBLLookup::rbllookup('2001:db8::20', 'dnsbl.example.test');

    is($hit, '127.0.0.4', 'IPv6 lookup returns the matched RBL address');
    is($text, "IPv6 source listed\n", 'IPv6 TXT response is returned verbatim');
    is_deeply(
        [ slurp_file($args_log) ],
        ["-t\tA\t$lookup", "-t\tTXT\t$lookup"],
        'host binary receives the expected IPv6 A and TXT lookup sequence',
    );
};

subtest 'rbllookup returns a false result when no RBL hit is found' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $lookup = '10.2.0.192.zen.example.test';
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        a_output => qq{Host $lookup not found: 3(NXDOMAIN)\n},
    );

    TestBootstrap::reload_module_with_config('ConfigServer::RBLLookup',{ HOST => $host_bin });
    my ($hit, $text) = ConfigServer::RBLLookup::rbllookup('192.0.2.10', 'zen.example.test');

    ok(!defined $hit || $hit eq '', 'no RBL hit returns a false hit value');
    ok(!defined $text || $text eq '', 'no RBL hit returns no TXT details');
    is_deeply(
        [ slurp_file($args_log) ],
        ["-t\tA\t$lookup"],
        'host binary is queried only for the A record when there is no hit',
    );
};

subtest 'rbllookup returns a false result for invalid input without invoking host' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($host_bin, $args_log) = build_fake_host_binary($dir);

    TestBootstrap::reload_module_with_config('ConfigServer::RBLLookup',{ HOST => $host_bin });
    my ($hit, $text) = ConfigServer::RBLLookup::rbllookup('not-an-ip', 'zen.example.test');

    ok(!defined $hit || $hit eq '', 'invalid input returns a false hit value');
    ok(!defined $text || $text eq '', 'invalid input returns no TXT details');
    ok(!-e $args_log, 'host binary is not invoked for invalid input');
};

subtest 'rbllookup reports timeout when the A lookup exceeds the alarm window' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $lookup = '10.2.0.192.timeout.example.test';
    my ($host_bin, $args_log) = build_fake_host_binary(
        $dir,
        timeout_a => 1,
    );

    TestBootstrap::reload_module_with_config('ConfigServer::RBLLookup',{ HOST => $host_bin });
    my ($hit, $text) = ConfigServer::RBLLookup::rbllookup('192.0.2.10', 'timeout.example.test');

    is($hit, 'timeout', 'slow host lookups are converted into the timeout sentinel');
    ok(!defined $text || $text eq '', 'timeout path returns no TXT details');
    is_deeply(
        [ slurp_file($args_log) ],
        ["-t\tA\t$lookup"],
        'timeout path stops after the A lookup and does not request TXT records',
    );
};

done_testing;

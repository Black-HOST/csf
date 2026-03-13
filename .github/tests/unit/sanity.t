#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();
require ConfigServer::Sanity;



sub write_test_sanity_file {
    my $dir = tempdir(CLEANUP => 1);
    my $path = File::Spec->catfile($dir, 'sanity.txt');

    open(my $fh, '>', $path) or die "Unable to create test sanity file $path: $!";
    print {$fh} <<'EOF';
AT_INTERVAL=10-3600=60
DROP=DROP|TARPIT|REJECT=DROP
CT_LIMIT=0|10-1000=0
DENY_IP_LIMIT=10-1000=200
EOF
    close($fh);

    return ($dir, $path);
}

sub reset_sanity_state {
    %ConfigServer::Sanity::sanity = ();
    %ConfigServer::Sanity::sanitydefault = ();
    $ConfigServer::Sanity::loaded = 0;
    return;
}



subtest 'sanity data is loaded lazily on first use' => sub {
    my (undef, $path) = write_test_sanity_file();

    reset_sanity_state();
    local $ConfigServer::Sanity::sanityfile = $path;

    TestBootstrap::with_mock_config({ IPSET => 0 }, sub {
        is($ConfigServer::Sanity::loaded, 0, 'sanity rules are not loaded at import time');
        is(scalar keys %ConfigServer::Sanity::sanity, 0, 'sanity hash is empty before first call');
        is(scalar keys %ConfigServer::Sanity::sanitydefault, 0, 'default hash is empty before first call');

        my ($insane, $range, $default) = ConfigServer::Sanity::sanity('AT_INTERVAL', '60');

        is($insane, 0, 'first call validates successfully');
        is($range, '10-3600', 'range comes from the loaded sanity file');
        is($default, '60', 'default comes from the loaded sanity file');
        is($ConfigServer::Sanity::loaded, 1, 'first call loads sanity rules');
    });
};

subtest 'range, discrete, and mixed rules are validated correctly' => sub {
    my (undef, $path) = write_test_sanity_file();

    reset_sanity_state();
    local $ConfigServer::Sanity::sanityfile = $path;

    TestBootstrap::with_mock_config({ IPSET => 0 }, sub {
        my ($insane, $range, $default);

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('AT_INTERVAL', '10');
        is($insane, 0, 'range rule accepts the lower boundary');
        is($range, '10-3600', 'range rule is reported as stored');
        is($default, '60', 'range rule default is returned');

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('AT_INTERVAL', '3601');
        is($insane, 1, 'range rule rejects values above the upper boundary');

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('DROP', 'TARPIT');
        is($insane, 0, 'discrete rule accepts an allowed token');
        is($range, 'DROP or TARPIT or REJECT', 'discrete rule is formatted for display');
        is($default, 'DROP', 'discrete rule default is returned');

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('DROP', 'QUEUE');
        is($insane, 1, 'discrete rule rejects an unsupported token');

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('CT_LIMIT', '0');
        is($insane, 0, 'mixed rule accepts its exact zero value');
        is($range, '0 or 10-1000', 'mixed rule keeps both exact and ranged choices');
        is($default, '0', 'mixed rule default is returned');

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('CT_LIMIT', '500');
        is($insane, 0, 'mixed rule accepts values in its numeric range');

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('CT_LIMIT', '5');
        is($insane, 1, 'mixed rule rejects values outside every allowed branch');
    });
};

subtest 'undef values return early without loading sanity rules' => sub {
    my (undef, $path) = write_test_sanity_file();

    reset_sanity_state();
    local $ConfigServer::Sanity::sanityfile = $path;

    TestBootstrap::with_mock_config({ IPSET => 0 }, sub {
        my @result = ConfigServer::Sanity::sanity('AT_INTERVAL', undef);

        is_deeply(\@result, [0], 'undef values return the early 0 result');
        is($ConfigServer::Sanity::loaded, 0, 'undef values do not trigger lazy loading');
        is(scalar keys %ConfigServer::Sanity::sanity, 0, 'undef values leave the sanity cache empty');
    });
};

subtest 'display formatting does not mutate cached rules' => sub {
    my (undef, $path) = write_test_sanity_file();

    reset_sanity_state();
    local $ConfigServer::Sanity::sanityfile = $path;

    TestBootstrap::with_mock_config({ IPSET => 0 }, sub {
        my ($insane, $range, $default) = ConfigServer::Sanity::sanity('DROP', 'TARPIT');
        is($insane, 0, 'first lookup validates an allowed token');
        is($range, 'DROP or TARPIT or REJECT', 'display output is formatted for humans');
        is($default, 'DROP', 'default value is preserved');
        is($ConfigServer::Sanity::sanity{DROP}, 'DROP|TARPIT|REJECT', 'cached rule keeps raw separators after formatting');

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('DROP', 'REJECT');
        is($insane, 0, 'later lookups still validate against the cached rule');
        is($range, 'DROP or TARPIT or REJECT', 'later lookups still report the formatted display value');
        is($ConfigServer::Sanity::sanity{DROP}, 'DROP|TARPIT|REJECT', 'cached rule remains unchanged across calls');
    });
};

subtest 'cached sanity data is reused after first load' => sub {
    my (undef, $first_path) = write_test_sanity_file();
    my $second_dir = tempdir(CLEANUP => 1);
    my $second_path = File::Spec->catfile($second_dir, 'sanity.txt');

    open(my $fh, '>', $second_path) or die "Unable to create second sanity file $second_path: $!";
    print {$fh} <<'EOF';
AT_INTERVAL=100-200=150
DROP=DROP|REJECT=DROP
CT_LIMIT=1-5=2
DENY_IP_LIMIT=500-600=550
EOF
    close($fh);

    reset_sanity_state();

    TestBootstrap::with_mock_config({ IPSET => 0 }, sub {
        local $ConfigServer::Sanity::sanityfile = $first_path;
        my ($insane, $range, $default) = ConfigServer::Sanity::sanity('AT_INTERVAL', '60');

        is($insane, 0, 'first file is used for initial load');
        is($range, '10-3600', 'initial range is from the first file');
        is($default, '60', 'initial default is from the first file');

        local $ConfigServer::Sanity::sanityfile = $second_path;
        ($insane, $range, $default) = ConfigServer::Sanity::sanity('AT_INTERVAL', '60');

        is($insane, 0, 'cached data remains active after file path changes');
        is($range, '10-3600', 'cached range is unchanged after first load');
        is($default, '60', 'cached default is unchanged after first load');
    });
};

subtest 'whitespace is ignored and unknown keys stay non-fatal' => sub {
    my (undef, $path) = write_test_sanity_file();

    reset_sanity_state();
    local $ConfigServer::Sanity::sanityfile = $path;

    TestBootstrap::with_mock_config({ IPSET => 0 }, sub {
        my ($insane, $range, $default) = ConfigServer::Sanity::sanity(' DROP ', ' TARPIT ');
        is($insane, 0, 'leading and trailing whitespace is ignored');
        is($range, 'DROP or TARPIT or REJECT', 'whitespace does not change the displayed rule');
        is($default, 'DROP', 'whitespace does not change the default');

        ($insane, $range, $default) = ConfigServer::Sanity::sanity('UNKNOWN_ITEM', '999');
        is($insane, 0, 'unknown keys are treated as non-insane');
        is($range, undef, 'unknown keys have no reported range');
        is($default, undef, 'unknown keys have no reported default');
    });
};

subtest 'DENY_IP_LIMIT is skipped when IPSET is enabled' => sub {
    my (undef, $path) = write_test_sanity_file();

    reset_sanity_state();
    local $ConfigServer::Sanity::sanityfile = $path;

    TestBootstrap::with_mock_config({ IPSET => 1 }, sub {
        my ($insane, $range, $default) = ConfigServer::Sanity::sanity('DENY_IP_LIMIT', '5');

        is($insane, 0, 'DENY_IP_LIMIT is not validated when IPSET is enabled');
        is($range, undef, 'no range is reported when DENY_IP_LIMIT is skipped');
        is($default, undef, 'no default is reported when DENY_IP_LIMIT is skipped');
    });
};

subtest 'missing sanity file fails with a clear error' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $path = File::Spec->catfile($dir, 'missing-sanity.txt');

    reset_sanity_state();
    local $ConfigServer::Sanity::sanityfile = $path;

    TestBootstrap::with_mock_config({ IPSET => 0 }, sub {
        my $ok = eval { ConfigServer::Sanity::sanity('AT_INTERVAL', '60'); 1 };
        ok(!$ok, 'sanity() dies when the sanity file is missing');
        like($@, qr/^Cannot open \Q$path\E:/, 'error message includes the missing file path');
    });
};

done_testing();

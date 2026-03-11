#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();
use ConfigServer::Slurp qw(slurp);

sub write_temp_file {
    my ($content, %opts) = @_;
    my $dir  = tempdir(CLEANUP => 1);
    my $name = $opts{name} || 'testfile.txt';
    my $path = File::Spec->catfile($dir, $name);

    open(my $fh, '>:raw', $path) or die "Unable to create $path: $!";
    print {$fh} $content;
    close($fh);

    return $path;
}

subtest 'reads lines from an existing file' => sub {
    my $path = write_temp_file("alpha\nbeta\ngamma\n");
    my @lines = slurp($path);

    is_deeply(\@lines, [qw(alpha beta gamma)], 'returns each line as a list element');
};

subtest 'preserves blank lines when splitting' => sub {
    my $path = write_temp_file("first\n\nsecond\n\n\nthird\n");
    my @lines = slurp($path);

    is_deeply(
        \@lines,
        ['first', '', 'second', '', '', 'third'],
        'empty lines between content are kept as empty strings',
    );
};

subtest 'handles file with no trailing newline' => sub {
    my $path = write_temp_file("one\ntwo");
    my @lines = slurp($path);

    is_deeply(\@lines, [qw(one two)], 'last line without newline is still returned');
};

subtest 'splits CRLF line endings' => sub {
    my $path = write_temp_file("aaa\r\nbbb\r\nccc\r\n");
    my @lines = slurp($path);

    is_deeply(\@lines, [qw(aaa bbb ccc)], 'CRLF pairs are treated as single line breaks');
};

subtest 'splits bare CR line endings' => sub {
    my $path = write_temp_file("aaa\rbbb\rccc\r");
    my @lines = slurp($path);

    is_deeply(\@lines, [qw(aaa bbb ccc)], 'bare carriage returns split lines');
};

subtest 'splits mixed newline styles in one file' => sub {
    my $path = write_temp_file("unix\nwindows\r\nclassic\rend");
    my @lines = slurp($path);

    is_deeply(
        \@lines,
        [qw(unix windows classic end)],
        'LF, CRLF, and CR can coexist in one file',
    );
};

subtest 'splits on vertical tab and form feed' => sub {
    my $path = write_temp_file("aa\x0Bbb\x0Ccc");
    my @lines = slurp($path);

    is_deeply(\@lines, [qw(aa bb cc)], 'VT and FF are recognised as line terminators');
};

subtest 'returns a single element for a file with no newlines' => sub {
    my $path = write_temp_file('hello world');
    my @lines = slurp($path);

    is_deeply(\@lines, ['hello world'], 'content without newlines is one element');
};

subtest 'returns an empty list for an empty file' => sub {
    my $path = write_temp_file('');
    my @lines = slurp($path);

    is(scalar @lines, 0, 'empty file produces zero elements');
};

subtest 'warns and returns empty list for a missing file' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    my $missing = File::Spec->catfile(tempdir(CLEANUP => 1), 'no-such-file.txt');
    my @lines = slurp($missing);

    is(scalar @lines, 0, 'missing file returns an empty list');
    is(scalar @warnings, 1, 'exactly one warning is emitted');
    like($warnings[0], qr/File does not exist/, 'warning mentions the missing file');
};

subtest 'slurpreg accessor returns the line-break regex' => sub {
    my $reg = ConfigServer::Slurp::slurpreg();

    isa_ok($reg, 'Regexp', 'slurpreg() returns a compiled regex');
    ok("\n"       =~ $reg, 'regex matches LF');
    ok("\r\n"     =~ $reg, 'regex matches CRLF');
    ok("\r"       =~ $reg, 'regex matches bare CR');
    ok("\x0B"     =~ $reg, 'regex matches vertical tab');
    ok("\x0C"     =~ $reg, 'regex matches form feed');
    ok("abc"     !~ $reg, 'regex does not match plain text');
};

subtest 'cleanreg accessor returns the whitespace-cleaning regex' => sub {
    my $reg = ConfigServer::Slurp::cleanreg();

    isa_ok($reg, 'Regexp', 'cleanreg() returns a compiled regex');
    ok("\r"       =~ $reg, 'cleanreg matches carriage return');
    ok("\n"       =~ $reg, 'cleanreg matches newline');
    ok("  hello"  =~ $reg, 'cleanreg matches leading whitespace');
    ok("hello  "  =~ $reg, 'cleanreg matches trailing whitespace');
};

subtest 'slurp is importable by name' => sub {
    ok(defined &slurp, 'slurp is available in the calling namespace after import');
};

subtest 'preserves whitespace within lines' => sub {
    my $path = write_temp_file("  leading\ntrailing  \n  both  \n");
    my @lines = slurp($path);

    is_deeply(
        \@lines,
        ['  leading', 'trailing  ', '  both  '],
        'internal and surrounding whitespace within lines is untouched',
    );
};

done_testing;

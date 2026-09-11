#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use Test::More;
use lib "$Bin/../lib";
use TestBootstrap qw(repo_root with_mock_config);

with_mock_config({}, sub { require ConfigServer::Messenger; });

sub read_template {
    my ($server, $type, @lines) = @_;
    my $requested;
    no warnings qw(redefine once);
    local *ConfigServer::Messenger::slurp = sub {
        ($requested) = @_;
        return @lines;
    };
    my @result = ConfigServer::Messenger::_messenger_template($server, $type);
    is($requested, "/usr/local/csf/tpl/$server.$type.txt", 'reads the installed template');
    return @result;
}

subtest 'legacy and customized Apache templates omit system-binary CGI mappings' => sub {
    my @unsafe = (
        '    ScriptAlias /local-bin /usr/bin',
        "\tSCRIPTALIAS\t/local-bin/\t/usr/bin/",
        'ScriptAlias "/local-bin" "/usr/bin"',
        "ScriptAlias '/local-bin/' '/usr/bin/'",
        'ScriptAlias /another-prefix /usr/bin',
        "ScriptAlias /local-bin \\\n/usr/bin",
        "ScriptAlias \\\n/local-bin \\\n/usr/bin",
    );
    my @preserved = (
        '# Custom administrator setting',
        'Header set X-Messenger custom',
        '# ScriptAlias /local-bin /usr/bin',
        'ScriptAlias /php-handler /usr/bin/php-cgi',
        'ScriptAlias /cgi-bin /srv/messenger/cgi-bin/',
        '<FilesMatch "\\.(inc|php)$">',
        '    [PHPHANDLER]',
        '</FilesMatch>',
    );
    for my $type (qw(main http https)) {
        for my $unsafe (@unsafe) {
            my @input = (@preserved, split(/\n/, $unsafe), 'KeepAlive Off');
            is_deeply(
                [read_template('apache', $type, @input)],
                [@preserved, 'KeepAlive Off'],
                "$type removes only the unsafe directive: $unsafe",
            );
        }
    }
};

subtest 'fresh and upgraded templates produce the same safe HTTPS configuration' => sub {
    my $path = File::Spec->catfile(repo_root(), 'tpl', 'apache.https.txt');
    open(my $fh, '<', $path) or die "Cannot read $path: $!";
    my @fresh = <$fh>;
    close($fh);
    chomp @fresh;
    unlike(join("\n", @fresh), qr/^\s*ScriptAlias\s/m, 'shipped HTTPS template has no CGI alias');

    my @legacy = @fresh;
    my ($at) = grep { $legacy[$_] =~ /<FilesMatch/ } 0 .. $#legacy;
    ok(defined $at, 'legacy insertion point exists');
    splice(@legacy, $at, 0, "\tScriptAlias /local-bin /usr/bin");

    my @safe = read_template('apache', 'https', @legacy);
    is_deeply(\@safe, \@fresh, 'preserved v15.03 template renders exactly like the patched template');
    is_deeply([read_template('apache', 'https', @safe)], \@safe, 'regeneration is idempotent');
    like(join("\n", @legacy), qr/ScriptAlias \/local-bin \/usr\/bin/, 'administrator template is not rewritten');
};

subtest 'unrelated content and native LiteSpeed templates remain unchanged' => sub {
    my @lines = ('# comment', '', 'ScriptAlias /local-bin /usr/bin');
    is_deeply([read_template('litespeed', 'https', @lines)], \@lines, 'no Apache filtering for native LiteSpeed');
    my @continued = ("Header set X-Messenger \\", 'custom', "# trailing \\");
    is_deeply([read_template('apache', 'https', @continued)], \@continued, 'preserves unrelated continuations');
};

done_testing;

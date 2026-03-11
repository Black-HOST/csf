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
    package Local::SendmailConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

sub build_capture_sendmail {
    my ($dir) = @_;
    my $script = File::Spec->catfile($dir, 'capture-sendmail.pl');

    open(my $fh, '>', $script) or die "Unable to create $script: $!";
    print {$fh} <<'EOF';
#!/usr/bin/env perl
use strict;
use warnings;

my $args_path = $ENV{CAPTURE_ARGS} or die "CAPTURE_ARGS not set\n";
my $body_path = $ENV{CAPTURE_BODY} or die "CAPTURE_BODY not set\n";

open(my $args_fh, '>', $args_path) or die "Unable to write $args_path: $!";
print {$args_fh} join("\n", @ARGV), "\n";
close($args_fh);

local $/;
my $body = <STDIN>;

open(my $body_fh, '>', $body_path) or die "Unable to write $body_path: $!";
print {$body_fh} $body;
close($body_fh);
EOF
    close($fh);

    chmod 0755, $script or die "Unable to chmod $script: $!";
    return $script;
}

sub load_sendmail_module {
    my ($config) = @_;

    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return Local::SendmailConfig->new($config);
    };

    require ConfigServer::Sendmail;
    return 1;
}

sub capture_relay_output {
    my ($dir, @relay_args) = @_;

    my $args_path = File::Spec->catfile($dir, 'captured-args.txt');
    my $body_path = File::Spec->catfile($dir, 'captured-body.txt');

    local $ENV{CAPTURE_ARGS} = $args_path;
    local $ENV{CAPTURE_BODY} = $body_path;

    ConfigServer::Sendmail::relay(@relay_args);

    open(my $args_fh, '<', $args_path) or die "Unable to read $args_path: $!";
    my @args = <$args_fh>;
    close($args_fh);
    chomp @args;

    open(my $body_fh, '<', $body_path) or die "Unable to read $body_path: $!";
    local $/;
    my $body = <$body_fh>;
    close($body_fh);

    return (\@args, $body);
}

my $tempdir = tempdir(CLEANUP => 1);
my $sendmail_script = build_capture_sendmail($tempdir);

load_sendmail_module({
    LF_ALERT_SMTP => 0,
    LF_ALERT_TO   => 'default-to@example.com',
    LF_ALERT_FROM => 'default-from@example.com',
    SENDMAIL      => $sendmail_script,
    DEBUG         => 0,
});

subtest 'wraptext leaves short lines intact apart from the final newline' => sub {
    my $wrapped = ConfigServer::Sendmail::wraptext('short line', 40);

    is($wrapped, "short line\n", 'short text is preserved as one line with a trailing newline');
};

subtest 'wraptext wraps long spaced lines at whitespace boundaries' => sub {
    my $wrapped = ConfigServer::Sendmail::wraptext('alpha beta gamma delta', 10);

    is(
        $wrapped,
        "alpha \nbeta \ngamma \ndelta\n",
        'space-delimited content is wrapped at the nearest whitespace break',
    );
};

subtest 'wraptext falls back to fixed-width chunks when no spaces exist' => sub {
    my $wrapped = ConfigServer::Sendmail::wraptext('averyverylongwordwithoutspaces', 10);

    is(
        $wrapped,
        "averyveryl\nongwordwit\nhoutspaces\n",
        'unbroken text is split into width-limited chunks',
    );
};

subtest 'relay uses configured fallback addresses when explicit arguments are omitted' => sub {
    my ($args, $body) = capture_relay_output(
        $tempdir,
        '',
        '',
        'To: original-to@example.com',
        'From: original-from@example.com',
        'Subject: Default route',
        '',
        'Generated at [time] on [hostname]',
    );

    is_deeply($args, ['-f', 'default-from@example.com', '-t'], 'sendmail is invoked with the configured fallback sender');
    like($body, qr/^To: default-to\@example\.com$/m, 'To header is replaced with the configured fallback recipient');
    like($body, qr/^From: default-from\@example\.com$/m, 'From header is replaced with the configured fallback sender');
    like($body, qr/^Subject: Default route$/m, 'other headers are preserved');
    unlike($body, qr/\[time\]/, 'time placeholder is expanded');
    unlike($body, qr/\[hostname\]/, 'hostname placeholder is expanded');
};

subtest 'relay lets explicit arguments override configured defaults' => sub {
    my ($args, $body) = capture_relay_output(
        $tempdir,
        'custom-to@example.com',
        'custom-from@example.com',
        'To: original-to@example.com',
        'From: original-from@example.com',
        'Subject: Explicit route',
        '',
        'Body line',
    );

    is_deeply($args, ['-f', 'custom-from@example.com', '-t'], 'explicit sender is passed to the sendmail command');
    like($body, qr/^To: custom-to\@example\.com$/m, 'explicit recipient replaces the header value');
    like($body, qr/^From: custom-from\@example\.com$/m, 'explicit sender replaces the header value');
    like($body, qr/^Subject: Explicit route$/m, 'subject remains untouched when overriding addresses');
    like($body, qr/^Body line$/m, 'message body is written to sendmail stdin');
};

done_testing;

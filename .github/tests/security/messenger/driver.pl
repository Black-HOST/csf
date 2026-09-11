#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../../lib";
use TestBootstrap qw(with_mock_config);

# Invokes the real Messenger generator with test settings. The sibling run.sh
# owns fixtures and assertions; use it only in the disposable Docker container.
die "Run through the Docker integration test\n" unless -f '/.dockerenv' && $> == 0;

my $mode = shift || '';
with_mock_config({
    MESSENGER_USER         => 'csf-test',
    MESSENGERV3GROUP       => 'csf-test',
    MESSENGERV3PERMS       => '755',
    MESSENGERV3WEBSERVER   => 'apache',
    MESSENGERV3PHPHANDLER  => 'SetHandler application/x-httpd-php',
    MESSENGERV3LOCATION    => '/etc/apache2/csf-messenger',
    MESSENGERV3HTTPS_CONF  => '/tmp/csf-messenger-test/sites.conf',
    MESSENGERV3TEST        => '/usr/sbin/apache2ctl -t',
    MESSENGERV3RESTART     => '/usr/sbin/apache2ctl -k graceful',
    MESSENGER_HTML         => 8080,
    MESSENGER_HTML_IN      => '80',
    MESSENGER_HTTPS        => 8443,
    MESSENGER_HTTPS_IN     => '443',
    IPV6                  => 0,
    DEBUG                 => 0,
    SYSLOG                => 0,
    RECAPTCHA_SITEKEY     => '',
    RECAPTCHA_SECRET      => '',
}, sub {
    require ConfigServer::Messenger;
    ConfigServer::Messenger->init(3);
    if ($mode eq 'legacy-control') {
        # Positive control: reproduce the old unfiltered template reader with
        # a harmless CGI fixture, never a command-execution payload.
        no warnings qw(redefine once);
        local *ConfigServer::Messenger::_messenger_template = sub {
            my ($server, $type) = @_;
            return ConfigServer::Slurp::slurp("/usr/local/csf/tpl/$server.$type.txt");
        };
        ConfigServer::Messenger::messengerv3();
    } else {
        ConfigServer::Messenger::messengerv3();
    }
});

#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();

{
    package Local::FakeMessengerClient;

    sub new {
        my ($class, $payload) = @_;
        return bless { buf => [ split //, $payload ] }, $class;
    }

    sub read {
        my $self = shift;
        # Caller passes: $client->read($char, 1)
        # $_[0] aliases the caller's $char, $_[1] aliases the length argument.
        if (@{ $self->{buf} }) {
            $_[0] = shift @{ $self->{buf} };
        } else {
            $_[0] = "\n";
        }
        return 1;
    }
}

sub load_messenger {
    my (%config) = @_;
    $config{IPV6}         //= 0;
    $config{MESSENGER6}   //= 0;
    $config{RECAPTCHA_NAT} //= '';
    $config{DEBUG}        //= 0;
    TestBootstrap::reload_module_with_config('ConfigServer::Messenger', \%config);
    return;
}

# Override ConfigServer::GetEthDev so init(1) can run without probing real
# network interfaces. Callers wrap a `local` block around their init() call.
sub _stub_getethdev {
    no warnings qw(redefine once);
    *ConfigServer::GetEthDev::new  = sub { return bless {}, 'ConfigServer::GetEthDev' };
    *ConfigServer::GetEthDev::ipv4 = sub { return () };
    *ConfigServer::GetEthDev::ipv6 = sub { return () };
    return;
}

subtest 'module exposes the documented public surface and a numeric VERSION' => sub {
    load_messenger();

    ok(ConfigServer::Messenger->can('init'),        'init() is part of the public API');
    ok(ConfigServer::Messenger->can('start'),       'start() is part of the public API');
    ok(ConfigServer::Messenger->can('messengerv2'), 'messengerv2() is callable as a class/package method');
    ok(defined $ConfigServer::Messenger::VERSION,   '$VERSION is defined at package level');
    cmp_ok($ConfigServer::Messenger::VERSION, '>=', 3.00,
        '$VERSION is at or above the documented 3.x baseline');
};

subtest 'init returns a blessed instance for version 2 without touching ssl directories' => sub {
    load_messenger();

    my $obj = ConfigServer::Messenger->init(2);

    isa_ok($obj, 'ConfigServer::Messenger', 'init returns a Messenger object for the v2 (TEXT) flavor');
    can_ok($obj, 'start');
};

subtest 'init(1) returns a blessed instance once GetEthDev is stubbed out' => sub {
    load_messenger();

    no warnings qw(redefine once);
    local *ConfigServer::GetEthDev::new  = sub { return bless {}, 'ConfigServer::GetEthDev' };
    local *ConfigServer::GetEthDev::ipv4 = sub { return () };
    local *ConfigServer::GetEthDev::ipv6 = sub { return () };

    my $obj = ConfigServer::Messenger->init(1);

    isa_ok($obj, 'ConfigServer::Messenger', 'init(1) returns a Messenger object for the v1 (HTTP/HTTPS) flavor');
};

subtest 'init(3) returns a blessed instance without dying on mkdir failures' => sub {
    load_messenger();

    my $obj = eval { ConfigServer::Messenger->init(3) };
    is($@, '', 'init(3) does not throw when /var/lib/csf/ssl is not writable');
    isa_ok($obj, 'ConfigServer::Messenger', 'init(3) returns a Messenger object for the v3 (HTTPS-CT) flavor');
};

subtest 'init(1) tolerates a populated RECAPTCHA_NAT list with spaces and multiple entries' => sub {
    load_messenger(RECAPTCHA_NAT => '192.168.1.1, 10.0.0.1, 172.16.0.5');

    no warnings qw(redefine once);
    local *ConfigServer::GetEthDev::new  = sub { return bless {}, 'ConfigServer::GetEthDev' };
    local *ConfigServer::GetEthDev::ipv4 = sub { return () };
    local *ConfigServer::GetEthDev::ipv6 = sub { return () };

    my $obj = eval { ConfigServer::Messenger->init(1) };
    is($@, '', 'init(1) does not die when RECAPTCHA_NAT carries a comma-separated IP list with whitespace');
    isa_ok($obj, 'ConfigServer::Messenger', 'init(1) still returns a Messenger object with RECAPTCHA_NAT populated');
};

subtest 'init(1) tolerates the MESSENGER6 + IPV6 combination' => sub {
    load_messenger(MESSENGER6 => 1, IPV6 => 1);

    no warnings qw(redefine once);
    local *ConfigServer::GetEthDev::new  = sub { return bless {}, 'ConfigServer::GetEthDev' };
    local *ConfigServer::GetEthDev::ipv4 = sub { return () };
    local *ConfigServer::GetEthDev::ipv6 = sub { return () };

    my $obj = eval { ConfigServer::Messenger->init(1) };
    is($@, '', 'init(1) does not die when MESSENGER6 and IPV6 are both enabled');
    isa_ok($obj, 'ConfigServer::Messenger', 'init(1) returns a Messenger object on an IPv6-enabled config');
};

subtest '_read_request_line returns an LF-terminated request line without the trailing newline' => sub {
    load_messenger();

    my $client = Local::FakeMessengerClient->new("GET / HTTP/1.0\n");
    my $line = ConfigServer::Messenger::_read_request_line($client);

    is($line, 'GET / HTTP/1.0', 'trailing LF is chomped off the returned line');
};

subtest '_read_request_line strips a trailing CR when the request uses CRLF' => sub {
    load_messenger();

    my $client = Local::FakeMessengerClient->new("GET /resource HTTP/1.1\r\n");
    my $line = ConfigServer::Messenger::_read_request_line($client);

    is($line, 'GET /resource HTTP/1.1', 'CRLF terminator is reduced to a bare request line');
};

subtest '_read_request_line stops reading once MAX_LINE_LENGTH bytes have been consumed' => sub {
    load_messenger();

    my $payload = ('A' x 5000) . "\n";
    my $client = Local::FakeMessengerClient->new($payload);
    my $line = ConfigServer::Messenger::_read_request_line($client);

    ok(length($line) > ConfigServer::Messenger::MAX_LINE_LENGTH(),
        'overlong request lines exit the read loop without consuming the entire payload');
    ok(length($line) <= ConfigServer::Messenger::MAX_LINE_LENGTH() + 1,
        'read stops within one byte of the documented MAX_LINE_LENGTH cap');
    unlike($line, qr/\n/, 'returned line never contains an embedded newline');
};

subtest '_read_request_line accepts a line of exactly MAX_LINE_LENGTH bytes terminated by LF' => sub {
    load_messenger();

    my $max     = ConfigServer::Messenger::MAX_LINE_LENGTH();
    my $payload = ('C' x $max) . "\n";
    my $client  = Local::FakeMessengerClient->new($payload);

    my $line = ConfigServer::Messenger::_read_request_line($client);

    is(length($line), $max, 'a line exactly at MAX_LINE_LENGTH is read in full and the LF chomped');
    is($line, 'C' x $max,    'the returned line is exactly the bytes that were provided');
};

done_testing;

#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

BEGIN {
    # Stub LWP::UserAgent so CloudFlare.pm can be loaded on hosts (incl. CI
    # runners) without libwww-perl installed. Each subtest still injects its
    # own behaviour via `local *LWP::UserAgent::method = sub { ... }`.
    $INC{'LWP/UserAgent.pm'} = __FILE__;
    no strict 'refs';
    *{'LWP::UserAgent::new'}    = sub { my $c = shift; bless {}, $c };
    *{'LWP::UserAgent::post'}   = sub { die 'LWP::UserAgent::post must be stubbed by the active subtest' };
    *{'LWP::UserAgent::delete'} = sub { die 'LWP::UserAgent::delete must be stubbed by the active subtest' };
}

use TestBootstrap ();

{
    package Local::FakeCFResponse;

    sub new { my ($class, %args) = @_; return bless \%args, $class }
    sub is_success  { return $_[0]->{is_success}  }
    sub content     { return $_[0]->{content}     }
    sub status_line { return $_[0]->{status_line} // 'fake-status' }
}

sub load_cloudflare {
    my (%config) = @_;
    $config{DEBUG}    //= 0;
    $config{URLGET}   //= 1;
    $config{CF_BLOCK} //= 'block';
    $config{CF_CPANEL} //= 0;
    TestBootstrap::reload_module_with_config('ConfigServer::CloudFlare', \%config);
    return;
}

subtest 'checktarget classifies countries, CIDR ranges, and bare IPs' => sub {
    load_cloudflare();

    is(ConfigServer::CloudFlare::checktarget('US'),          'country',  'two-letter token is treated as a country code');
    is(ConfigServer::CloudFlare::checktarget('192.0.2.0/24'), 'ip_range', '/24 CIDR is treated as an ip_range target');
    is(ConfigServer::CloudFlare::checktarget('192.0.0.0/16'), 'ip_range', '/16 CIDR is treated as an ip_range target');
    is(ConfigServer::CloudFlare::checktarget('192.0.2.10'),  'ip',       'plain IPv4 falls through to the ip target');
    is(ConfigServer::CloudFlare::checktarget('2001:db8::1'), 'ip',       'plain IPv6 falls through to the ip target');
};

subtest 'getscope parses DOMAIN, DISABLE, and ANY directives from csf.cloudflare' => sub {
    load_cloudflare(CF_CPANEL => 0);

    no warnings qw(redefine once);
    local *ConfigServer::CloudFlare::slurp = sub {
        return (
            '# example csf.cloudflare contents',
            'DOMAIN:example.com:USER:alice:ACCOUNT:alice@example.com:APIKEY:key-alice',
            'DOMAIN:any:USER:bob:ACCOUNT:bob@example.com:APIKEY:key-bob',
            'DISABLE:carol',
            'ANY:bob',
            '',
        );
    };

    my $scope = ConfigServer::CloudFlare::getscope();

    is($scope->{domain}{'example.com'}{user},    'alice',              'DOMAIN line records the owning user');
    is($scope->{domain}{'example.com'}{account}, 'alice@example.com',  'DOMAIN line records the cloudflare account');
    is($scope->{domain}{'example.com'}{apikey},  'key-alice',          'DOMAIN line records the cloudflare API key');
    is($scope->{user}{alice}{domain}{'example.com'}, 'example.com',    'user->domain mapping is populated from DOMAIN lines');
    is($scope->{user}{bob}{any}, 1, 'a DOMAIN line with the special "any" name flags the user as catch-all');
};

subtest 'block POSTs JSON-encoded rule body and returns the new rule id on success' => sub {
    load_cloudflare(CF_BLOCK => 'block');

    my %posted;
    no warnings qw(redefine once);
    local *LWP::UserAgent::new = sub { return bless {}, shift };
    local *LWP::UserAgent::post = sub {
        my ($self, $url, %rest) = @_;
        $posted{url}     = $url;
        $posted{content} = $rest{Content};
        return Local::FakeCFResponse->new(
            is_success => 1,
            content    => '{"result":{"id":"rule-block-1"}}',
        );
    };

    my ($id, $status) = ConfigServer::CloudFlare::block('192.0.2.10');

    is($id, 'rule-block-1', 'success path returns the new rule id from the parsed JSON response');
    is($status, 'CloudFlare: block ip 192.0.2.10', 'success path returns a human-readable status string');
    is($posted{url}, 'https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules', 'POST hits the access_rules endpoint');
    like($posted{content}, qr/"target"\s*:\s*"ip"/,            'JSON body declares the ip target for a bare IPv4');
    like($posted{content}, qr/"value"\s*:\s*"192\.0\.2\.10"/,  'JSON body carries the requested IP value');
    like($posted{content}, qr/"mode"\s*:\s*"block"/,           'JSON body propagates the configured CF_BLOCK mode');
};

subtest 'block reports the status line when the upstream request fails' => sub {
    load_cloudflare(CF_BLOCK => 'block');

    no warnings qw(redefine once);
    local *LWP::UserAgent::new  = sub { return bless {}, shift };
    local *LWP::UserAgent::post = sub {
        return Local::FakeCFResponse->new(
            is_success  => 0,
            content     => '{"errors":[{"code":1000}]}',
            status_line => '500 Internal Server Error',
        );
    };

    my @result = ConfigServer::CloudFlare::block('192.0.2.10');

    is(scalar @result, 1, 'failure path returns a single error string instead of (id, status)');
    is($result[0], 'CloudFlare: [192.0.2.10] block failed: 500 Internal Server Error', 'error string includes the IP and the upstream status line');
};

subtest 'whitelist tags the rule with the whitelist mode and notes' => sub {
    load_cloudflare();

    my $body;
    no warnings qw(redefine once);
    local *LWP::UserAgent::new  = sub { return bless {}, shift };
    local *LWP::UserAgent::post = sub {
        my ($self, $url, %rest) = @_;
        $body = $rest{Content};
        return Local::FakeCFResponse->new(
            is_success => 1,
            content    => '{"result":{"id":"rule-allow-1"}}',
        );
    };

    my ($id, $status) = ConfigServer::CloudFlare::whitelist('US');

    is($id, 'rule-allow-1',                              'whitelist returns the new rule id on success');
    is($status, 'CloudFlare: whitelisted country US',    'whitelist status string includes the target classification');
    like($body, qr/"mode"\s*:\s*"whitelist"/,            'whitelist body sets mode=whitelist regardless of CF_BLOCK');
    like($body, qr/"target"\s*:\s*"country"/,            'whitelist body classifies a two-letter token as country');
};

subtest 'remove returns an id-not-found error when no id is supplied and lookup is empty' => sub {
    load_cloudflare();

    no warnings qw(redefine once);
    local *ConfigServer::CloudFlare::getid = sub { return '' };

    my $status = ConfigServer::CloudFlare::remove('192.0.2.10', 'block', '');

    is($status, 'CloudFlare: [192.0.2.10] remove failed: id not found', 'missing rule id surfaces a clear error from remove()');
};

subtest 'remove issues DELETE and reports success when an explicit id is given' => sub {
    load_cloudflare();

    my %deleted;
    no warnings qw(redefine once);
    local *LWP::UserAgent::new    = sub { return bless {}, shift };
    local *LWP::UserAgent::delete = sub {
        my ($self, $url, %rest) = @_;
        $deleted{url} = $url;
        return Local::FakeCFResponse->new(is_success => 1, content => '{}');
    };

    my $status = ConfigServer::CloudFlare::remove('192.0.2.10', 'block', 'rule-123');

    is($status, 'CloudFlare: removed ip 192.0.2.10', 'remove returns a human-readable success status');
    is($deleted{url}, 'https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules/rule-123', 'DELETE targets the rule id endpoint');
};

done_testing;

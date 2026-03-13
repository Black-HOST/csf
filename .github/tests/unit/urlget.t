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
    package Local::URLGetLWPResponse;

    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }

    sub is_success {
        my ($self) = @_;
        return $self->{is_success};
    }

    sub content {
        my ($self) = @_;
        return $self->{content};
    }

    sub message {
        my ($self) = @_;
        return $self->{message};
    }

    sub content_length {
        my ($self) = @_;
        return $self->{content_length};
    }
}



subtest 'urlget warns and returns nothing when no URL is provided' => sub {
    TestBootstrap::reload_module_with_config('ConfigServer::URLGet',{ CURL => '/nonexistent/curl', WGET => '/nonexistent/wget' });

    my $client = ConfigServer::URLGet->new(1, 'agent-test', '');
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    my @result = $client->urlget();

    is(scalar @result, 0, 'no URL returns an empty result list');
    is(scalar @warnings, 1, 'missing URL emits one warning');
    like($warnings[0], qr/url not specified/, 'warning explains that the URL is required');
};

subtest 'urlget dispatches to the configured worker backend' => sub {
    TestBootstrap::reload_module_with_config('ConfigServer::URLGet',{ CURL => '/nonexistent/curl', WGET => '/nonexistent/wget' });

    no warnings qw(redefine once);

    local *ConfigServer::URLGet::urlgetTINY = sub { return (0, 'tiny-backend') };
    my $tiny = ConfigServer::URLGet->new(1, 'agent', '');
    is_deeply([$tiny->urlget('https://example.test')], [0, 'tiny-backend'], 'option 1 dispatches to the HTTP::Tiny worker');

    local *ConfigServer::URLGet::binget = sub { return (0, 'bin-backend') };
    my $bin = ConfigServer::URLGet->new(3, 'agent', '');
    is_deeply([$bin->urlget('https://example.test')], [0, 'bin-backend'], 'option 3 dispatches to the binary fallback worker');

    SKIP: {
        skip 'LWP::UserAgent is not available in this environment', 2
            unless eval { require LWP::UserAgent; 1 };

        local *ConfigServer::URLGet::urlgetLWP = sub { return (0, 'lwp-backend') };
        my $lwp = ConfigServer::URLGet->new(2, 'agent', '');
        isa_ok($lwp, 'ConfigServer::URLGet', 'option 2 constructor returns an object when LWP is available');
        is_deeply([$lwp->urlget('https://example.test')], [0, 'lwp-backend'], 'option 2 dispatches to the LWP worker');
    }
};

subtest 'urlgetTINY uses the configured agent and proxy and returns inline content on success' => sub {
    TestBootstrap::reload_module_with_config('ConfigServer::URLGet',{ CURL => '/nonexistent/curl', WGET => '/nonexistent/wget' });

    my %new_args;
    no warnings qw(redefine once);
    local *HTTP::Tiny::new = sub {
        my ($class, %args) = @_;
        %new_args = %args;
        return bless {}, $class;
    };
    local *HTTP::Tiny::request = sub {
        my ($self, $method, $url) = @_;
        is($method, 'GET', 'HTTP::Tiny backend performs a GET request');
        is($url, 'https://example.test/content', 'HTTP::Tiny backend receives the requested URL');
        return {
            success => 1,
            content => 'tiny-body',
        };
    };

    my $client = ConfigServer::URLGet->new(1, 'CustomAgent/1.0', 'http://proxy.test:8080');
    my ($status, $text) = $client->urlget('https://example.test/content');

    is($status, 0, 'successful inline download returns status 0');
    is($text, 'tiny-body', 'successful inline download returns the response body');
    is($new_args{agent}, 'CustomAgent/1.0', 'configured agent string is passed into HTTP::Tiny');
    is($new_args{proxy}, 'http://proxy.test:8080', 'configured proxy is passed into HTTP::Tiny');
    is($new_args{timeout}, 300, 'HTTP::Tiny timeout is set as expected');
};

subtest 'urlgetTINY streams file downloads into a temporary file before renaming' => sub {
    TestBootstrap::reload_module_with_config('ConfigServer::URLGet',{ CURL => '/nonexistent/curl', WGET => '/nonexistent/wget' });

    my $dir = tempdir(CLEANUP => 1);
    my $target = File::Spec->catfile($dir, 'download.bin');

    no warnings qw(redefine once);
    local *HTTP::Tiny::new = sub {
        my ($class, %args) = @_;
        return bless {}, $class;
    };
    local *HTTP::Tiny::request = sub {
        my ($self, $method, $url, $opts) = @_;

        my $response = {
            success => 1,
            headers => { 'content-length' => 6 },
        };

        $opts->{data_callback}->('abc', $response);
        $opts->{data_callback}->('def', $response);

        return $response;
    };

    my $client = ConfigServer::URLGet->new(1, 'DownloadAgent/1.0', '');
    my ($status, $path) = $client->urlget('https://example.test/file', $target, 1);

    open(my $fh, '<', $target) or die "Unable to open $target: $!";
    local $/;
    my $content = <$fh>;
    close($fh);

    is($status, 0, 'successful file download returns status 0');
    is($path, $target, 'successful file download returns the requested path');
    is($content, 'abcdef', 'downloaded chunks are written to the final file');
    ok(!-e "$target.tmp", 'temporary file is renamed away after success');
};

subtest 'urlgetTINY falls back to binget when the HTTP backend returns an error' => sub {
    TestBootstrap::reload_module_with_config('ConfigServer::URLGet',{ CURL => '/nonexistent/curl', WGET => '/nonexistent/wget' });

    my @fallback_args;
    no warnings qw(redefine once);
    local *HTTP::Tiny::new = sub {
        my ($class, %args) = @_;
        return bless {}, $class;
    };
    local *HTTP::Tiny::request = sub {
        return {
            success => 0,
            status  => 599,
            content => 'gateway exploded',
            reason  => 'Internal failure',
        };
    };
    local *ConfigServer::URLGet::binget = sub {
        @fallback_args = @_;
        return (1, 'fallback-result');
    };

    my $client = ConfigServer::URLGet->new(1, 'FallbackAgent/1.0', '');
    my ($status, $text) = $client->urlget('https://example.test/fail', undef, 1);

    is($status, 1, 'fallback result status is returned');
    is($text, 'fallback-result', 'fallback result text is returned');
    is_deeply(
        \@fallback_args,
        ['https://example.test/fail', undef, 1, 'gateway exploded'],
        'binget receives the request context and the 599 response body as the error message',
    );
};

subtest 'binget reports a clear error when no download helpers are configured' => sub {
    TestBootstrap::reload_module_with_config('ConfigServer::URLGet',{ CURL => '/definitely/missing/curl', WGET => '/definitely/missing/wget' });

    my $client = ConfigServer::URLGet->new(1, 'NoHelpers/1.0', '');
    my ($status, $text) = ConfigServer::URLGet::binget('https://example.test/file', undef, 1, 'initial failure');

    is($status, 1, 'missing helper binaries return an error status');
    is(
        $text,
        'Unable to download (CURL/WGET also not present, see csf.conf): initial failure',
        'non-binary mode includes the original error message when helpers are unavailable',
    );

    $client = ConfigServer::URLGet->new(3, 'NoHelpers/1.0', '');
    ($status, $text) = ConfigServer::URLGet::binget('https://example.test/file', undef, 1, 'ignored');

    is($status, 1, 'binary-only mode also returns an error status');
    is(
        $text,
        'Unable to download (CURL/WGET also not present, see csf.conf)',
        'binary-only mode omits the upstream error detail when helpers are unavailable',
    );
};

subtest 'urlgetLWP can be exercised without network access when LWP is available' => sub {
    TestBootstrap::reload_module_with_config('ConfigServer::URLGet',{ CURL => '/nonexistent/curl', WGET => '/nonexistent/wget' });

    SKIP: {
        skip 'LWP::UserAgent is not available in this environment', 7
            unless eval { require LWP::UserAgent; require HTTP::Request; 1 };

        my %calls;
        no warnings qw(redefine once);
        local *LWP::UserAgent::new = sub {
            my ($class) = @_;
            return bless {}, $class;
        };
        local *LWP::UserAgent::agent = sub {
            my ($self, $agent) = @_;
            $calls{agent} = $agent;
            return;
        };
        local *LWP::UserAgent::timeout = sub {
            my ($self, $timeout) = @_;
            $calls{timeout} = $timeout;
            return;
        };
        local *LWP::UserAgent::proxy = sub {
            my ($self, $schemes, $proxy) = @_;
            $calls{proxy} = $proxy;
            $calls{schemes} = $schemes;
            return;
        };
        local *LWP::UserAgent::request = sub {
            my ($self, $request) = @_;
            isa_ok($request, 'HTTP::Request', 'urlgetLWP builds an HTTP::Request object');
            $calls{method} = $request->method;
            $calls{url} = $request->uri->as_string;
            return Local::URLGetLWPResponse->new(
                is_success => 1,
                content    => 'lwp-body',
            );
        };

        my $client = ConfigServer::URLGet->new(2, 'LWPAgent/2.0', 'http://proxy.test:9090');
        my ($status, $text) = $client->urlget('https://example.test/lwp');

        is($status, 0, 'successful LWP inline download returns status 0');
        is($text, 'lwp-body', 'successful LWP inline download returns the response body');
        is($calls{agent}, 'LWPAgent/2.0', 'configured LWP agent is applied');
        is($calls{timeout}, 30, 'configured LWP timeout is applied');
        is($calls{proxy}, 'http://proxy.test:9090', 'configured proxy is applied to the LWP client');
        is_deeply($calls{schemes}, ['http', 'https'], 'proxy is attached to both HTTP and HTTPS schemes');
        is($calls{method}, 'GET', 'LWP request uses GET');
        is($calls{url}, 'https://example.test/lwp', 'LWP request targets the requested URL');
    }
};

done_testing;

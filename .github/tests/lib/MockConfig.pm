package MockConfig;

use strict;
use warnings;

use Test::MockModule;

our %config;
our $_mock;

sub set_config {
    my %new_config = @_;
    %config = %new_config;

    no warnings 'once';
    %sbin::csf::config = %new_config;

    return;
}

sub clear_config {
    %config = ();

    no warnings 'once';
    %sbin::csf::config = ();

    return;
}

sub get_mock_config {
    return %config;
}

sub merge_config {
    my %override = @_;
    my %merged = ( %config, %override );
    set_config(%merged);
    return;
}

sub import {
    my $class  = shift;
    my $caller = caller;

    no strict 'refs';
    *{"${caller}::set_config"}      = \&set_config;
    *{"${caller}::clear_config"}    = \&clear_config;
    *{"${caller}::get_mock_config"} = \&get_mock_config;
    *{"${caller}::merge_config"}    = \&merge_config;

    $_mock = Test::MockModule->new('ConfigServer::Config');
    $_mock->redefine(
        loadconfig => sub {
            return bless {}, 'ConfigServer::Config';
        },
        get_config => sub {
            my $key = shift;
            return $config{$key};
        },
        config => sub {
            return %config;
        },
        resetconfig => sub {
            %config = ();
            no warnings 'once';
            %sbin::csf::config = ();
            return;
        },
        ipv4reg => sub {
            return qr/(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/;
        },
        ipv6reg => sub {
            return qr/((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?/;
        },
    );
}

1;

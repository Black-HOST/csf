package TestCSFScript;

use strict;
use warnings;

use Exporter qw(import);
use File::Spec;
use TestBootstrap qw(repo_root);

our @EXPORT_OK = qw(load_csf_pl);

sub _install_stubs {
    {
        no warnings 'once';
        package ConfigServer::Config;
        sub import { return }
        sub loadconfig { bless {}, __PACKAGE__ }
        sub get_config { return '' }
        sub config { return () }
        sub ipv4reg { return qr/(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/ }
        sub ipv6reg { return qr/[0-9A-Fa-f:]+/ }
    }
    $INC{'ConfigServer/Config.pm'} = __FILE__;

    {
        no warnings 'once';
        package ConfigServer::URLGet;
        sub import { return }
        sub urlget { return }
    }
    $INC{'ConfigServer/URLGet.pm'} = __FILE__;
}

sub load_csf_pl {
    _install_stubs();
    my $script = File::Spec->catfile( repo_root(), 'csf.pl' );
    my $loaded = do $script;
    die $@ || $! unless $loaded;
    return $script;
}

1;

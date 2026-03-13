package TestBootstrap;

use strict;
use warnings;

use Exporter qw(import);
use File::Basename qw(dirname);
use File::Spec;

our @EXPORT_OK = qw(repo_root mock_config with_mock_config reload_module_with_config);

BEGIN {
    # Ensure tests load modules from this checkout before any system-installed CSF copy.
    my $root = File::Spec->rel2abs(
        File::Spec->catdir( dirname(__FILE__), '..', '..', '..' )
    );

    unshift @INC, $root unless grep { $_ eq $root } @INC;
    $ENV{CSF_TEST_REPO_ROOT} ||= $root;
}

sub repo_root {
    return $ENV{CSF_TEST_REPO_ROOT};
}

# ---------------------------------------------------------------------------
# Shared config-mocking helpers
# ---------------------------------------------------------------------------

{
    package TestBootstrap::MockConfig;

    sub new {
        my ($class, $config) = @_;
        return bless { config => $config }, $class;
    }

    sub config {
        my ($self) = @_;
        return %{ $self->{config} };
    }
}

sub mock_config {
    my ($config) = @_;
    return TestBootstrap::MockConfig->new($config);
}

sub with_mock_config {
    my ($config, $code) = @_;

    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return TestBootstrap::MockConfig->new($config);
    };

    return $code->();
}

sub reload_module_with_config {
    my ($module, $config, %opts) = @_;

    require ConfigServer::Config;

    no warnings qw(redefine once);
    local *ConfigServer::Config::loadconfig = sub {
        return TestBootstrap::MockConfig->new($config);
    };

    my $path = $module;
    $path =~ s{::}{/}g;
    $path .= '.pm';
    delete $INC{$path};

    for my $extra (@{ $opts{also_delete} || [] }) {
        my $ep = $extra;
        $ep =~ s{::}{/}g;
        $ep .= '.pm';
        delete $INC{$ep};
    }

    eval "require $module; 1" or die $@;
    return 1;
}

1;

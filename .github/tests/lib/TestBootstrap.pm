package TestBootstrap;

use strict;
use warnings;

use Exporter qw(import);
use File::Basename qw(dirname);
use File::Spec;

our @EXPORT_OK = qw(repo_root);

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

1;

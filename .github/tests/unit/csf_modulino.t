#!/usr/bin/env perl

BEGIN {
    *CORE::GLOBAL::exit = sub { die "unexpected exit(@_)" };
}

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->catdir( $Bin, '..', 'lib' );

use Test::More;
use TestBootstrap qw(repo_root);
use TestCSFScript qw(load_csf_pl);

my $script = File::Spec->catfile( repo_root(), 'csf.pl' );
local @ARGV = ('__should_not_run__');

my $loaded = eval { load_csf_pl(); 1 };
ok( $loaded, 'csf.pl loads successfully as a modulino' ) or diag $@ || $!;
can_ok( 'sbin::csf', qw(run run_open3 process_input) );
{
    no warnings 'once';
    ok( !defined $sbin::csf::input{command}, 'loading csf.pl does not execute top-level dispatch' );
}

done_testing;

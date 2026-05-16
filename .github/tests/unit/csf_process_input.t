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
use TestCSFScript qw(load_csf_pl);

load_csf_pl();

{
    no warnings 'once';
    local %sbin::csf::input;
    local @ARGV = ( '--ADD', '1.2.3.4', 'with', 'comment' );

    sbin::csf::process_input();

    is( $sbin::csf::input{command}, '--add', 'process_input lowercases the command' );
    is( $sbin::csf::input{argument}, '1.2.3.4 with comment', 'process_input joins remaining args into argument' );
}

{
    no warnings 'once';
    local %sbin::csf::input;
    local @ARGV = ('--help');

    sbin::csf::process_input();

    is( $sbin::csf::input{command}, '--help', 'single-argument command is preserved' );
    ok( !defined $sbin::csf::input{argument}, 'single-argument command leaves argument undefined' );
}

done_testing;

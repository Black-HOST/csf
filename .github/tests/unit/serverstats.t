#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;
use lib "$Bin/../lib";

use TestBootstrap ();
use ConfigServer::ServerStats;

sub reset_serverstats_state {
    delete $INC{'ConfigServer/ServerStats.pm'};
    require ConfigServer::ServerStats;
    return;
}

subtest 'init returns undef when GD::Graph::bars is unavailable' => sub {
    my $loaded = eval { require GD::Graph::bars; 1 };

    SKIP: {
        skip 'GD::Graph::bars is installed in this environment', 1 if $loaded;

        my $result = ConfigServer::ServerStats::init();
        is($result, undef, 'init returns undef when GD::Graph backends cannot load');
    }
};

subtest 'charts_html assembles the standard four-image layout' => sub {
    my $html = ConfigServer::ServerStats::charts_html(0, '/img/');

    like($html, qr{<table class='table table-bordered'>}, 'output opens with the standard table wrapper');
    like($html, qr{src='/img/lfd_hour\.gif\?text=\d+}, 'hour bar chart points at the configured image dir');
    like($html, qr{src='/img/lfd_pie_hour\.gif\?text=\d+}, 'hour pie chart is rendered');
    like($html, qr{src='/img/lfd_month\.gif\?text=\d+}, 'month chart is rendered');
    like($html, qr{src='/img/lfd_year\.gif\?text=\d+}, 'year chart is rendered');
    unlike($html, qr{lfd_cc\.gif}, 'country chart is omitted when cc_lookups is false');
};

subtest 'charts_html adds the country chart when cc_lookups is enabled' => sub {
    my $html = ConfigServer::ServerStats::charts_html(1, '/assets/');

    like($html, qr{src='/assets/lfd_cc\.gif\?text=\d+}, 'country chart is rendered when cc_lookups is true');
    like($html, qr{src='/assets/lfd_year\.gif\?text=\d+}, 'year chart still rendered alongside cc chart');
};

subtest 'minmaxavg tracks min, max, and running-sum AVG across calls' => sub {
    reset_serverstats_state();

    ConfigServer::ServerStats::minmaxavg('HOUR', '1cpu', 10);
    ConfigServer::ServerStats::minmaxavg('HOUR', '1cpu', 30);
    ConfigServer::ServerStats::minmaxavg('HOUR', '1cpu', 20);

    my $html = ConfigServer::ServerStats::graphs_html('/x/');

    like($html, qr{<b>cpu</b></td><td>Min:<b>10\.00</b></td><td>Max:<b>30\.00</b></td><td>Avg:<b>60\.00</b>}, 'HOUR cpu row reports MIN=10, MAX=30, and the cumulative AVG sum');
};

subtest 'minmaxavg keeps each (graph, name) bucket isolated' => sub {
    reset_serverstats_state();

    ConfigServer::ServerStats::minmaxavg('HOUR',  '1cpu',  10);
    ConfigServer::ServerStats::minmaxavg('HOUR',  '1cpu',  20);
    ConfigServer::ServerStats::minmaxavg('HOUR',  '2load', 5);
    ConfigServer::ServerStats::minmaxavg('DAY',   '1cpu',  100);
    ConfigServer::ServerStats::minmaxavg('WEEK',  '3disk', 99);
    ConfigServer::ServerStats::minmaxavg('MONTH', '4mem',  512);

    my $html = ConfigServer::ServerStats::graphs_html('/g/');

    like($html, qr{<b>cpu</b></td><td>Min:<b>10\.00</b></td><td>Max:<b>20\.00</b>}, 'HOUR cpu bucket shows only the HOUR samples');
    like($html, qr{<b>load</b></td><td>Min:<b>5\.00</b></td><td>Max:<b>5\.00</b>}, 'HOUR load bucket is independent of cpu');
    like($html, qr{<b>cpu</b></td><td>Min:<b>100\.00</b></td><td>Max:<b>100\.00</b>}, 'DAY cpu bucket is independent of HOUR cpu bucket');
    like($html, qr{<b>disk</b></td><td>Min:<b>99\.00</b>}, 'WEEK bucket shows the WEEK sample only');
    like($html, qr{<b>mem</b></td><td>Min:<b>512\.00</b>}, 'MONTH bucket shows the MONTH sample only');
};

subtest 'graphs_html targets the configured image directory for every timeframe' => sub {
    reset_serverstats_state();

    ConfigServer::ServerStats::minmaxavg('HOUR',  '1x', 1);
    ConfigServer::ServerStats::minmaxavg('DAY',   '1x', 1);
    ConfigServer::ServerStats::minmaxavg('WEEK',  '1x', 1);
    ConfigServer::ServerStats::minmaxavg('MONTH', '1x', 1);

    my $html = ConfigServer::ServerStats::graphs_html('/cdn/');

    like($html, qr{src='/cdn/lfd_systemhour\.gif\?text=\d+},  'HOUR image src uses the supplied imgdir');
    like($html, qr{src='/cdn/lfd_systemday\.gif\?text=\d+},   'DAY image src uses the supplied imgdir');
    like($html, qr{src='/cdn/lfd_systemweek\.gif\?text=\d+},  'WEEK image src uses the supplied imgdir');
    like($html, qr{src='/cdn/lfd_systemmonth\.gif\?text=\d+}, 'MONTH image src uses the supplied imgdir');
};

done_testing;

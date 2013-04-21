#!/usr/bin/perl

use strict;

use warnings;

use lib './lib';

use Brew::Thermometer::Reader;

my $heat = Brew::Thermometer::Reader->new({mash=>'28-000004672ef9', herms=>'28-00000467bc19'});

$heat->go();




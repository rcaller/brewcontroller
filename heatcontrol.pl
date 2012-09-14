#!/usr/bin/perl

use strict;

use warnings;

use lib './lib';

use Brew::Heater::Controller;

my $heat = Brew::Heater::Controller->new();

$heat->go();




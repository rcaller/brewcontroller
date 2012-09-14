#!/usr/bin/perl

use strict;

use warnings;

use lib './lib';

use Brew::Thermometer::Reader;

my $heat = Brew::Thermometer::Reader->new('/home/richc/brewcontroller/bin/pcsensor -s');

$heat->go();




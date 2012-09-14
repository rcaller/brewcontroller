#!/usr/bin/perl

use strict;

use warnings;

use lib './lib';

use Brew::Controller;

my $brew = Brew::Controller->new();

$brew->go();




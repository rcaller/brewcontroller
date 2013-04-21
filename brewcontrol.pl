#!/usr/bin/perl

use strict;

use warnings;

use FindBin;

use lib "$FindBin::Bin/lib";

use Brew::Controller;

my $brew = Brew::Controller->new();

$brew->go();




package Brew::Config;

=head1 NAME

Brew::Config - Brewery mash config reader

=head1 SYNOPSIS

    use Brew::Config;
    my $brew = Brew::Config->new();
    $brew->get(NAME);

=head1 DESCRIPTION

Simple config reader

=head2 Methods

=cut

use strict;
use warnings;
use YAML::Syck;
use FindBin;
use constant CONFIG_FILE => "$FindBin::Bin/conf/brewconfig.yaml";
use constant LOG_CONFIG => "$FindBin::Bin/conf/log4perl.conf";

=over 12

=item C<new>

Returns a new Brew::Config object.

=cut


sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  $self->init();
  return $self;
}

=item C<init>

Load YAML file

=cut

sub init {
  my $self=shift;
  $self->{data} = LoadFile(CONFIG_FILE);
}

=item C<get>

Return a config value

=cut

sub get {
  my $self = shift;
  my ($config_name) = @_;
  return $self->{data}{$config_name};
}

=item C<log_config>

Return path to logger config

=cut

sub log_config {
  my $self = shift;
  return LOG_CONFIG
}

=head1 AUTHOR

Richc

=cut

1;

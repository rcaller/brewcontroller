package Brew::Controller;

=head1 NAME

Brew::Controller - Brewery mash controller

=head1 SYNOPSIS

    use Brew::Controller;
    my $brew = Brew::Controller->new();
    $brew->go();

=head1 DESCRIPTION

Brewery control system core.  This will take readings from a USB thermometer (temper 1). 
 It will report these to a web serivce that will return a target temperature.  A pid 
algorithm will be used to pass a percentage power rate to the heater control element in the HERMS tank

=head2 Methods

=cut

use strict;
use warnings;

use Data::Dumper;
use Brew::Heater::Controller;
use Brew::Thermometer::Reader;

use Brew::Config;

use JSON;

use ZeroMQ qw/:all/;
use LWP;

use constant LOOP_TIME => 5;

use constant THERMOMETER_BINARY=>"/home/richc/brewcontroller/bin/pcsensor -s";

use constant PROPORTIONAL => 2;

use constant HEATER_QUEUE_ADDRESS => 'tcp://127.0.0.1:9909';
use constant THERMO_QUEUE_ADDRESS => 'tcp://127.0.0.1:9908';


my $target = 30;

=over 12

=item C<new>

Returns a new Brew::Heater::Controller object.

=cut



sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

=item C<init>
  initialise 
=cut

sub init {
  my $self = shift;
  $self->{config} = Brew::Config->new();
  $self->{ua} = LWP::UserAgent->new;
  $self->{mq} = ZeroMQ::Context->new();
  $self->{heater_socket} = $self->{mq}->socket(ZMQ_PUSH);
  $self->{heater_socket}->bind($self->{config}->get('heater_queue'));
  # fork heater controller process
  my $pid = fork();
  if (!$pid) {
    my $heat = Brew::Heater::Controller->new();
    $heat->subscribe_to_queue($self->{config}->get('heater_queue'));
    $heat->go();
    die("Heater Child exit");
  }
  # in parent set pid
  $self->{heater_pid} = $pid;

  $self->{thermo_socket} = $self->{mq}->socket(ZMQ_PULL);
  $self->{thermo_socket}->bind($self->{config}->get('thermo_queue'));

  my $pid2 = fork();; 
  if (!$pid2) {
    my $thermo = Brew::Thermometer::Reader->new($self->{config}->get('thermometer_binary'));
    $thermo->subscribe_to_queue($self->{config}->get('thermo_queue'));
    $thermo->go();
    die("Thermometer Child exit");
  }
  $self->{thermo_pid} = $pid2;
  return;
}

=item C<go>

Start the brew controller daemon

=cut

sub go {
  my $self = shift;
  $self->init();
  print "GO!\n";
  while (1) {
    my $temp = $self->read_temp();
    if ($temp) {
      $self->report_temp($temp); 
      my $setting = PROPORTIONAL * ($target - $temp);
      print  "temp - $temp : target - $target : st - $setting\n";
      $self->{heater_socket}->send($setting);
    }
    else {
      print "Temp not set\n";
    }
    sleep(3);
  }

}

=item C<read_temp>

Read the latest temperature from the thermometer

=cut

sub read_temp {
  my $temp;
  my $self = shift;
  while (my $l = $self->{thermo_socket}->recv(ZMQ_NOBLOCK)) {
    if (defined($l->data) && $l->data) {
      $temp = int($l->data);
    }
  }
  return $temp;
}

=item C<report_temp>

Report current temp to server

=cut

sub report_temp {
  my $self = shift;
  my ($temp) = @_;
  my $url = $self->{config}->get('report_url') . $temp;
  my $resp = $self->{ua}->get($url);
  return $self->parse_response($resp->content());
}

=item C<parse_response>

Parse the data back from the server and return either undef or a brewstatus object

=cut

sub parse_response {
  my $self = shift;
  my ($resp) = @_;

}

=back

=head1 LICENSE

This is released under the Artistic 
License. See L<perlartistic>.

=head1 AUTHOR

Richc

=cut

1;

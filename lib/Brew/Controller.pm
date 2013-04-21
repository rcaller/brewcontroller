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
use Log::Log4perl;

use Brew::Config;
use Brew::PID;

use JSON;

use ZeroMQ qw/:all/;
use LWP;

use constant LOOP_TIME => 5;

use constant THERMOMETER_BINARY=>"/home/richc/brewcontroller/bin/pcsensor -s";


use constant HEATER_QUEUE_ADDRESS => 'tcp://127.0.0.1:9909';
use constant THERMO_QUEUE_ADDRESS => 'tcp://127.0.0.1:9908';



=over 12

=item C<new>

Returns a new Brew::Heater::Controller object.

=cut



sub new {
  my $class = shift;
  my $self = {target_temp => 0};
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
  $self->{pid} = Brew::PID->new($self->{config}->get('pid'));
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
    my $thermo = Brew::Thermometer::Reader->new($self->{config}->get('thermometers'));
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
  my $p =  $self->{config}->get('pid')->{p};
  while (1) {
    my $temps = $self->read_temp();
    if ($temps) {
      $self->{target_temp} = $self->report_temp($temps);
      if ($self->{target_temp}) {
        my $temp;
        my $target_temp;
        if ($self->{target_temp}{active}) {
          $temp = $temps->{flow}; 
          $target_temp = $self->{target_temp}{active};
        }
        else {
           $temp = $temps->{herms};
          $target_temp = $self->{target_temp}{pre_warm};

        }

        my $setting = 100 * $self->{pid}->getResponse(current=>$temp, target=>$target_temp);
        $setting=100 if $setting>100;
        print  "temp - $temp : target - $target_temp : st - $setting\n";
        $self->{heater_socket}->send($setting);
      }
      else {
        print "No target set\n";
      }
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
  while (my $l = $self->{thermo_socket}->recv_as("json", ZMQ_NOBLOCK)) {
    if (defined($l) && $l) {
      $temp = $l;
    }
  }
  return $temp;
}

=item C<report_temp>

Report current temps to server

=cut

sub report_temp {
  my $self = shift;
  my ($temps) = @_;
  print STDERR Dumper($temps);
  my $url = $self->{config}->get('report_url');
  my $req = HTTP::Request->new('POST', $url);
  $req->header( 'Content-Type' => 'application/json' );
  $req->content( to_json($temps) );
  my $resp = $self->{ua}->request($req);
  return $self->parse_response($resp->content());
}

=item C<parse_response>

Parse the data back from the server and return either undef or a brewstatus object

=cut

sub parse_response {
  my $self = shift;
  my ($resp) = @_;
  return from_json($resp);
}

=back

=head1 LICENSE

This is released under the Artistic 
License. See L<perlartistic>.

=head1 AUTHOR

Richc

=cut

1;

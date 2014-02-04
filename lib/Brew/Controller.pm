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
use List::Util qw( min max );
use Math::Derivative qw(Derivative1 Derivative2);
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
  Log::Log4perl::init($self->{config}->log_config());
  $self->{logger} = Log::Log4perl->get_logger('brew.controller');
  $self->{logger}->warn('Controller Starting');
  $self->{config} = Brew::Config->new();
  $self->{ua} = LWP::UserAgent->new;
  $self->{mq} = ZeroMQ::Context->new();
  $self->{pid} = Brew::PID->new($self->{config}->get('pid'));
  $self->{heater_socket} = $self->{mq}->socket(ZMQ_PUSH);
  $self->{heater_socket}->bind($self->{config}->get('heater_queue'));


  #$self->{tune}=0;

  # fork heater controller process
  my $pid = fork();
  if (!$pid) {
    my $heat = Brew::Heater::Controller->new();
    $heat->set_logger($self->{logger});
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
   $self->{logger}->warn('Starting control');
  my $p =  $self->{config}->get('pid')->{p};
  while (1) {
    $self->tune() if ($self->{tune});
    my $temps = $self->read_temp();
    if ($temps) {
      $self->{target_temp} = $self->report_temp($temps);
      $self->{logger}->warn("TT".Dumper($self->{target_temp}));
      if ($self->{target_temp}) {
        my $temp;
        my $target_temp;
        
        if ($self->{target_temp}{active}) {
          if (!$temps->{flow}) {
            $self->{logger}->warn("No Flow Temp");
            next;
          }
          $temp = $temps->{flow} - 0.3; 
          $target_temp = $self->{target_temp}{active};
        }
        else {
           if (!$temps->{herms}) {
            $self->{logger}->warn("No HERMS Temp");
            next;
          }
 
           $temp = $temps->{herms};
          $target_temp = $self->{target_temp}{pre_warm};

        }
        
        my $setting = 100 * $self->{pid}->getResponse(current=>$temp, target=>$target_temp);
        $setting=100 if $setting>100;
        $setting = 0 if $temps->{flow} > $target_temp+5;
        $self->{logger}->warn("Temp - $temp");
        $self->{logger}->warn("Target - $target_temp");
        $self->{logger}->warn("Setting - $setting");
        $self->{heater_socket}->send($setting);
      }
      else {
         $self->{logger}->warn('No target set');
      }
    }
    else {
       $self->{logger}->warn('Temp not set');
    }
	    sleep(3);
  }

}

=item C<tune>

Run a Zieger-Nichols tuning process

=cut

sub tune {
  my $self = shift;
  my $tune_setting=20;
  my $tune_start = time;
  my $tuning_data={};
  $self->{logger}->warn('Starting tune');
  while (1) {
    sleep 1;
    last if (!$self->{tune});
    my $temps = $self->read_temp();
    next if (!$temps->{flow});
    $self->report_temp($temps);
    my $time = time - $tune_start;
    $tuning_data->{$time} = $temps->{flow};
    $self->{heater_socket}->send($tune_setting);
    $self->{logger}->info("tune - $time:".$temps->{flow});
    last if (defined($tuning_data->{$time - 120}) && ($temps->{flow} == $tuning_data->{$time - 20})); 
  
    my $fh;
    open $fh, '>', '/tmp/tuningdata.json';
    print $fh to_json($tuning_data);
    close $fh;
    my @x = keys(%$tuning_data);
    my @y = values(%$tuning_data);
    eval {
      my @derivative = Derivative1(\@x, \@y);
      my @second_derivative = Derivative2(\@x, \@y);
      my $index = grep {$second_derivative[$_] == (max(@second_derivative))} 0..$#second_derivative; 
      $self->{logger}->info("index $index"); 
      my $L = $y[$index] - ($derivative[$index] * $x[$index]);
      my $T = ((max(@y) - $L) / $derivative[$index]) - $L;
      print "L - $L\nT - $T\n\n";
      my $p = 1.2 * $T / $L;
      my $i = 0.6 * $T / $L^2;
      my $d = 0.6 * $T;
      print "p-$p\ni-$i\nd-$d\n";
    }
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
  $self->{logger}->info(Dumper($temps));
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

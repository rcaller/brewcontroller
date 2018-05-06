package Brew::Thermometer::Reader;

=head1 NAME

Brew::Thermometer::Reader

=head1 SYNOPSIS

    use Brew::Thermometer::Reader;
    my $brew = Brew::Thermometer::Reader->new(therm=>idvalue);
    $brew->go();

=head1 DESCRIPTION

This module is a daemon.  It will print the temperature in C to STDOUT every interval

=head2 Methods

=cut

use strict;
use warnings;

use ZeroMQ qw/:all/;
use JSON;
use Log::Log4perl;

use constant LOOP_TIME => 1;

=over 12

=item C<new>

Returns a new Brew::Thermometer::Reader object.

Arguement is hash of names and id numbers for thermometers

=cut



sub new {
  my $class = shift;
  my ($therms)= @_;
  my $self = {thermometers => $therms};
  $self->{logger} = Log::Log4perl->get_logger('brew.controller');
  bless $self, $class;
  return $self;
}



=item C<go>

Start the temperature reader daemon

=cut

sub go {
  my $self = shift;
  
  while (1) {
    my $temp_data = {};
    foreach my $therm(keys %{$self->{thermometers}}) {
      my $therm_id = $self->{thermometers}{$therm}{id};
      next if !$therm_id;
      my $sensor_temp = `cat /sys/bus/w1/devices/$therm_id/w1_slave 2>&1`;
      if ($sensor_temp !~ /No such file or directory/) {
        if ($sensor_temp !~ /NO/) {
          $sensor_temp =~ /t=(\d+)/i;
          $self->{logger}->warn($self->{thermometers}{$therm}{correct});
          my $temperature = (($1/1000)+$self->{thermometers}{$therm}{correct});
          $temp_data->{$therm}=$temperature
        }
      }
      else { 
	 $self->{logger}->warn("$therm_id not found"); 
      }       
    }
    $self->{queue}->send_as(json => $temp_data);
    sleep LOOP_TIME
  }

}

=item C<subscribe_to_queue>
  subscribe to a queue on the passed address
=cut

sub subscribe_to_queue {
  my $self = shift;
  my ($queue_address) = @_;
  $self->{mq} = ZeroMQ::Context->new();
  $self->{queue} = $self->{mq}->socket(ZMQ_PUSH);
  $self->{queue}->connect($queue_address);
 
}




=back

=head1 LICENSE

This is released under the Artistic 
License. See L<perlartistic>.

=head1 AUTHOR

Richc

=cut

1;

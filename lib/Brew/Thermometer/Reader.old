package Brew::Thermometer::Reader;

=head1 NAME

Brew::Thermometer::Reader

=head1 SYNOPSIS

    use Brew::Thermometer::Reader;
    my $brew = Brew::Thermometer::Reader->new();
    $brew->go();

=head1 DESCRIPTION

This module is a daemon.  It will print the temperature in C to STDOUT every interval

=head2 Methods

=cut

use strict;
use warnings;

use ZeroMQ qw/:all/;

use constant LOOP_TIME => 1;

=over 12

=item C<new>

Returns a new Brew::Thermometer::Reader object.

Takes one arguement, the path to an executable that will itself
print temperature to STDOUT when run

=cut



sub new {
  my $class = shift;
  my $binary = shift;
  my $self = {binary => $binary};
  bless $self, $class;
  return $self;
}



=item C<go>

Start the temperature reader daemon

=cut

sub go {
  my $self = shift;
  
  while (1) {
    my $executable = $self->{binary};
    my $temp = `$executable`;
    chomp($temp);
    $self->{queue}->send($temp);
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

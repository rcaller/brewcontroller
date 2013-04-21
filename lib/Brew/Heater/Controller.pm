package Brew::Heater::Controller;

=head1 NAME

Brew::Heater::Controller - Controller for usb switched element

=head1 SYNOPSIS

    use Brew::Heater::Controller;
    my $brew = Brew::Heater::Controller->new();
    $brew->go();

=head1 DESCRIPTION

This module is a daemon that will fork.  It expects to be created with an input
pipe off which it will take power level requests.  Every execution cycle it will 
attempt to take a number (0-100) from the pipe, if there are multiple numbers in the pipe
it will take the last one.  If there are no numbers in the pipe it will take the 
preious number it received or 0 if it has no number yet.
  It will then switch the element on for n% of the next execution cycle

=head2 Methods

=cut

use strict;
use warnings;

use IO::Handle;
use Time::HiRes qw|usleep|;
use ZeroMQ qw/:all/;
use constant LOOP_TIME => 5;

=over 12

=item C<new>

Returns a new Brew::Heater::Controller object.

=cut



sub new {
  my $class = shift;
  my $self = {on => 0};
  bless $self, $class;
  $self->init();
  return $self;
}

=item C<init>
  initialise 
=cut

sub init {
  my $self = shift;
  my $io = new IO::Handle;
  if ($io->fdopen(fileno(STDIN),"r")) {
    $io->blocking(0);
    $self->{io} = $io;
  }
  else {
    die("Failed to open STDIN");
  }
}

=item C<go>

Start the brew controller daemon

=cut

sub go {
  my $self = shift;
  
  while (1) {
    $self->read_queue();
    $self->control();
  }

}

=item C<subscribe_to_queue>
  subscribe to a queue on the passed address
=cut

sub subscribe_to_queue {
  my $self = shift; 
  my ($queue_address) = @_;
  $self->{mq} = ZeroMQ::Context->new();
  $self->{queue} = $self->{mq}->socket(ZMQ_PULL);
  $self->{queue}->connect($queue_address);
  
}

=item C<read_queue>
  Read number from stdin and update on if needed
=cut

sub read_queue {
  my $self = shift;
  while (my $l = $self->{queue}->recv(ZMQ_NOBLOCK)) {
    my $percent = int($l->data);
    $self->{on} = $percent if ($percent<=100);
  }
}

=item C<control>
  Control the loop, on for $percent, off for rest of loop time
=cut

sub control {
  my $self = shift;
  my $on = LOOP_TIME*10000*$self->{on};
  my $off = (LOOP_TIME*1000000)-$on;
  system "./bin/on.sh";
  usleep $on if ($on>0);
  system "./bin/off.sh";
  usleep $off if ($off>0);
}

=back

=head1 LICENSE

This is released under the Artistic 
License. See L<perlartistic>.

=head1 AUTHOR

Richc

=cut

1;

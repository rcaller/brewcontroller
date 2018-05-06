package Brew::PID;

=head1 NAME

Brew::PID - PID controller implementation

=head1 SYNOPSIS

    use Brew::PID;
    my $pid = Brew::Controller->new({p=>1,i=>2,d=>3});
    $pid->getResponse(current => 1, target => 2);

=head1 DESCRIPTION

Implements a pid algoritm


Warning - this object is stateful and not thread safe

=head2 Methods

=cut

use strict;
use warnings;

use Data::Dumper;

use Data::Clone;

=over 12

=item C<new>

Returns a new Brew::PID object.

=cut



sub new {
  my $class = shift;
  my ($pid_hash) = @_;
  my $self = clone($pid_hash);
  bless $self, $class;
  return $self;
}

=over 12

=item C<getResponse>

Returns a float between 0-1

=cut


sub getResponse {
  my $self = shift;
  my %data = @_;
  my ($p, $i, $d) = 0;
  my $current = $data{current};
  my $target = $data{target};
  return 0 if !($data{current});
  my $error = $target - $current;
  $p = $error * $self->{p};
  $i = $self->integral($error);
  $d = $self->differential($current);
  
  print STDERR "P-$p\nI-$i\nD-$d\n\n";
  my $u = $p + $i + $d;
  return $u>1?1:$u; 
}


=over 12

=item C<integral>

Calculate integral component

=cut

sub integral {
  my $self = shift;
  my ($error) = @_;
  # unshift current error onto start of array
  unshift @{$self->{integral_array}}, $error;
  my $integral=0;
  if (scalar(@{$self->{integral_array}}) > 9) {
    map {$integral += $_} @{$self->{integral_array}}[0..9];
  }
  return ($integral * $self->{i});
}


=over 12

=item C<differential>

Calculate differential component

=cut

sub differential {
  my $self = shift;
  my ($temp) = @_;
  my $d = 0;
  my $time = time;
  if ($self->{last_temp}) {
    $d = ($temp - ($self->{last_temp})) /
         ($time - ($self->{last_time})) *
         $self->{d};
  } 
  $self->{last_temp} = $temp;
  $self->{last_time} = $time;


  return $d;
}

1;

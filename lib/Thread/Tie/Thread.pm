package Thread::Tie::Thread;

# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our $VERSION : unique = '0.02';
use strict;

# Make sure we can do threads
# Make sure we can do shared threads
# Make sure we can freeze and thaw

use threads ();
use threads::shared ();
use Storable ();

# Make sure the freeze and thaw routines are in memory
# Create frozen version of empty list
# Save the iced signature

Storable::thaw( Storable::freeze( [] ) );
my $iced = Storable::freeze( [] );
$iced = unpack( 'l',$iced );

# Clone detection logic

my $CLONE = 0;

# Satisfy -require-

1;

#---------------------------------------------------------------------------

# class methods

#---------------------------------------------------------------------------
#  IN: 1 class with which to bless the object
# OUT: 1 instantiated object

sub new {

# Obtain the class
# Make sure we have a blessed object so we can do stuff with it
# Save the clone level (so we can check later if we've been cloned)

    my $class = shift;
    my $self = bless {},$class;
    $self->{'CLONE'} = $CLONE;

# Create the control channel
# Create the data channel
# Store references to these inside the object
# Start the thread, save the thread id on the fly

    my $control : shared = '';
    my $data : shared;
    @$self{qw(control data)} = (\$control,\$data);
    $self->{'tid'} = threads->new( \&_handler,$self )->tid;

# Create the ordinal number channel (reserve 0 for special purposes)
# Save reference to it inside the object
# Wait for the thread to take control
# Return with the instantiated object

    my $ordinal : shared = 1;
    $self->{'ordinal'} = \$ordinal;
    threads->yield while defined($control);
    $self;
} #new

#---------------------------------------------------------------------------

# instance methods

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 thread encapsulated in object

sub thread { threads->object( shift->{'tid'} ) } #thread

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 thread id of thread encapsulated in object

sub tid { shift->{'tid'} } #tid

#---------------------------------------------------------------------------

# internal methods

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 subroutine to execute inside the thread
#      3..N data to be sent (optional)
# OUT: 1..N result of action (optional)

sub _handle {

# Obtain the object
# Obtain the subroutine
# Obtain the references to the control and data fields
# Create frozen version of the data

    my $self = shift;
    my $sub = shift;
    my ($control,$data) = @$self{qw(control data)};
    my $frozen = _freeze( \@_ );

# Initialize the counter
# While we haven't got access to the handler
#  Give up this timeslice if we tried this before
#  Wait for access to the belt
#  Reloop if we got access here before the handler was waiting again

    my $tries;
    AGAIN: while (1) {
        threads->yield if $tries++;
        {lock( $control );
         next AGAIN if defined( $$control );

# Set the data to be passed
# Mark there is something being done now
# Signal the handler to do its thing

         $$data = $frozen;
         $$control = $sub;
         threads::shared::cond_signal( $control );
        } #$control

#  Wait for the handler to be done with this request
#  Obtain local copy of result
#  Indicate that the caller is ready with the request
#  Return result of the action

        threads->yield while defined( $$control );
        $frozen = $$data;
        undef( $$data );
        return _thaw( $frozen );
    }
} #_handle

#---------------------------------------------------------------------------
#  IN: 1 instantiated object

sub _handler {

# Obtain the object
# Obtain the references to the fields that we need
# Subroutine to execute
# Thread local list of tied objects
# Ordinal number of object to which it is tied

    my $self = shift;
    my ($control,$data) = @$self{qw(control data)};
    my $sub;
    my @object;
    my $ordinal;

# Initialize general dispatch
# Local copy of object to use
# Local copy of code to execute
# Frozen copy of no values

    my %dispatch;
    my $object;
    my $code;
    my $undef = _freeze( [undef] );

# Initialize the tie() dispatch hash

    my %tie_dispatch = (
     TIESCALAR => sub {my $scalar; tie $scalar, shift, @_},
     TIEARRAY  => sub {my @array; tie @array, shift, @_ },
     TIEHASH   => sub {my %hash; tie %hash, shift, @_ },
     TIEHANDLE => sub {tie *CLONE, shift, @_ }
    );

# Take control of the belt
# Indicate to the world we've taken control

    lock( $control );
    undef( $$control );

# While we're accepting things to do
#  Wait for something to do
#  Outloop when we're done

    while (1) {
        threads::shared::cond_wait( $control );
        last unless $$control;

#  Obtain the name of the subroutine to execute
#  Obtain the ordinal number of the object to execute + data to be sent
#  If we have a tie action
#   If it is a known tie method
#    Perform the appropriate tieing subroutine
#   Else
#    Die, we don't know how to handle this

        {no strict 'refs';
	 $sub = $$control;
         ($ordinal,@_) = _thaw( $$data );
         if ($sub =~ m#^(.*)::(TIE\w+)$#) {
             if ($sub = $tie_dispatch{ $2 }) {
                 $object[$ordinal] = $sub->( $1,@_ );
             } else {
                 die "Don't know how to tie with $sub";
             }

#  Elsif there is an object for this ordinal number, saving object on the fly
#   If we have a code reference for this method, saving it on the fly
#   Elseif we haven't checked before
#    Normalize the subroutine name
#    Obtain a code reference for this method on this object if here is one
#   Call the method with the right object and save result

         } elsif ($object = $object[$ordinal]){
             if ($code = $dispatch{$sub}) {
             } elsif( !exists( $dispatch{$sub} ) ) {
                 $sub =~ s#^.*::##;
                 $code = $dispatch{$sub} = $object->can( $sub );
             }
             $$data = $code ? _freeze( [$code->( $object,@_ )] ) : $undef;

#  Else (we don't have an object yet)
#   Just call the sub routine

         } else {
             $$data = _freeze( [$sub->( @_ )] )
         }
	} #no strict refs

#  Mark the data to be ready for usage
#  Wait until the caller has taken it

	undef( $$control );
        threads->yield while defined( $$data );
    }
} #_handler

#---------------------------------------------------------------------------
#  IN: 1 reference to data structure to freeze
# OUT: 1 frozen scalar

sub _freeze {

# If we have at least one element in the list
#  For all of the elements
#   Return truly frozen version if something special
#  Return the values contatenated with null bytes
# Else (empty list)
#  Return undef value

    if (@{$_[0]}) {
        foreach (@{$_[0]}) {
            return Storable::freeze( $_[0] ) if !defined() or ref() or m#\0#;
        }
        return join( "\0",@{$_[0]} );
    } else {
        return;
    }
} #_freeze

#---------------------------------------------------------------------------
#  IN: 1 frozen scalar to defrost
# OUT: 1..N thawed data structure

sub _thaw {

# Return now if nothing to return or not interested in result

    return unless defined( $_[0] ) and defined( wantarray );

# If we're interested in a list
#  Return thawed list from frozen info if frozen
#  Return list split from a normal string
# Elseif we have frozen stuff (and we want a scalar)
#  Thaw the list and return the first element
# Else (not frozen and we want a scalar)
#  Look for the first nullbyte and return string until then if found
#  Return the string

    if (wantarray) {
        return @{Storable::thaw( $_[0] )} if unpack( 'l',$_[0] ) == $iced;
        split( "\0",$_[0] )
    } elsif (unpack( 'l',$_[0] ) == $iced) {
        Storable::thaw( $_[0] )->[0];
    } else {
	return $1 if $_[0] =~ m#^([^\0]*)#;
        $_[0];
    }
} #_thaw

#---------------------------------------------------------------------------

# standard Perl features

#---------------------------------------------------------------------------

# Increment the current clone value (mark this as a cloned version)

sub CLONE { $CLONE++ } #CLONE

#---------------------------------------------------------------------------
#  IN: 1 instantiated object

sub DESTROY {

# Obtain the object
# Return if we're not in the originating thread
# Shut the thread down
# And wait for it to be actually finished

    my $self = shift;
    return if $self->{'CLONE'} != $CLONE;
    $self->_handle;
    $self->thread->join;
} #DESTROY

#---------------------------------------------------------------------------
#  IN: 1 module to load
#      2..N any parameters to import

sub USE {

# Obtain the class
# Create a copy for the filename
# Make sure we have a correct filename
# Load the module file
# Execute import routine (if any)

    my $class = shift;
    my $file = $class;
    $file =~ s#::#/#g; $file .= '.pm';
    require $file;
    $class->import( @_ );
} #USE

#---------------------------------------------------------------------------

__END__

=head1 NAME

Thread::Tie::Thread - create threads for tied variables

=head1 DESCRIPTION

Helper class for L<Thread::Tie>.  See documentation there.

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 COPYRIGHT

Copyright (c) 2002 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Thread::Tie>.

=cut

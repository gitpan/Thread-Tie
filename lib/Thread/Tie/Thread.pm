package Thread::Tie::Thread;

# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our $VERSION : unique = '0.04';
use strict;

# Make sure we can do threads
# Make sure we can do shared threads
# Make sure we can serialize with freeze() and thaw()

use threads ();
use threads::shared ();
use Thread::Serialize;

# Thread local list of tied objects
# Clone detection logic

my @OBJECT;
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
#  IN: 1 instantiated object

sub shutdown {

# Obtain the object
# Return if we're not in the originating thread
# Return now if already shut down

    my $self = shift;
    return if $self->{'CLONE'} != $CLONE;
    return unless defined( $self->{'tid'} );

# Shut the thread down
# Wait for it to be actually finished
# Mark the thread as shut down

    $self->_handle;
    $self->thread->join;
    undef( $self->{'tid'} );
} #shutdown

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
    my $frozen = freeze( @_ );

# Initialize the tries counter
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
        return thaw( $frozen );
    }
} #_handle

#---------------------------------------------------------------------------
#  IN: 1 instantiated object

sub _handler {

# Obtain the object
# Obtain the references to the fields that we need
# Subroutine to execute
# Ordinal number of object to which it is tied

    my $self = shift;
    my ($control,$data) = @$self{qw(control data)};
    my $sub;
    my $ordinal;

# Initialize general dispatch

    my %dispatch = (
     EVAL    => \&doEVAL,
     UNTIE   => \&doUNTIE,
     USE     => \&doUSE,
    );

# Local copy of object to use
# Local copy of code to execute
# Frozen copy of no values

    my $object;
    my $code;
    my $undef = freeze( undef );

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

        $sub = $$control;
        ($ordinal,@_) = thaw( $$data );

#  If we have an object, obtaining local copy of object on the fly
#   If we have a code reference for this method, saving it on the fly
#   Elseif we haven't checked before
#    Normalize the subroutine name
#    Obtain a code reference for this method on this object if here is one
#   Call the method with the right object and save result

        if ($object = $OBJECT[$ordinal]) {
            if ($code = $dispatch{$sub}) {
            } elsif( !exists( $dispatch{$sub} ) ) {
                (my $localsub = $sub) =~ s#^.*::##;
                $code = $dispatch{$sub} = $object->can( $localsub );
            }
            $$data = $code ? freeze( $code->( $object,@_ ) ) : $undef;

#  Elseif we have a tie action
#   If it is a known tie method
#    Perform the appropriate tieing subroutine
#   Else (unknown tie method)
#    Die, we don't know how to handle this

        } elsif ($sub =~ m#^(.*)::(TIE\w+)$#) {
            if ($sub = $tie_dispatch{ $2 }) {
                $OBJECT[$ordinal] = $sub->( $1,@_ );
            } else {
                die "Don't know how to TIE with $sub";
            }

#  Elseif we're attempting to destroy without an object
#   Just set an undefined results (assume it is DESTROY after untie()
#  Elseif it is a known subroutine that is allowed
#   Execute the action, assume it's a special startup function
#  Else
#   Die now, this is strange!

        } elsif ($sub =~ m#DESTROY$#) {
            $$data = $undef;
        } elsif ($code = $dispatch{$sub}) {
            $$data = $code->( undef,@_ );
        } else {
            die "Attempting to $sub without an object at $ordinal\n";
        }

#  Mark the data to be ready for usage
#  Wait until the caller has taken it

	undef( $$control );
        threads->yield while defined( $$data );
    }
} #_handler

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

    my $self = shift;
    return if $self->{'CLONE'} != $CLONE;
    $self->shutdown;
} #DESTROY

#---------------------------------------------------------------------------
#  IN: 1 object (ignored)
#      2 code to eval

sub doEVAL { eval( $_[1] ) } #doEVAL

#---------------------------------------------------------------------------
#  IN: 1 object
#      2 ordinal number of object to remove

sub doUNTIE {

# Obtain the object
# If we can destroy the object, obtaining code ref on the fly
#  Perform whatever needs to be done to destroy
# Kill all references to the variable

    my $object = shift;
    if (my $code = $object->can( 'DESTROY' )) {
        $code->( $object );
    }
    undef( $OBJECT[shift] );
} #doUNTIE

#---------------------------------------------------------------------------
#  IN: 1 object (ignored)
#      2 module to load
#      3..N any parameters to import

sub doUSE {

# Remove object
# Obtain the class
# Create a copy for the filename
# Make sure we have a correct filename
# Load the module file
# Execute import routine (if any)

    shift;
    my $class = shift;
    my $file = $class;
    $file =~ s#::#/#g; $file .= '.pm';
    require $file;
    $class->import( @_ );
} #doUSE

#---------------------------------------------------------------------------

__END__

=head1 NAME

Thread::Tie::Thread - create threads for tied variables

=head1 SYNOPSIS

    use Thread::Tie; # use as early as possible for maximum memory savings

    my $tiethread = Thread::Tie::Thread->new;
    tie stuff, 'Thread::Tie', {thread => $thread};

    my $tid = $tiethread->tid;        # thread id of tied thread
    my $thread = $tiethread->thread;  # actual "threads" thread
    $tiethread->shutdown;             # shut down specific thread

=head1 DESCRIPTION

                  *** A note of CAUTION ***

 This module only functions on Perl versions 5.8.0 and later.
 And then only when threads are enabled with -Dusethreads.  It
 is of no use with any version of Perl before 5.8.0 or without
 threads enabled.

                  *************************

The Thread::Tie::Thread module is a helper class for the L<Thread::Tie>
module.  It is used to create the thread in which the actual code, to which
variables are tied with the Thread::Tie class, is located.

Please see the documentation of the L<Thread::Tie> module for more
information.

=head1 CLASS METHODS

There is only one class method.

=head2 new

 my $tiethread = Thread::Tie::Thread->new;

The "new" class method returns an instantiated object that can be specified
with the "thread" field when tie()ing a variable.

=head1 OBJECT METHODS

The following object methods are available for the instantiated
Thread::Tie::Thread object.

=head2 tid

 my $tid = $tiethread->tid;

The "tid" object method returns the thread id of the actual L<threads>
thread that is being used.

=head2 thread

 my $thread = $tiethread->thread;

The "thread" object method returns the actual L<threads> thread object that
is being used.

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 COPYRIGHT

Copyright (c) 2002 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Thread::Tie>, L<threads>.

=cut

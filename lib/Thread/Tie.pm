package Thread::Tie;

# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our $VERSION : unique = '0.01';
use strict;

# Use the thread creation logic

use Thread::Tie::Thread ();

# Default thread to be used
# Clone detection logic

my $THREAD;
my $CLONE = 0;

# Satisfy -require-

1;

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 module to which variable is tied in thread

sub module { shift->{'module'} } #module

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 reference to semaphore for lock()

sub semaphore { shift->{'semaphore'} } #semaphore

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
# OUT: 1 thread object hosting this variable

sub thread { shift->{'thread'} } #thread

#---------------------------------------------------------------------------

# internal methods

#---------------------------------------------------------------------------
#  IN: 1 class for which to bless
#      2 default module to tie to in thread
#      4 reference to hash containing parameters
#      5..N any parameters
# OUT: 1 instantiated object

sub _tie {

# Obtain the class
# Obtain the default module
# Create the tie subroutine name
# Obtain the hash reference
# Make it a blessed object

    my $class = shift;
    my $default_module = shift;
    my $tie_sub = 'TIE'.uc($default_module);
    my $self = shift || {};
    bless $self,$class;

# Set the thread that will be used
# Set the module that should be used to tie to
# Save the clone level

    my $thread = $self->{'thread'} ||= $THREAD ||= ($class.'::Thread')->new;
    my $module = $self->{'module'} ||= $class.'::'.$default_module;
    $self->{'CLONE'} = $CLONE;

# Obtain the reference to the thread shared ordinal area
# Make sure we're the only one doing stuff now
# Save the current ordinal number on the tied object, incrementing on the fly
# Make sure that the module is available in the thread
# Handle the tie request in the thread

    my $ordinal = $thread->{'ordinal'};
    {lock( $ordinal );
     $self->{'ordinal'} = $$ordinal++;
     $self->_handle( 'USE', $module );
     $self->_handle( $module.'::'.$tie_sub, @_ );
    } #$ordinal

# Create a semaphore for external locking
# Save a reference to it in the object
# Return the instantiated object

    my $semaphore : shared;
    $self->{'semaphore'} = \$semaphore;
    $self;
} #_tie

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2 subroutine to execute inside the thread
#      3..N data to be sent (optional)
# OUT: 1..N result of action (optional)

sub _handle {

# Obtain the object
# Handle it using the thread object

    my $self = shift;
    $self->{'thread'}->_handle( shift,$self->{'ordinal'},@_ );
} #_handle

#---------------------------------------------------------------------------

# standard Perl features

#---------------------------------------------------------------------------

# Increment the current clone value (mark this as a cloned version)

sub CLONE { $CLONE++ } #CLONE

#---------------------------------------------------------------------------
#  IN: 1 instantiated object
#      2..N input parameters
# OUT: 1..N output parameters

sub AUTOLOAD {

# Obtain the object
# Obtain the subroutine name
# Handle the command with the appropriate data

    my $self = shift;
    (my $sub = $Thread::Tie::AUTOLOAD) =~ s#^.*::#$self->{'module'}::#;
    $self->_handle( $sub,@_ );
} #AUTOLOAD

#---------------------------------------------------------------------------
#  IN: 1 instantiated object

sub DESTROY {

# Obtain the object
# Return if we're not in the originating thread
# Handle the command with the appropriate data

    my $self = shift;
    return if $self->{'CLONE'} != $CLONE;
    $self->_handle( $self->{'module'}.'::DESTROY',@_ );
} #DESTROY

#---------------------------------------------------------------------------
#  IN: 1 class for which to bless
#      2 reference to hash containing parameters
#      3 initial value of scalar
# OUT: 1 instantiated object

sub TIESCALAR { shift->_tie( 'Scalar',@_ ) } #TIESCALAR

#---------------------------------------------------------------------------
#  IN: 1 class for which to bless
#      2 reference to hash containing parameters
# OUT: 1 instantiated object

sub TIEARRAY { shift->_tie( 'Array',@_ ) } #TIEARRAY

#---------------------------------------------------------------------------
#  IN: 1 class for which to bless
#      2 reference to hash containing parameters
# OUT: 1 instantiated object

sub TIEHASH { shift->_tie( 'Hash',@_ ) } #TIEHASH

#---------------------------------------------------------------------------
#  IN: 1 class for which to bless
#      2 reference to hash containing parameters
#      3..N any parameters passed to open()
# OUT: 1 instantiated object

sub TIEHANDLE { shift->_tie( 'Handle',@_ ) } #TIEHANDLE

#---------------------------------------------------------------------------

__END__

=head1 NAME

Thread::Tie - tie variables into a thread of their own

=head1 SYNOPSIS

    use Thread::Tie;

    # use default thread + tieing + create thread when needed
    tie $scalar, 'Thread::Tie';
    tie @array, 'Thread::Tie';
    tie %hash, 'Thread::Tie';
    
    # create a thread beforehand
    my $thread = Thread::Tie::Thread->new;
    tie $scalar, 'Thread::Tie', {thread => $thread};

    # use alternate implementation
    tie $scalar, 'Thread::Tie',
     { thread => $thread, module => 'Own::Tie::Implementation' };

    # initialize right away
    tie $scalar, 'Thread::Tie', {}, 10;
    tie @array, 'Thread::Tie', {}, qw(a b c);
    tie %hash, 'Thread::Tie', {}, (a => 'A', b => 'B', c => 'C');

=head1 DESCRIPTION

                  *** A note of CAUTION ***

 This module only functions on Perl versions 5.8.0 and later.
 And then only when threads are enabled with -Dusethreads.  It
 is of no use with any version of Perl before 5.8.0 or without
 threads enabled.

                  *************************

The standard shared variable scheme used by Perl, is based on tie-ing the
variable to some very special dark magic.  This dark magic ensures that
shared variables, which are copied just as any other variable when a thread
is started, update values in all of the threads where they exist as soon as
the value of a shared variable is changed.

Needless to say, this could use some improvement.

The Thread::Tie module is a proof-of-concept implementation of another
approach to shared variables.  Instead of having shared variables exist
in all the threads from which they are accessible, shared variable exist
as "normal", unshared variables in a seperate thread.  Only a tied object
exists in each thread from which the shared variable is accesible.

Through the use of a client-server model, any thread can fetch and/or update
variables living in that thread.  This client-server functionality is hidden
under the hood of tie().  So you could say that one dark magic (the current
shared variables implementation) is replaced by another dark magic.

I see the following advantages to this approach:

=over 2

=item memory usage

Shared variables in this approach are truly shared.  The value of a variable
only exists once in memory.  This implementation also circumvents the memory
leak that currently (threads::shared version 0.90) plagues any shared array
or shared hash access.

=item tieing shared variables

Because the current implementation uses tie-ing, you can B<not> tie a shared
variable.  The same applies for this implementation you might say.  However,
it B<is> possible to specify a non-standard tie implementation for use
B<within> the thread.  So with this implementation you B<can> C<tie()> a
shared variable.  So you B<could> tie a shared hash to a DBM file à la
dbmopen() with this module.

=back

Of course there are disadvantages to this approach:

=over 2

=item pure perl implementation

This module is currently a pure perl implementation.  This is ok for a proof
of concept, but may need re-implementation in pure XS or in Inline::C for
production use.

=item tradeoff between cpu and memory

This implementation currently uses (much) more cpu than the standard shared
variables implementation.  Whether this would still be true when re-implemented
in XS or Inline::C, remains to be seen.

=back

=head1 IMPROVEMENTS

It should already be possible to tie handles, but this hasn't been tested
yet.

It would be nice if you could start a bare thread, i.e. like when you start
a script.  Problem though is how are you going to communicate with that
thread?

Examples should be added.

A more extensive test-suite should be added.

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 COPYRIGHT

Copyright (c) 2002 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<threads>.

=cut

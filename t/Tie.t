BEGIN {				# Magic Perl CORE pragma
    if ($ENV{PERL_CORE}) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use Test::More tests => 52;

use_ok( 'Thread::Tie::Thread' );
can_ok( 'Thread::Tie::Thread',qw(
 new
 thread
 tid
) );

use_ok( 'Thread::Tie' );
can_ok( 'Thread::Tie',qw(
 module
 semaphore
 TIESCALAR
 TIEARRAY
 TIEHASH
 TIEHANDLE
 thread
) );

#== SCALAR =========================================================

my $tied = tie my $scalar, 'Thread::Tie',{},10;
isa_ok( $tied,'Thread::Tie',		'check tied object type' );

isa_ok( $tied->thread,'Thread::Tie::Thread','check thread object type' );
cmp_ok( $tied->thread->tid,'==',1,	'check tid of thread' );
isa_ok( $tied->thread->thread,'threads','check thread object type' );
isa_ok( $tied->semaphore,'SCALAR',	'check semaphore type' );

cmp_ok( $scalar,'==',10,		'check scalar numerical fetch' );
$scalar++;
cmp_ok( $scalar,'==',11,		'check scalar increment' );
$scalar = 'Apenootjes';
is( $scalar,'Apenootjes',		'check scalar fetch' );

threads->new( sub {$scalar = 'from thread'} )->join;
is( $scalar,'from thread',		'check scalar fetch' );

#== ARRAY ==========================================================

$tied = tie my @array, 'Thread::Tie',{},qw(a b c);
isa_ok( $tied,'Thread::Tie',		'check tied object type' );
is( join('',@array),'abc',		'check array fetch' );

push( @array,qw(d e f) );
is( join('',@array),'abcdef',		'check array fetch' );

threads->new( sub {push( @array,qw(g h i) )} )->join;
is( join('',@array),'abcdefghi',	'check array fetch' );

shift( @array );
is( join('',@array),'bcdefghi',		'check array fetch' );

unshift( @array,'a' );
is( join('',@array),'abcdefghi',	'check array fetch' );

pop( @array );
is( join('',@array),'abcdefgh',		'check array fetch' );

push( @array,'i' );
is( join('',@array),'abcdefghi',	'check array fetch' );

splice( @array,3,3 );
is( join('',@array),'abcghi',		'check array fetch' );

splice( @array,3,0,qw(d e f) );
is( join('',@array),'abcdefghi',	'check array fetch' );

splice( @array,0,3,qw(d e f) );
is( join('',@array),'defdefghi',	'check array fetch' );

delete( $array[0] );
is( join('',@array),'efdefghi',		'check array fetch' );

@array = qw(a b c d e f g h i);
is( join('',@array),'abcdefghi',	'check array fetch' );

cmp_ok( $#array,'==',8,			'check size' );
ok( exists( $array[8] ),		'check whether array element exists' );
ok( !exists( $array[9] ),		'check whether array element exists' );

$#array = 10;
cmp_ok( scalar(@array),'==',11,		'check number of elements' );
is( join('',@array),'abcdefghi',	'check array fetch' );

ok( !exists( $array[10] ),		'check whether array element exists' );
$array[10] = undef;
ok( exists( $array[10] ),		'check whether array element exists' );

ok( !exists( $array[11] ),		'check whether array element exists' );
ok( !defined( $array[10] ),		'check whether array element defined' );
ok( !defined( $array[11] ),		'check whether array element defined' );
cmp_ok( scalar(@array),'==',11,		'check number of elements' );

@array = ();
cmp_ok( scalar(@array),'==',0,		'check number of elements' );
is( join('',@array),'',			'check array fetch' );

#== HASH ===========================================================

$tied = tie my %hash, 'Thread::Tie',{},(a => 'A');
isa_ok( $tied,'Thread::Tie',		'check tied object type' );
is( $hash{'a'},'A',			'check hash fetch' );

$hash{'b'} = 'B';
is( $hash{'b'},'B',			'check hash fetch' );

is( join('',sort keys %hash),'ab',	'check hash keys' );

ok( !exists( $hash{'c'} ),		'check existence of key' );
threads->new( sub { $hash{'c'} = 'C' } )->join;
ok( exists( $hash{'c'} ),		'check existence of key' );
is( $hash{'c'},'C',			'check hash fetch' );

is( join('',sort keys %hash),'abc',	'check hash keys' );

my %otherhash = %hash;
is( join('',sort keys %otherhash),'abc','check hash keys' );

my @list;
while (my ($key,$value) = each %hash) { push( @list,$key,$value ) }
is( join('',sort @list),'ABCabc',	'check all eaches' );

delete( $hash{'b'} );
is( join('',sort keys %hash),'ac',	'check hash keys' );

%hash = ();
cmp_ok( scalar(keys %hash),'==',0,	'check number of elements' );
is( join('',keys %hash),'',		'check hash fetch' );

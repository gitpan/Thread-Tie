require 5.008;
use threads (); # just to force breakage if threads are not available
use ExtUtils::MakeMaker;

WriteMakefile (
 NAME		=> "Thread::Tie",
 ($[ >= 5.005) ?
 (AUTHOR	=> 'Elizabeth Mattijsen (liz@dijkmat.nl)',
  ABSTRACT	=> 'tie variables into a thread of their own') : (),
 VERSION_FROM	=> 'lib/Thread/Tie.pm',
 PREREQ_PM	=> {
		   Storable => 0,
                   },
);

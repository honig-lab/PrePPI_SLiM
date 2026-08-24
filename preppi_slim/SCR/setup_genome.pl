#!/usr/bin/perl

use strict;
use warnings;

use MODS::Globals;
use MODS::Genome;
use MODS::Pipeline;
# use MODS::Methods;
use Getopt::Std;

my $PGM = $0;                   #name of program
$PGM =~ s#.*/##;     
my $usage = <<USAGE;
USAGE:
        $PGM genome_name -f sequences.fa [-d] [-q] 
        Parameters:
		
		genome_name: Name of the genome. 
		-f sequences.fa: Fasta file with the sequences of the target proteins
		-d Toggle on debug mode.
                -q Set up the Pipeline, but don't qsub.             
USAGE

if(@ARGV<1 ) {
  print STDERR $usage ;
  exit(-1);
  }

my $gname=shift;

my %opts;
getopts('dqf:m:',\%opts);
my $debug=$opts{d} ? 'yes' : 'no';
my $execute=$opts{q} ? 'no' : 'yes' ;

die("You must specify a fasta file containing at least one sequence") if not defined $opts{f};

my $genome=new MODS::Genome(gname => $gname );
$genome->init($opts{f}) if defined $opts{f};

my $pipeline=new MODS::Pipeline(name=>"Setup",gname=>$gname,debug=>$debug);
unlink $pipeline->{stepsfn}, "$pipeline->{stepsfn}.focus";
$pipeline->add_step("IUPRED");

exit(0) if defined $opts{q};
$pipeline->qsub();

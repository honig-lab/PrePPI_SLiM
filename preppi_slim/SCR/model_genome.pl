#!/usr/bin/perl

use strict;
use warnings;

use MODS::Globals;
use MODS::Genome;
use MODS::Pipeline;
use MODS::Methods;
use Getopt::Std;

my $PGM = $0;                   #name of program
$PGM =~ s#.*/##;     
my $usage = <<USAGE;
USAGE:
        $PGM genome_name [-f sequences.fa] [-p] [-d] [-m MDL|SM|NS]
        Parameters:
		
		-genome_name: Name of the genome. 
		-f sequences.fa: Fasta file with the sequences of the target proteins
		-d Toggle on debug mode.
		-p Parse the sequences into domains.
		-m Run only certain steps (MDL=modeling, SM=structure-based scores, NS=non-structural scores).
                -q Set up the Pipeline, but don't qsub.             
USAGE

if(@ARGV<1 ) {
  print STDERR $usage ;
  exit(-1);
  }

my $gname=shift;

my %opts;
getopts('pdqf:m:',\%opts);
my $parse=$opts{p} ? 'yes': 'no';
my $debug=$opts{d} ? 'yes' : 'no';
my $focus=$opts{m} ? $opts{m} : "all";
my $execute=$opts{q} ? 'no' : 'yes' ;

my $genome=new MODS::Genome(gname => $gname );
$genome->init($opts{f},parse=>$parse) if defined $opts{f};

my $pipeline=new MODS::Pipeline(name=>"Model",gname=>$gname,debug=>$debug);
$pipeline->set_targets($opts{t}) if defined $opts{t};
`rm -rf $pipeline->{stepsfn} $pipeline->{stepsfn}.focus`;
$pipeline->add_step("BLAST_PDB_it1_m");
$pipeline->add_step("NEST_blast");
$pipeline->add_step("IUPRED");
$pipeline->add_step("HHBLITS_m");
$pipeline->add_step("NEST_m");
$pipeline->add_step("Skan_compact");

exit(0) if defined $opts{q};
$pipeline->qsub();


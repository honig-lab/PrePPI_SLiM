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
        $PGM genome_name [-d]
        Parameters:
		
		-genome_name: Name of the genome. 
		-d Toggle on debug mode.
USAGE

if(@ARGV<1 ) {
  print STDERR $usage ;
  exit(-1);
  }

my $gname=shift;

my %opts;
getopts('pdqtf:m:a:',\%opts);
my $debug=$opts{d} ? 'yes' : 'no';

my $genome=new MODS::Genome(gname => $gname );

my $pipeline=new MODS::Pipeline(name=>"run_elm",gname=>$gname,debug=>$debug);
$pipeline->set_targets($opts{t}) if defined $opts{t};

# Disorder
$pipeline->add_step("IUPRED");

# ELM protein peptide
$pipeline->add_step("FindMotifs_ELM");
$pipeline->add_step("FindPRDs_ELM");
$pipeline->add_step("Gopher");
$pipeline->add_step("MuscleG");
$pipeline->add_step("MotifConsv");
$pipeline->add_step("ProtPeptide_ELM");

$pipeline->qsub();


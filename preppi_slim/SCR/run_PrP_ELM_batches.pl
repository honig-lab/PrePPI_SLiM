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
        $PGM genome_name [-g genome_name2] [-d]
        Parameters:
		
		-genome_name: Name of the genome.
		-g: Calculates ProtPeptide_ELM.txt between genome_name and genome_name2.
		-d: Toggle on debug mode.
USAGE

if(@ARGV<1 ) {
  print STDERR $usage ;
  exit(-1);
  }

my $gname=shift;

my %opts;
getopts('pdqtf:g:m:a:',\%opts) or die $usage;

my $debug=$opts{d} ? 'yes' : 'no';
my $parms="";
if(defined $opts{g}) {
    $parms = "external,$opts{g}";
}

my $genome=new MODS::Genome(gname => $gname );

my $pipeline=new MODS::Pipeline(name=>"ProtPeptide_ELM",gname=>$gname,debug=>$debug);
# $pipeline->set_targets($opts{t}) if defined $opts{t};

$pipeline->add_step("ProtPeptide_ELM",$parms);

$pipeline->qsub();


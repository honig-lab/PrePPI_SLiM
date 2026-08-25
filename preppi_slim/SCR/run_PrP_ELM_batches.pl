#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use MODS::Globals;
use MODS::Genome;
use MODS::Pipeline;
use MODS::Methods;

my $usage = <<'USAGE';
Usage:
  run_PrP_ELM_batches.pl genome1 [options]

Options:
  -g, --genome2 NAME       Partner genome (default: genome1)
  -O, --orientation ROLE   Role of genome1: motif or prd (default: motif)
  -r, --reverse            Alias for --orientation prd
  -d, --debug              Retain per-task scheduler logs
  -q, --no-submit          Configure without submitting
  -h, --help               Show this help

Orientations:
  motif  SLiMs from genome1 are compared with PRDs from genome2.
  prd    PRDs from genome1 are compared with SLiMs from genome2; results still
         remain under genome1, grouped by its PRD-side protein IDs.
USAGE

my $gname = shift @ARGV;
die $usage if not defined $gname;

my ($genome2, $reverse, $debug, $no_submit, $help);
my $orientation = 'motif';
GetOptions(
    'g|genome2=s'     => \$genome2,
    'O|orientation=s' => \$orientation,
    'r|reverse'       => \$reverse,
    'd|debug'         => \$debug,
    'q|no-submit'     => \$no_submit,
    'h|help'          => \$help,
) or die $usage;
die $usage if $help;

$orientation = 'prd' if $reverse;
die "--orientation must be motif or prd\n"
    if $orientation ne 'motif' and $orientation ne 'prd';
$genome2 //= $gname;

my $genome = MODS::Genome->new(gname => $gname);
die "Genome does not exist: $genome->{home}\n" if not -d $genome->{home};
my $partner = MODS::Genome->new(gname => $genome2);
die "Partner genome does not exist: $partner->{home}\n" if not -d $partner->{home};

(my $safe_partner = $genome2) =~ s/[^A-Za-z0-9_.-]+/_/g;
my $run_tag = "${orientation}_$safe_partner";
my $pipeline_name = "ProtPeptide_ELM_$run_tag";
my $pipeline = MODS::Pipeline->new(
    name  => $pipeline_name,
    gname => $gname,
    debug => $debug ? 'yes' : 'no',
);
unlink $pipeline->{stepsfn}, "$pipeline->{stepsfn}.focus";

my $parameters = join ',',
    external    => $genome2,
    orientation => $orientation,
    run_tag     => $run_tag;
$pipeline->add_step('ProtPeptide_ELM', $parameters);
$pipeline->qsub($no_submit ? 'no' : 'yes');

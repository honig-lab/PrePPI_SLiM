#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Std;

use MODS::Methods;

if(!@ARGV) {
  print STDERR "Usage: process_method.pl pipeline_name name step_name\n";
  exit(-1);
  }

my $pname=shift;
my $gname=shift;
my $sname=shift;
my $tgts=shift;
my $dbg=shift;

my $genome=new MODS::Genome(gname=>$gname);
my $pipeline=new MODS::Pipeline(name=>$pname,gname=>$gname);

sleep(300);
my @ids=`cut -f 1 $tgts`;
foreach(@ids) {
    print STDERR $_;
    chop;
    no strict 'refs';
    my $mname="MODS::$sname";
    my $method=$mname->new(gname=>$gname,gid=>$_,step_parameters=>$pipeline->step_arg($sname));
    chdir $method->{wrkdir} or die "Could not change directory to $method->{wrkdir}";
    $method->process();
    `touch $method->{wrkdir}/process; chmod g+rw $method->{wrkdir}/process` if not -e "$method->{wrkdir}/process";
}

my @jobsf=`ls -f $pipeline->{pipedir} | grep $tgts | egrep -v "time|active"`;
for(@jobsf) { 
    chomp; 
    print STDERR `mv $pipeline->{pipedir}/$_ $pipeline->{pipedir}/completed`; 
    print STDERR "Processing target: $_\n"; # AS: Debugging statement
    }

print STDERR `rm -rf $pipeline->{pipedir}/$tgts.active`;

#!/usr/bin/perl

use strict;
use warnings;
use sigtrap 'handler', \&sig_handler, 'normal-signals';
use Getopt::Std;

use MODS::Methods;

if(!@ARGV) {
  print STDERR "Usage:  run_method.pl pipeline_name genome_name step_name gname sge_task_id\n";
  exit(-1);
  }

my $pname=shift;
my $gname=shift;
my $sname=shift;
my $tgtlst=shift;
my $taskid=shift;
my $quiet=shift;

my $pipeline=new MODS::Pipeline(name=>$pname,gname=>$gname);
my $genome=new MODS::Genome(gname=>$gname);
$tgtlst=`readlink -f $tgtlst`;
chomp $tgtlst;
my $jobdata=`perl -ne '(\$gid,\$nj)=split; if ($taskid<=\$alitot+\$nj) { chop; \$tid=$taskid-\$alitot; print "\$gid\t\$tid"; last; } \$alitot+=(split)[1];' $tgtlst`;
chomp $jobdata;
my ($gid,$sge_idx)=split(/\t/,$jobdata);
no strict 'refs';
my $mname="MODS::$sname";
my $method=$mname->new(gname=>$gname,gid=>$gid,step_parameters=>$pipeline->step_arg($sname));
$method->{sge_task_id}=$sge_idx if defined $method->{sge_input};
$method->{quiet}='no' if defined $quiet;
my $adir="$tgtlst.active";
$method->{active}="$adir/RUN.$gid.$sge_idx";
`touch $method->{active}; chmod g+rw $method->{active}` if -d "$tgtlst.active";
`touch $adir/LAST; chmod g+rw $adir/LAST` if defined $ENV{SGE_TASK_LAST} and $taskid==$ENV{SGE_TASK_LAST} and -d "$tgtlst.active";
my $tm=$pipeline->time();
chdir $method->{wrkdir} or die "Could not change directory to $method->{wrkdir}";
my $start=time();
$method->prep() if defined $quiet;
$method->run();
my $elapsed=time()-$start;
`touch $method->{wrkdir}/done; chmod g+rw $method->{wrkdir}/done`;
exit if not -d "$tgtlst.active";
`touch $adir/FREE.$gid.$sge_idx; chmod g+rw $adir/FREE.$gid.$sge_idx`;
my $ntasks=$method->count_tasks();
open(TIMFH,">$adir/TM.$gid.$sge_idx");
print TIMFH "$gid\t$sge_idx\t$elapsed\t$ntasks\n";
close TIMFH;
`chmod g+rw $adir/TM.$gid.$sge_idx`;
`echo "$tm" > $method->{wrkdir}/done; chmod g+rw $method->{wrkdir}/done`;
$tm=$pipeline->time();



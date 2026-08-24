#!/usr/bin/perl

use MODS::Globals;
use strict;
use warnings;
use Getopt::Std;
use MODS::Methods;

$|++;

if(@ARGV>4) {
  print STDERR "Usage:  run_pipeline.pl pipeline_name genome_name [-d]\n";
  exit(-1);
  }

my $pname=shift;
my $gname=shift;

my %opts;
getopts('dm:',\%opts);
my $debug='no';
$debug='yes' if $opts{d};

my $pipeline=new MODS::Pipeline(name=>$pname,gname=>$gname,debug=>$debug);
chdir $pipeline->{pipedir}
    or die "Could not change directory to $pipeline->{pipedir}: $!\n";
my @steps=$pipeline->steps();
my $genome=new MODS::Genome(gname=>$gname);

$pipeline->stage("Pipeline started.");
sleep(5);

my $start=time();
my @running;
@running=`cat $pipeline->{pipedir}/running` if -e "$pipeline->{pipedir}/running";
`rm -rf $pipeline->{pipedir}/running` if -e "$pipeline->{pipedir}/running";
for(@running) { chop; }

my $n=0;
my %jobstat;
if(-e "$pipeline->{pipedir}/$pname.jstat") {
    my @jstat=`cat $pipeline->{pipedir}/$pname.jstat`; 
    for(@jstat) {
        chomp;
        my ($jid,$jinfo)=split(/\t/);
        $pipeline->stage("Reading jobs status: $_.") if not ($n++)%100;
        $jobstat{$jid}=$jinfo;
    }
}

my @jlist;
my @tgts=();
@tgts=`cat targets.lst` if -e "targets.lst";
@tgts=$genome->get_target_list() if not scalar(@tgts);
$n=0;
for(@tgts) { 
    $pipeline->stage("Setting up job queue: $_.") if not ($n++)%100;
    chomp; 
    foreach my $s (@steps) { 
        my $jid="$_:$s";
        my $tm=$pipeline->time();
        $jobstat{$jid}="($tm init)" if not defined $jobstat{$jid};
        push(@jlist,$jid) if not $jobstat{$jid}=~/fail|complete/;  
    }
}


my ($jtot,$nrun,$navail,$jactive)=(0,0,0,0);
my $ccount=0;
my $lasttgt=0;
$lasttgt=`cat $pname.tlast` if -e "$pname.tlast";
my %avail=();
 
if(defined $opts{m}) {
    my $end=$opts{m};
    @jlist=@jlist[0 .. $end];
}

while(1) {

    my $i;
    my $jfail;
    my $updatetm=time();
    for($i=$lasttgt;$i<scalar(@jlist);$i++) {
        last if -e "$pname.pause";
        last if -e "$pname.kill";
        last if -e "$pname.update";
        chomp $jlist[$i];
        my $jid=$jlist[$i];
        if(not $ccount%100) {
            $jactive=0;
            $jfail=0;
            for(@running) {
                my ($jname)=split;  
                if(-d "$jname.active") { 
                    `ls -f $jname.active | grep RUN | wc -l`=~/(\d+)/; $jactive+=$1; 
                    `ls -f $jname.active | grep FAIL | wc -l`=~/(\d+)/; $jfail+=$1;
                    last if $jfail>100;
                }
            }
            $pipeline->stage("Checking job status: $jid, $ccount jobs checked in current block, $jactive active jobs");
        }
        if(not $jid=~/:/) { print STDERR "jid error target $i"; print scalar(@jlist); print "\n"; exit(0); }
        my ($gid,$sname)=split(/:/,$jid);
	# last if $ccount++>2000;
	last if $ccount++>$MAX_ARRAY_VAL;
        my $jinfo="";
        my $tm=$pipeline->time();
        $jobstat{$jid}="($tm init)" if not defined $jobstat{$jid};
        $jinfo=$jobstat{$jid};
        $pipeline->status($gid,$sname,\%jobstat);
        print STDERR "$jid $jobstat{$jid}\n" if $pipeline->{debug} eq 'yes' and $jinfo ne $jobstat{$jid}; 
        if($jobstat{$jid}=~/complete|skip|fail/) { splice(@jlist,$i,1); $i--; next; }
        next if not $jobstat{$jid}=~/ready (\d+) jobs/ or $jobstat{$jid}=~/queued/;
        $jobstat{$jid}.="($tm queued)";
        `echo -e "$gid\t$1" >> $sname.tgt`;
    }

    $ccount=0;
    my $n=0;
    if(-e "$pname.update") {
        for(@running) {
            my ($jname,$nj)=split;
            my $sname=substr($jname,0,length($jname)-10);
            my @tms=`ls -f $jname.active | grep TM | cut -c 4-9;`;
            foreach my $gid (@tms) { 
                chop $gid;
                $pipeline->stage("Checking and saving job status: $gid $sname.") if ($n++)%100==0;
                $pipeline->status($gid,$sname,\%jobstat);
            }
        }
    }

    if($jfail) {
        for(@running) {
            my ($jname,$nj)=split;
            my $sname=substr($jname,0,length($jname)-10);
            my @failj=`ls -f $jname.active | grep FAIL | cut -c 6-100`;
            foreach my $gid (@failj) { 
                chop $gid;
                $pipeline->status($gid,$sname,\%jobstat);
                `rm -r $jname.active/FAIL.$gid`;
            }
        }
    }

    open(CPL,">$pipeline->{pipedir}/$pname.jstat");
    foreach my $k (keys %jobstat) { print CPL "$k\t$jobstat{$k}\n"; }
    close CPL;

    if(-e "$pname.update") { `cp $pname.jstat $pname.jstat.tmp; rm $pname.update`; }
    if(-e "$pname.kill") { $pipeline->stage("Pipeline was killed"); `rm -rf $pname.kill`; exit(0); }
    if(-e "$pname.pause") { `touch $pname.paused`; while(-e "$pname.pause") { sleep(1); } }
    if(time()-$updatetm>30) { `cp $pname.jstat $pname.jstat.tmp`; }
   
    $pipeline->stage("Checking cpu/space usage and submitting jobs.");
    
    $navail=0;
    for(@steps) {
        next if not -e "$_.tgt";
        `wc -l $_.tgt`=~/(\d+)/;
        $navail++ if $1!=0;
    }

    $pipeline->check_active();

    $nrun=0; $jtot=0;
    my @checkrun=@running;
    @running=();
    my %nstep=();
    for(@checkrun) {
        my ($jname,$j)=split;
        my $js=substr($jname,0,length($jname)-10);
        next if not -e "$jname";
        my @jobdat=`squeue --job=$j --noheader --format="%.j" 2> /dev/null`;
        next if not @jobdat;
        push(@running,$_);
        $nstep{$js}++ if not -e "$jname.active/LAST";
        $nrun++ if not -e "$jname.active/LAST";
    }

    for(@steps) {
        my $sname=$_;
        `wc -l $_.tgt`=~/(\d+)/;
        next if $1==0;
        $nstep{$sname}=0 if not defined $nstep{$sname};
        if((($nstep{$sname}<3 and $navail>1) or $navail==1) and $nrun<5) {
            push(@running,$pipeline->submit_block($sname,\%jobstat)); 
            open(RUNFH,">$pipeline->{pipedir}/running");
            for(@running) { print RUNFH "$_\n" }
            close RUNFH;
        } else {
            print STDERR "$sname\nnstep: $nstep{$sname} navail: $navail nrun: $nrun jtot: $jtot\n";
        }
    }

    $lasttgt=$i+1>=scalar(@jlist) ? 0 : $i;

    my $activej=scalar(@jlist);
    print STDERR "Remaining jobs: $activej\n";

    if(not scalar(@jlist)) {
        `cp $pname.jstat $pname.jstat.tmp`;
        my @failed=grep { $jobstat{$_}=~/fail/ } keys %jobstat;
        if(@failed) {
            $pipeline->stage("Pipeline failed: ".scalar(@failed)." job(s) failed.");
            exit(1);
        }
        $pipeline->stage("Pipeline complete.");
        $pipeline->mail(); 
        exit(0);
    }

    my $tm=time()-$start;
    print STDERR "Time: $tm\n";

    if((time()-$start)>10000) { 
        print STDERR "Time limit exceeded. Resubmitting.\n";
        $pipeline->qsub(); 
        `echo $lasttgt > $pname.tlast`;
        exit(0); 
    } 
    sleep(1);
}
   

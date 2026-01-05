package MODS::Pipeline;
use strict;
use warnings;
use File::Temp qw/ tempfile /;

use MODS::Globals;
use MODS::Genome;

sub new {

    my ( $class, %args ) = @_;

    my $s = bless {}, $class;

    foreach (keys %args) { $s->{$_}=$args{$_}; }

    die "Error: you need to specify a pipeline name (e.g. name=>MyPipe)" if not defined $s->{name};
    die "Error: you need to specify a genome name (e.g. gname=>human)" if not defined $s->{gname};

    $s->{genome}=new MODS::Genome(gname => $s->{gname});
    die "Genome $s->{gname} does not exist." if not -d $s->{genome}->home();
    $s->{pipedir}="/groups/bh6_gp/data/shares/databases/hfpd/genomes/$s->{gname}/Pipeline/$s->{name}.pip";
    `mkdir -m 775 $s->{pipedir}` if not -d $s->{pipedir};
    `mkdir -m 775 $s->{pipedir}/timings` if not -d "$s->{pipedir}/timings";
    `mkdir -m 775 $s->{pipedir}/completed` if not -d "$s->{pipedir}/completed";
    `mkdir -m 775 $s->{pipedir}/incomplete` if not -d "$s->{pipedir}/incomplete";
    my @tgts=$s->{genome}->get_target_list();
    `touch $s->{pipedir}/$s->{name}.stage; chmod g+rw $s->{pipedir}/$s->{name}.stage` if not -e "$s->{pipedir}/$s->{name}.stage";
    `touch $s->{pipedir}/$s->{name}.steps; chmod g+rw $s->{pipedir}/$s->{name}.steps` if not -e "$s->{pipedir}/$s->{name}.steps";
    `touch $s->{pipedir}/$s->{name}.jstat; chmod g+rw $s->{pipedir}/$s->{name}.jstat` if not -e "$s->{pipedir}/$s->{name}.jstat";
    `touch $s->{pipedir}/running; chmod g+rw $s->{pipedir}/running` if not -e "$s->{pipedir}/running";
    $s->{ntgts}=scalar(@tgts);
    $s->{stepsfn}="$s->{pipedir}/$s->{name}.steps";
    $s->{quiet}='yes';
    $s->{debug}='no' if not defined $s->{debug};
    $s->{qflag}='yes';
    return $s;

}


sub add_step {

    my $s=shift;
    my $sname=shift;
    my $argstr=shift;
    my %args=();

    # Parse the argument string into key-value pairs
    if(defined $argstr) {
        my @data=split(/,/,$argstr);
        for(my $i=0;$i<scalar @data;$i+=2) {
            $args{$data[$i]}=$data[$i+1];
        }
    }

    # Write the default .tgt file
    `touch $s->{pipedir}/$sname.tgt; chmod g+rw $s->{pipedir}/$sname.tgt` if not -e "$s->{pipedir}/$sname.tgt";
    open(STEPS, ">>$s->{stepsfn}") or die "Could not open $s->{stepsfn}\n";
    print STEPS "$sname\t";
    foreach (keys %args) { print STEPS "<$_>$args{$_}<\/$_>"; }
    print STEPS "\n";
    close STEPS;

    # Write genome2 to .g2 file if present
    if (defined $args{"external"}) {
        my $g2_file = "$s->{pipedir}/$sname.g2";
        open(G2, ">$g2_file") or die "Could not open $g2_file to write genome2\n";
        print G2 $args{"external"};
        close G2;
        `chmod g+rw $g2_file`;
    }
}
    
sub qsub {
    
    my $s = shift;
    my $execute=shift;
    $execute='yes' if not defined $execute;
    my $qsub="$s->{pipedir}/$s->{name}.sh";
    my $fn="$s->{name}.$s->{gname}";
    open(QSUB,">$qsub") or die("Could not open $qsub ($!)\n");
    print QSUB "#!/bin/bash\n";
    print QSUB "#SBATCH --chdir=$s->{pipedir}\n";
    print QSUB "#SBATCH --job-name=$fn\n";
    print QSUB "#SBATCH --time=24:00:00\n";
    print QSUB "#SBATCH --output=$fn.o\%j\n";
    print QSUB "#SBATCH --error=$fn.e\%j\n";
    my $dbopt="";
    $dbopt=" -d " if $s->{debug} eq 'yes';
    print QSUB "export PERL5LIB=$ENV{PERL5LIB}\n";
    print QSUB "export TROLLTOP=$ENV{TROLLTOP}\n";
    print QSUB "export SUBMAT=$ENV{SUBMAT}\n";
    print QSUB "export JACKALDIR=$ENV{JACKALDIR}\n";
    print QSUB "export HFPD_DIR=$ENV{HFPD_DIR}\n";
    print QSUB "export HFPD_DATA_DIR=$ENV{HFPD_DATA_DIR}\n" if defined $ENV{HFPD_DATA_DIR};
    print QSUB "export HFPD_IFS_DATA=$ENV{HFPD_IFS_DATA}\n" if defined $ENV{HFPD_IFS_DATA};
    print QSUB "export HFPD_IFS_HOME=$ENV{HFPD_IFS_HOME}\n" if defined $ENV{HFPD_IFS_HOME};
    print QSUB "export HFPD_IFS_SCRATCH=$ENV{HFPD_IFS_SCRATCH}\n" if defined $ENV{HFPD_IFS_SCRATCH};
    print QSUB "export HFPD_SCRATCH_DIR=$ENV{HFPD_SCRATCH_DIR}\n" if defined $ENV{HFPD_SCRATCH_DIR};
    print QSUB "$MAIN_DIRECTORY/SCR/run_pipeline.pl $s->{name} $s->{gname} $dbopt\n";
    print QSUB "\n";
    close QSUB;
    `chmod g+rw $qsub`;
    print STDERR `sbatch $qsub` if $execute eq 'yes';

}

sub stop {
    my $s=shift;
    `rm $s->{pipedir}/$s->{name}.active`;
}

sub steps {
    my $s=shift;
    my $fn=$s->{stepsfn};
    $fn="$s->{stepsfn}.focus" if -e "$s->{stepsfn}.focus";
    my @steps=();
    @steps=`cut -f 1 $fn`;
    die("No pipeline steps found in $fn") if not @steps;
    for(@steps) { chomp; }
    return @steps;
}

sub stepname {

    my $s=shift;  
    my $idx=shift;
    my $stepline=`head -$idx $s->{stepsfn} | tail -1`;
    return (split(/\t/,$stepline))[0]; 
   
}

sub step_arg {

    my $s=shift;  
    my $name=shift;
    my %output=();
    my @steps=`cat $s->{stepsfn}`;
    foreach my $step (@steps)
    {
        if($step  =~ m/^$name/)
        {
            my($n,$args)=split(/\t/,$step);
	    if(defined $args)
	    {
		while($args =~m/<([\w]*)>([^<^>]*)<\/[\w]*>/g)
		{
		    $output{$1}=$2;
		}
	    }
        }
    }
    return \%output;
}

sub check {

    my $s=shift;
    my $fname="$s->{pipedir}/$s->{name}.jstat";
    $fname="$fname.new" if -e "$fname.new";
    if(not -e $fname) { return undef; }
    my @jstat=`cat $fname`;
   
    my @pstat;
    foreach my $sname ($s->steps) {
        my $sstat="$sname:";
        my @sjobs=grep(/:$sname\t/,@jstat);
        foreach my $type ('holding','ready','queued','submit','complete','fail') {
            $sstat.="$type(";
            my @tjobs=grep(/ $type/,@sjobs);
            my @ids;
            foreach (@tjobs) { /^(.+):$sname/; push(@ids,$1); }
            @ids=sort(@ids);
            for(@ids) { $sstat.="$_,"; }
            chop $sstat if @ids;
            $sstat.=");";
        }
        chop $sstat;
        push(@pstat,$sstat);

    }
    return @pstat;
}

sub submit_block {
    my $s=shift;
    my $sname=shift;
    my $jsref=shift;
    my @jobs=`cat $sname.tgt`;
    my @sjobs;
    my $jtot=0;
    no strict 'refs';
    my $mname="MODS::$sname";
    my $method=$mname->new();
    my $jcap=$MAX_ARRAY_VAL;
    if(defined $method->{slots}) {
        my $gr="$sname\_.....\\.tgt\$";
        my @stgt=`ls -f $s->{pipedir} | grep $gr`;
        $method->{jcap}=$method->{slots};
        for(@stgt) {
            chop;
            my $queued=`perl -ne '\$tot+=(split)[1]; END { print "\$tot\n"}' $_`;
            $method->{jcap}-=$queued;
            my @t=`ls -f $_.active | grep FREE`;
            foreach my $f (@t) { `rm -rf $_/$f`; }
            $method->{jcap}+=scalar(@t);
        }
    }
    $jcap=$method->{jcap} if defined $method->{jcap};
    return if not $jcap;
    my ($fh, $fn) = tempfile( "$sname\_XXXXX", DIR => $s->{pipedir}, SUFFIX=>".tgt");
    for(@jobs) {
        last if ($jtot+1)>$jcap;
        push(@sjobs,$_);
        my ($jid,$nj)=(split(/\t/,$_));
        $jtot+=$nj;
        $jid.=":$sname";
        my $tm=$s->time();
        my $tfn=$fn;
        $tfn =~ s#.*/##;
        $$jsref{$jid}.="($tm submit $tfn)";
        }
    for(@sjobs) { shift @jobs; }
    for(@sjobs) { print $fh "$_"; }
    close $fh;
    `chmod g+rw $fn`;
    $fn=~s#.*/##;
    my @qarg=($fn,$sname,$jtot);
    push(@qarg,$method->{qres}) if defined $method->{qres};
    my $jnam=$s->qsub_block(@qarg);
    open(TGTFH,">$sname.tgt");
    close(TGTFH);
    for(@jobs) { chomp; `echo -e "$_" >> $sname.tgt`; }
    return $jnam;
}

# Write resource string for slurm based on $qres
sub write_resource_string {
    my $s=shift;
    my $qres=shift;

    my $resource_lines = '';
    my @resource_elems = split (/,/, $qres);

    foreach my $element (@resource_elems) {
        my ($key, $value) = split (/=/, $element);

        if ($key eq 'mem') {
            # Append memory setting
            $resource_lines .= "#SBATCH --mem=$value\n";
        }
        elsif ($key eq 'time') {
            # Reformat time value to "days-hh:mm:ss"
            my $time_value = $s->reformat_time_string($value);
            $resource_lines .= "#SBATCH --time=$time_value\n";
        }
        else {
            die "Did not recognize resource of type '$key' in '$qres'"
        }
    }

    return $resource_lines;
}

# Parse the time string into components (hh:mm:ss format)
sub reformat_time_string {
    my $s = shift;
    my $time = shift;

    # Check for empty or undefined time
    die "Time string is undefined or empty" unless defined $time && $time ne '';

    my ($hours, $minutes, $seconds);
    if ($time =~ /^(\d*):(\d*):(\d*)$/) {
        ($hours, $minutes, $seconds) = ($1, $2, $3);
        die "Invalid seconds in '$time'" if $seconds >= 60;
        die "Invalid minutes in '$time'" if $minutes >= 60;
    }
    else {
        die "Could not parse 'time=$time' from \$qres";
    }

    # Calculate total days and remaining hours
    my $days = int($hours / 24);
    $hours = $hours % 24;

    # Format into "days-hh:mm:ss"
    return sprintf("%d-%02d:%02d:%02d", $days, $hours, $minutes, $seconds);
}

sub qsub_block {
    my $s = shift;
    my $fn = shift;
    my $sname = shift;
    my $jtot = shift;
    my $qres = shift;

    `mkdir $s->{pipedir}/$fn.active`;
    `chmod g+rw $s->{pipedir}/$fn.active`;

    my $batch_size = $MAX_ARRAY_VAL;
    my $num_batches = int(($jtot + $batch_size - 1) / $batch_size);

    my $last_job_id;

    for my $batch (1 .. $num_batches) {
        my $start_index = ($batch - 1) * $batch_size + 1;
        my $end_index = $batch * $batch_size;
        $end_index = $jtot if $end_index > $jtot;

        my $batch_fn = "$fn";

        open(QSUB, ">$s->{pipedir}/$batch_fn.sh") or die "Could not open $s->{pipedir}/$batch_fn.sh ($!)";
        print QSUB "#!/bin/bash\n";
        print QSUB "#SBATCH --chdir=$s->{pipedir}\n";
        print QSUB "#SBATCH --job-name=$batch_fn\n";
        my $fn_out = ($s->{debug} eq 'no') ? "/dev/null" : "$batch_fn.o\%j";
        my $fn_err = ($s->{debug} eq 'no') ? "/dev/null" : "$batch_fn.e\%j";
        print QSUB "#SBATCH --output=$fn_out\n";
        print QSUB "#SBATCH --error=$fn_err\n";
        print QSUB $s->write_resource_string($qres) if defined $qres;
        print QSUB "#SBATCH --export=ALL\n";
        print QSUB "#SBATCH --array=$start_index-$end_index\n";
        print QSUB "chmod g+rw *$fn*\n";
        print QSUB "if $HFPD_SCR/run_method.pl $s->{name} $s->{gname} $sname $s->{pipedir}/$fn \$SLURM_ARRAY_TASK_ID";
        print QSUB " debug" if $s->{debug} eq 'yes';
        print QSUB "; then\n";
        print QSUB "    echo 'Success!'\n";
        print QSUB "else\n";
        print QSUB "    gid=`cut -f 1 $s->{pipedir}/$fn | head -\$SLURM_ARRAY_TASK_ID | tail -1`\n";
        print QSUB "    touch $s->{pipedir}/$fn.active/FAIL.\$gid\n";
        print QSUB "    chmod g+rw $s->{pipedir}/$fn.active/FAIL.\$gid\n";
        print QSUB "fi\n";

        close QSUB;
        `chmod g+rw $s->{pipedir}/$batch_fn.sh`;

        my $dependency = $last_job_id ? "--dependency=afterok:$last_job_id" : "";
        my $return_value = `sbatch $dependency $s->{pipedir}/$batch_fn.sh`;
        print STDERR $return_value if $s->{qflag} eq 'yes';

        if ($return_value !~ /^Submitted batch job (\d+)/) {
            die "Batch job submission failed: $return_value";
        }

        $last_job_id = $1;
    }

    open(QSUB, ">$s->{pipedir}/w$fn.sh") or die "Could not open $s->{pipedir}/w$fn.sh ($!)";
    print QSUB "#!/bin/bash\n";
    print QSUB "#SBATCH --chdir=$s->{pipedir}\n";
    print QSUB "#SBATCH --job-name=w$fn\_$s->{gname}\n";
    print QSUB "#SBATCH --output=/dev/null\n" if $s->{debug} eq 'no';
    print QSUB "#SBATCH --error=/dev/null\n" if $s->{debug} eq 'no';
    print QSUB "#SBATCH --export=ALL\n";
    print QSUB "#SBATCH --dependency=afterok:$last_job_id\n";
    print QSUB "chmod g+rw *$fn*\n";
    print QSUB "$HFPD_SCR/process_method.pl $s->{name} $s->{gname} $sname $fn";
    print QSUB " debug" if $s->{debug} eq 'yes';
    print QSUB "\n";
    close QSUB;

    `chmod g+rw $s->{pipedir}/w$fn.sh`;
    print STDERR `sbatch $s->{pipedir}/w$fn.sh` if $s->{qflag} eq 'yes';

    return "$fn\t$jtot";
}

sub debug_step {

    my $s=shift;
    my ($sname,$gid,$submit)=@_;
    $s->{qflag}=$submit if defined $submit;
    my $mname="MODS::$sname";
    my $method=$mname->new(gname=>$s->{gname},gid=>$gid,step_parameters=>$s->step_arg($sname));
    $method->prep();
    my $nj=$method->count_jobs();
    die("No jobs to run for $sname $gid") if $nj==0;
    my $fn="$sname\_$gid.tgt";
    my @jobsf=`ls -f $s->{pipedir} | grep $fn`;
    for(@jobsf) { chop; `rm -rf $s->{pipedir}/$_`; }
    open(TGT,">$s->{pipedir}/$fn");
    print TGT "$gid\t$nj\n";
    close TGT;
    `chmod g+rw $s->{pipedir}/$fn`;
    my @qarg=($fn,$sname,$nj);
    push(@qarg,$method->{qres}) if defined $method->{qres};
    $s->{debug}='yes';
    my $jname=$s->qsub_block(@qarg);
    $s->{debug}='no';
    $method->output();
    return $fn;
}

sub status {
    my $s=shift;
    my ($gid,$sname,$jsref)=@_;
    my $jid="$gid:$sname";
    my $tm=$s->time();
    no strict 'refs';
    my $mname="MODS::$sname";
    $$jsref{$jid}.="(last checked: $tm)" unless $$jsref{$jid}=~/last checked/;
    $$jsref{$jid}=~ s/last checked .+:\d+:\d+:\d+\)/last checked $tm\)/;
    my $method=$mname->new(gname=>$s->{gname},gid=>$gid,step_parameters=>$s->step_arg($sname));
    $$jsref{$jid}.="($tm modeled)" if -e $method->{pdb} and not $$jsref{$jid}=~/modeled/;
    do { $$jsref{$jid}.="($tm complete)" unless $$jsref{$jid}=~/complete/; return; } if $method->complete();
    if($$jsref{$jid}=~/submit/ and not -e "$method->{wrkdir}/done" and not $$jsref{$jid}=~/killed/ and not $$jsref{$jid}=~/fail|complete/) { 
        $$jsref{$jid}=~/submit (.+.tgt)\)/;
        return if -d "$1.active";
        $$jsref{$jid}.="($tm fail killed)"; 
        return; 
    } 
    my $ready=1;
    my $predfail="";
    if(defined $method->{holds}) {
        my $pstep=$_;
        foreach(split(/,/,$method->{holds})) { 
            $pstep=$_;
            next if not defined $$jsref{"$gid:$_"};
            $ready=0 if $$jsref{"$gid:$_"}=~/fail/ or not $$jsref{"$gid:$_"}=~/complete/;
            $predfail.="$_ " if $$jsref{"$gid:$_"}=~/fail|skipped/; 
            last if not $ready;
        }
        if(not $ready) { 
            if($predfail eq "") { $$jsref{$jid}.="($tm holding for $pstep)" if not $$jsref{$jid}=~/holding for $pstep/; return; }
            else { $$jsref{$jid}.="($tm predecessor $predfail failed)" if not $$jsref{$jid}=~/predec/; return; }
        }
    }
    my $nj=$method->count_jobs();
    do { $$jsref{$jid}.="($tm fail output not found)"; return; } if $nj and not $method->complete() and -e "$method->{wrkdir}/done" and not $$jsref{$jid}=~/output/ and -e "$method->{wrkdir}/process";
    do { $$jsref{$jid}.="($tm fail skipped)"; return; } if $nj>10000 and not $$jsref{$jid}=~/skip/;
    $$jsref{$jid}.="($tm ready $nj jobs)" if $ready and not $$jsref{$jid}=~/ready/;  
    if($nj==0) {
        $$jsref{$jid}.="($tm complete 0 jobs)";
        do { $method->process(); `touch $method->{wrkdir}/process`; `touch $method->{wrkdir}/done`} if not -e "$method->{wrkdir}/process"; 
    }
    $method->prep();
}

sub stage {
    my $s=shift;
    my $msg=shift;
    my $tm=$s->time();
    do { `echo "$msg ($tm)." > $s->{pipedir}/$s->{name}.stage`; } if defined $msg;
    $msg="";
    my $jid=$s->get_jid();
    $msg=`cat $s->{pipedir}/$s->{name}.stage` if -e "$s->{pipedir}/$s->{name}.stage";
    return $msg if $msg=~/Pipeline complete/;
    return "Pipeline not running, last msg: $msg" if not defined $jid and $msg=~/[a-z]/;
    return "$msg";
}

sub pause {
    my $s=shift;
    `touch $s->{pipedir}/$s->{name}.pause`;
    while(not -e "$s->{pipedir}/$s->{name}.paused") { $s->stage("Pipeline is paused"); sleep(1); }
}

sub resume {
    my $s=shift;
    `rm -rf $s->{pipedir}/$s->{name}.pause $s->{pipedir}/$s->{name}.paused`;
}

sub progress {
    my $s=shift;
    my @tgts=$s->{genome}->get_target_list();
    my @steps=$s->steps();
    my $tasks=(scalar @tgts)*(scalar @steps);
    `grep " complete" $s->{pipedir}/$s->{name}.jstat | wc -l`=~/(\d+)/;
    my $cpl=$1;
    `grep " fail" $s->{pipedir}/$s->{name}.jstat | wc -l`=~/(\d+)/;
    return ($cpl,$1,$tasks-$1-$cpl);
}

sub get_jid {
    my $s=shift;
    my $jid = `squeue --name=$s->{name}.$s->{gname} --noheader --format='%A'`;
    return $1;
    }

sub check_active {
    my $s=shift;
    my @activej=`ls -f $s->{pipedir} | grep ".tgt.active\$"`;
    foreach my $j (@activej) {
        chomp $j;
        $j=~/(.+)\.active/;
        my $jname=$1;
        my @jobdat=`squeue --name=$jname --noheader`;
        next if @jobdat;
        print STDERR "$jname was incomplete.\n";
        #my @fns=`ls -f $s->{pipedir} | grep $jname`;
        #foreach my $f (@fns) { chomp $f; `mv $f $s->{pipedir}/incomplete`; }
    }
}

sub set_targets {

    my $s=shift;
    my $tgts=shift;
    open(TGTS,">$s->{pipedir}/targets.lst");
    for(split(/,/,$tgts)) {
        chomp;
        print TGTS "$_\n";
    }
    close TGTS;
}

sub get_disk_usage {
    my $s=shift;
    return if not -e "$s->{pipedir}/running";
    my @running=`cut -f 1 $s->{pipedir}/running`;
    for(@running) {
        chomp;
        my $sname=substr($_,0,length($_)-10);
        print "$sname\n";
        my @jobs=`cut -f 1 $s->{pipedir}/$_` if -e "$s->{pipedir}/$_";
        my %du;
        foreach my $gid (@jobs) {
            chomp $gid;
            no strict 'refs';
            my $mname="MODS::$sname";
            my $method=$mname->new(gname=>$s->{gname},gid=>$gid,step_parameters=>$s->step_arg($sname));
            next if -e "$method->{wrkdir}/done";
            `du -s $method->{wrkdir}`=~/(\d+)/;
            $du{$gid}=$1;
        }
        my @data=();
        @data=`cat $s->{pipedir}/$sname.usage` if -e "$s->{pipedir}/$sname.usage";
        my %siz;
        for(@data) { chomp; $siz{(split)[0]}=(split)[1]; }
        for(@jobs) { $siz{$_}=$du{$_} if defined $du{$_}; }
        open(SIZFD,">$s->{pipedir}/$sname.usage");
        for(sort keys %siz) { print SIZFD "$_\t$siz{$_}\n"; }
        close(SIZFD);
    }
}

sub collect_statistics {
    my $s=shift;
    my @steps=$s->steps();
    my %times;
    for(@steps) {
        my @fns=`ls -f $s->{pipedir}/timings | grep "$_\_......tgt.time"`;
        my ($tottm,$tottsk)=(0,0);
        next if not @fns;
        foreach my $f (@fns) { 
            chop $f; 
            my @times=`cat  $s->{pipedir}/timings/$f`;
            foreach my $line (@times) {
                my @data=split(/\t/,$line);
                $tottm+=$data[2];
                $tottsk+=$data[3];
            }
        }
        $times{$_}=$tottm/$tottsk;
    }
    return %times;
}
 
sub create_mail()
{
    my $s=shift;
    my $email=shift;
    my $sender=shift;
    my $sbj=shift;
    my $msg=shift;
    
    my $file=$s->{pipedir}."/EMAIL.txt";
    
    my $text="email\t$email\n";
    $text.="sbj\t$sbj\n";
    $text.="msg\t$msg\n";
    $text.="sender\t$sender";
    open(FILE,">$file") or die "Could not create $file";
    print FILE $text;
    close FILE;

}
    
sub mail()
{
    my $s=shift;
    my $file=$s->{pipedir}."/EMAIL.txt";
    if(-s $file)
    {
        my @chars = ("A".."Z", "a".."z");
        my $string;
        my ($email,$sender,$sbj,$msg)=split(/\|\|\|/,$s->{mail});
        
        $string .= $chars[rand @chars] for 1..8;
	my $file_out=$EMAIL_DIR."/".$string;
	while (-e $file_out)
	{
	    $string .= $chars[rand @chars] for 1..8;
	    $file_out=$EMAIL_DIR."/".$string;
	}
        print STDERR `cp $file $file_out`;
    	print STDERR `chmod 777 $file_out`;
    }
}

sub time {
    my $s=shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday)=localtime(time);
    my @days=("M","T","W","Th","F","S","Su");
    return "$days[$wday-1]:$hour:$min:$sec";
}

1;


package MODS::Method;

use strict;
use warnings;

use File::Temp qw/ tempdir /;

use MODS::Globals;
use MODS::Genome;


sub new {

    my ( $class, %args ) = @_;
    my $self = bless {}, $class;
    foreach (keys %args) {  
        #push(@{$self->{atts}},$_);
        if(/step_parameters/) {
            my $parms=$args{step_parameters};
            for(keys %$parms) {
                $self->{$_}=$$parms{$_};
            }
        next;
        }
        $self->{$_}=$args{$_}; 
    }
    $self->{name}=$self->pname();
    $self->{quiet}='yes' unless defined $self->{quiet};
    $self->{go}='yes' unless defined $self->{go};
    $self->{init}='yes' if not defined $self->{init};
    $self->ginit(); 
    return $self;

}

sub ginit {

    my $self=shift;
    #if (! (grep {$_ eq 'wrkdir'} @{$self->{atts}})) { push(@{$self->{atts}},'wrkdir'); } 
    #if (! (grep {$_ eq 'name'} @{$self->{atts}})) { push(@{$self->{atts}},'name'); } 
    return if not defined $self->{gname} or not defined $self->{gid};
    my $genome=new MODS::Genome(gname=>$self->{gname});
    $genome->mk_tgt_dir($self->{gid});
    $self->{genome}=$genome;
    $self->{uniId}=$genome->seqUniId($self->{gid});
    $self->{seq}=$genome->seq($self->{gid});
    $self->{desc}=$genome->desc($self->{gid});
    $self->{seqfn}=$genome->seqfn($self->{gid});
    $self->{seqd}=$genome->seqd($self->{gid});
    $self->{wrkdir}="$self->{genome}->{home}/Pipeline/Pipeline_$self->{gid}/$self->{name}" if not defined $self->{wrkdir};
    do { umask 000; mkdir($self->{wrkdir},0775) or die "Could not create method working directory $self->{wrkdir} ($!)"; } unless -d $self->{wrkdir} or $self->{init} ne 'yes';
    $self->{skan}="$self->{seqd}/Nbr/$self->{gid}.skan";
    $self->{neighbors}="$self->{seqd}/Nbr/$self->{gid}.neigh";
    $self->{rescorr}="$self->{seqd}/Nbr/rescorr.txt";
    $self->{predint}="$self->{seqd}/PredInterface/$self->{gid}.int";
    $self->{interactions}="$self->{seqd}/Interactions/$self->{gid}.int";
    $self->{LR}="$self->{seqd}/Interactions/$self->{gid}.lr";
    $self->{pdb}="$self->{seqd}/Models/$self->{gid}_m.pdb";
    $self->{ppcorr_list}="$self->{seqd}/Profiles/$self->{gid}.list";
    $self->{ortho_pairs}="$self->{seqd}/Orthology/ortho_pairs.txt";
    $self->{ortho_groups}="$self->{seqd}/Orthology/groups.ort";
    $self->{ortho_sequences}="$self->{seqd}/Orthology/all_sequences.fasta";
    $self->{inparanoid_groups}="$self->{seqd}/Orthology/inparanoid.ort";
    $self->{gopher_groups}="$self->{seqd}/Orthology/gopher.ort";
    $self->{motifs}="$self->{seqd}/Motifs/motif.txt";
    $self->{motifs_elm}="$self->{seqd}/Motifs/motif_elm.txt";
    $self->{prds}="$self->{seqd}/Motifs/prd.txt";
    $self->{prds_elm}="$self->{seqd}/Motifs/prd_elm.txt";
}

sub default_opts {

    my $pgmopts="";
    return $pgmopts;
}


sub attrib_string {

    my $self=shift;
    if(not defined $self->{atts}) { return ""; }
    my @alist=@{$self->{atts}}; 
    my $attstr;
    foreach my $atr ( @alist ) {
        my $val=$self->{$atr};
        $attstr.="<$atr>$self->{$atr}<\/$atr> ";
    }

    return $attstr;

}

sub hold_str {
    my $self=shift;
    my $holdstr="";
    if (defined $self->{holds}) { foreach (split(/,/,$self->{holds}))
                                    {
                                        $holdstr.="$_";
                                        if( $self->{gid} )
                                        {
                                            $holdstr.="_$self->{gid}";
                                        }
                                        if( $self->{gname} )
                                        {
                                            $holdstr.="_$self->{gname}";
                                        }
                                        $holdstr.=",";
                                    }
                                }
    
    
    return $holdstr;

}

sub run {

    my $self=shift;
    
    $self->{pgmopts}=$self->default_opts() if not defined $self->{pgmopts};
    my $cmd="$self->{cmd}";
    
    if($self->{step_parameters})
    {
        my $step_args=$self->{step_parameters};
        my $step_arguments="";
        foreach my $key (keys %$step_args)
        {
            if(!$key eq "") {$step_arguments.=" -$key";}
            $step_arguments.=" $step_args->{$key}";
            
        }
        $cmd.=$step_arguments;
    }
    
    $cmd.=" $self->{pgmopts}";
    $cmd.=" 1> $self->{stdout} " if $self->{stdout};
    $cmd.=" 2> $self->{stderr} " if $self->{stderr};
    print STDERR "$cmd\n" unless $self->{quiet} eq 'yes';
    my @output=`$cmd`;
    return @output;

}

sub qopts {
    # todo: This method needs rewriting before running on slurm.
    #       The -l flag does not have a 1-1 translation in slurm and needs special care.
    die("STOPPING: 'Method::qopts' was called but it has not been migrated to slurm");

    my $self=shift;
    my $qopts;
    $qopts="#!/bin/bash\n";
    $qopts.="#\$ -wd $self->{wrkdir}\n";
    $qopts.="#\$ -N $self->{name}" unless defined $self->{jobname};
    $qopts.="#\$ -N $self->{jobname}" if defined $self->{jobname};
    $qopts.="_$self->{gid}" if defined $self->{gid};
    $qopts.="_$self->{gname}" if defined $self->{gname};
    $qopts.="\n";
    $qopts.="#\$ -l $self->{qres}\n" if defined $self->{qres};
    do { my $str=$self->hold_str(); $qopts.="#\$ -hold_jid $str\n"; } if defined $self->{holds};

    return $qopts;
}

sub holds { my $s=shift; return split(/,/,$s->{holds}) if defined $s->{holds}; return (); }

sub qsub {
    # todo: This method needs rewriting before running on slurm.
    #       It relies on Method::qopts (above), which needs special care.
    die("STOPPING: 'Method::qsub' was called but it has not been migrated to slurm");

    my $self=shift;
    
    my $qsubfn="$self->{wrkdir}/$self->{name}.sh";
    open(QSUB,">$qsubfn") or die("Could not open $qsubfn: $!");
    print QSUB $self->qopts();
    my $attstr=$self->attrib_string();
    my $sgestr="";
    do { my $nj=$self->count_jobs(); print QSUB "#\$ -t 1-$nj\n"; $sgestr=" -q \$SGE_TASK_ID \n"} if defined $self->{sge_input};
    print QSUB "#\$ -V\n";
    print QSUB "$HFPD_SCR/run_method.pl  -a \"$attstr\" $sgestr\n";
    my $tid="";
    $tid=".\$SGE_TASK_ID" if defined $self->{sge_input};
    print QSUB "touch $self->{name}.END$tid\n";
#    print QSUB "rm -rf $self->{name}*.e*$tid $self->{name}*.o*$tid\n" if $self->{quiet} eq 'yes'; 
    $tid=$self->{sge_task_id} if defined $self->{sge_task_id};
    close QSUB;
    print STDERR `qsub $qsubfn` if $self->{go} eq 'yes';;
}

sub set_sge_input {

    my $s=shift;
    $s->{sge_task_id}=shift;
}
      
sub count_jobs {

    my $self=shift;
    if(defined $self->{sge_input}) {
        `wc -l $self->{sge_input}`=~/(\d+) */;
        return $1;
    }
    return 1;

}

sub count_tasks { return 1; }

sub get_pdb {
    my $s=shift;
    my $tpl=shift;
    $tpl=~/^[de].(..).(.)/ ? 0 : $tpl=~/..(..)_(.)/; 
    my $dir=$1;
    my $ch=uc($2);
    return ($tpl=~/^[de]/ ? ("$DOM_DIR/$dir/$tpl.pdb",$ch) : ("$PDBCHAIN_DIR/$dir/$tpl.pdb",$ch));
}

sub pdb_id_chain {

    my $s=shift;
    my $tpl=shift;
    $tpl=~/^[de](....)(.)/ ? 0 : $tpl=~/(....)_(.)/; 
    my $id=$1;
    my $ch=uc($2);
    return ($id,$ch);
}

sub output() {
    my $s=shift;
    if(not defined $s->{output}) {
        print STDERR "No output defined for $s->{name}.\n";
        return;
    }
    my @fns=split(/,/,$s->{output});
    for(@fns) {
        print STDERR "$_\n";
    }
}

sub hmap_path {

    my $s=shift;
    my $tpl=shift;

    my $pdbcode;
    my $chain;
    my $hmap_location;
 
  if ($tpl=~/^[defgh](\d[a-z0-9]{3})([a-z0-9_.])[a-z0-9_]$/) {
         $pdbcode=$1;
          if ($2 eq "_") {$chain="[A ]";} else {$chain=uc($2);}
         $hmap_location=substr($pdbcode,1,2);
         }
 
    elsif ($tpl=~/^(\d[a-z0-9]{3})_(\S)$/) {
         $pdbcode=$1;
          $chain=$2;
          $hmap_location=substr($pdbcode,2,2);
         }

    return "$HMAPALL_DIR/$hmap_location/$tpl.prof";

}

sub get_pdb_dat {
    my $s=shift;
    my $id=shift;
    $id=~/^[de](....)(.)/ ? 0 : $id=~/(....)_(.)/;
    my $pdbid=$1;
    my @rval= ($pdbid,uc($2),substr($pdbid,2,2));
}

sub pred_interface {
    my $s=shift;
    my $predifn="$s->{seqd}/PredInterface/$s->{gid}.int";
    return () if not -e $predifn;
    my $predi="";	
    open (PREDINTF,$predifn) or die "Could not open $predifn";
    while(<PREDINTF>) {
        next if /^#/;
        chomp;
        my @fields=split(/\t/);
        next if $fields[1]=~/NULL/ or not $fields[1]=~/\d/;
        $predi.=" " if $predi=~/\d/;
	$predi.=$fields[1];
    }
    return split(/\s+/,$predi);  
}
    
sub check {

    my $s=shift;
    my $step_args=shift;
    return $s->complete($step_args);

}

sub complete {
    my $s=shift;
    if(defined $s->{output}) {
        my @outf=split(/,/,$s->{output});
        for(@outf) { return 0 if not -e $_; }
        return 1;
    }
    return 0;
}

sub prep { }

sub process {
    my $s=shift;
    `touch $s->{wrkdir}/process`;
}

sub clean_output {
    my $s=shift;
    return unless defined $s->{output};
    my @outf=split(/,/,$s->{output});
    for(@outf) { 
        print STDERR "Removing $s->{gid} $s->{name} $_\n"; 
        print STDERR `rm -rf $_` if -e $_; 
    }
}

sub compress
{
    my $s=shift;
    my $input=shift;
    my $output=shift;
    $input =~ m#^(.*?)([^/]*)$#;
    my ($dir,$file)  = ($1,$2);
    my $PWD = `pwd`;
    chomp $PWD;	
    chdir $dir;
    if(-e $input)
    {
        my $aux="aux_compress_$file";
        print STDERR `tar -cvzf $aux $file`;
        print STDERR `mv $aux $output`;
        `chmod g+rw $output`;
        print STDERR `rm $input`;
    }
    chdir $PWD;
}

sub uncompress
{
    my $s=shift;
    my $input=shift;
    my $dir = $input;
    $dir =~ s/(.*)\/.*$/$1/;

    my $PWD = `pwd`;
    chomp $PWD;	
    if(-e $input)
    {
        chdir $dir;
        print STDERR `tar -xvf $input --transform 's?.*/??g'`;
        chdir $PWD;
    }
}

sub check_all_evaluation
{
    my $s=shift;
    return 0 if (!defined $ENV{HFPD_EVALUEALL} || $ENV{HFPD_EVALUEALL}==0);
    return 1;
}
   

1;
        

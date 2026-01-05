package MODS::MultiAlign;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::Method::ginit();
     $s->{cmd}=$CLUSTALW;
     $s->{holds}="OrthoSeq";
     my $args=$s->{step_parameters};
     $s->{output}="$s->{seqd}/Aligns/all_Clustalw.ali" if defined $s->{seqd};
     $s->{input}="$s->{seqd}/Orthology/all_sequences.fasta" if defined $s->{seqd};
     if(defined $args->{input})
     {
        $s->{output}="$s->{seqd}/Aligns/".$args->{input}."_Clustalw.ali";
        $s->{input}="$s->{seqd}/Orthology/".$args->{input}."_sequences.fasta";
        delete $s->{step_parameters}->{input};
     }
     
}



sub run {
    
    my $s=shift;
    
    if(-e $s->{input})
    {
        my $aux_out=$s->{wrkdir}."/output.txt";
        $s->{pgmopts}=" -infile=".$s->{input}."  -outfile=".$aux_out." -outorder=input";
        $s->MODS::Method::run();
        print STDERR `mv $aux_out $s->{output}; chomd g+rw $s->{outout}`;
    }
    
}

sub count_jobs {
    my $s=shift;
    return 0 if length($s->{gid})!=6;
    return 1;
}

package MODS::MultiAlign_JH;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::Method::ginit();
     $s->{cmd}="$MAIN_DIRECTORY/SCR/alignment_jackhammer.bash";
     $s->{qres}="mem=10G,time=02:00:00";
     my $args=$s->{step_parameters};
     $s->{output}="$s->{seqd}/Aligns/jackhammer.sto";
     if(defined $args->{input})
     {
        $s->{output}="$s->{seqd}/Aligns/".$args->{input}."_jackhammer.sto";
        delete $s->{step_parameters}->{input};
     }
     
}



sub run {
    
    my $s=shift;
    
    if(-e $s->{seqfn})
    {
        $s->{pgmopts}=" ".$s->{gid}." ".$s->{seqfn}."  ".$s->{wrkdir}." ".$JACKHAMMER." ".$UNI_SPROT;
        $s->MODS::Method::run();
        my $out=$s->{wrkdir}."/align_".$s->{gid}.".sto";
        print STDERR `mv $out $s->{output}`;
        $s->compress($s->{output},$s->{output}.".tar.gz");
    }
    
}

sub complete {
    my $s=shift;
    if(-e $s->{seqfn})
    {
        return 0 if(!-e "$s->{output}.tar.gz");
    }
    return 1;
}


package MODS::MuscleG;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::Method::ginit();
      $s->{qres}="mem=12G,time=04:00:00";
     $s->{cmd}="$MAIN_DIRECTORY/SCR/get_gopher_ic.pl";;
     $s->{holds}="Gopher";
     $s->{output}="$s->{seqd}/Aligns/Gopher.csv";
     $s->{input}="$s->{seqd}/Orthology/gopher.fas";
}



sub run {
    
    my $s=shift;
    
    if(-e $s->{seqfn} && -e $s->{input})
    {
        my $aux_out=$s->{wrkdir}."/output.txt";
        
        $s->{pgmopts}=" -i ".$s->{seqfn}." -f ".$s->{input}."  -o ".$aux_out ;
        $s->MODS::Method::run();
        print STDERR `mv $aux_out $s->{output}`;
    }
    
}

1;

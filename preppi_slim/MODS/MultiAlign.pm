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
     return $s if not defined $s->{seqd};
     $s->{output}="$s->{seqd}/Aligns/residue_conservation.csv";
     $s->{input}="$s->{seqd}/Orthology/gopher.fas";
     return $s;
}



sub run {
    
    my $s=shift;
    
    if(-e $s->{seqfn} && -e $s->{input})
    {
        my $aux_out=$s->{wrkdir}."/output.txt";
        
        $s->{pgmopts}=" -i ".$s->{seqfn}." -f ".$s->{input}." -o ".$aux_out.
                       " -g ".$s->{gname}." -p ".$s->{gid};
        $s->MODS::Method::run();
        print STDERR `mv $aux_out $s->{output}`;
    }
    
}

1;

package MODS::FindPRDs_ELM;
use strict;
use warnings;
use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

    my $s=shift;
    $s->MODS::Method::ginit();
    $s->{cmd}="$MAIN_DIRECTORY/SCR/get_PRD_elm.pl";
    $s->{holds}="";
    $s->{qres}="mem=10G";
    $s->{input}=$s->{seqfn} if defined $s->{seqd};
    $s->{output}=$s->{prds_elm} if defined $s->{seqd};
    $s->{output2}=$s->{seqd}."/Motifs/".$s->{gid}.".pfam" if defined $s->{seqd};
    $s->{pgmopts}="$s->{input} $s->{output2} $s->{output} $s->{gname} $s->{gid}" if defined $s->{seqd};
}

sub run {
    my $s=shift;
    $s->MODS::Method::run();
}

sub complete {
    my $s=shift;
    return -e $s->{output} && -e $s->{output2};
}

1;

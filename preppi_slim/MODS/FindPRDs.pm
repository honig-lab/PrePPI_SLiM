package MODS::FindPRDs;
use strict;
use warnings;
use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

    my $s=shift;
    $s->MODS::Method::ginit();
    $s->{cmd}="$MAIN_DIRECTORY/SCR/get_PRD.pl";
    $s->{holds}="Skan_g,Skan_compact";
    $s->{output}=$s->{prds} if defined $s->{seqd};
}

sub run {
    my $s=shift;
    my $nbrf="$s->{gid}.neigh.compact";
    `cp $s->{seqd}/Nbr/$nbrf.gz .`;
    `gzip -d $nbrf.gz`;
    `mkdir $s->{seqd}/Motifs` if not -d "$s->{seqd}/Motifs";
    $s->{pgmopts}="$nbrf $s->{output} ";
    $s->MODS::Method::run();
    `rm -rf $nbrf`;
}
    
sub count_jobs {
    my $s=shift;
    return 0 if not -e "$s->{seqd}/Nbr/$s->{gid}.neigh.compact.gz";
    return 1;
}

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
    $s->{pgmopts}="$s->{input} $s->{output2} $s->{output}" if defined $s->{seqd};
}

sub run {
    my $s=shift;
    $s->MODS::Method::run();
}

1;

package MODS::FindMotifs;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::Method::ginit();
     $s->{cmd}="$MAIN_DIRECTORY/SCR/get_motifs.pl";
     $s->{output}=$s->{motifs};
}

sub run {
    my $s=shift;
    $s->{pgmopts}="    $s->{seqfn} $s->{output} ";
    $s->MODS::Method::run();
}

sub count_jobs {
    my $s=shift;
    return 0 if length($s->{gid})>6;
    return 1;
}

package MODS::FindMotifs_ELM;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::FindMotifs);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::FindMotifs::ginit();
     $s->{cmd}="$MAIN_DIRECTORY/SCR/get_motifs_elm.pl";
     $s->{output}=$s->{motifs_elm};
     
}


1;
        


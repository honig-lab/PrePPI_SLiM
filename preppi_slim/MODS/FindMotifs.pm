package MODS::FindMotifs_ELM;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA = qw(MODS::Method);

sub pname { return 'FindMotifs_ELM'; }

sub ginit {
    my ($self) = @_;
    $self->MODS::Method::ginit();
    $self->{cmd} = "$MAIN_DIRECTORY/SCR/get_motifs_elm.pl";
    $self->{output} = $self->{motifs_elm};
}

sub run {
    my ($self) = @_;
    $self->{pgmopts} = "$self->{seqfn} $self->{output} $self->{gname} $self->{gid}";
    return $self->MODS::Method::run();
}

sub count_jobs {
    my ($self) = @_;
    return length($self->{gid}) > 6 ? 0 : 1;
}

1;

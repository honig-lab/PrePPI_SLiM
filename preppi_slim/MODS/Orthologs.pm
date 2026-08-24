package MODS::Gopher;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA = qw(MODS::Method);

sub pname { return 'Gopher'; }

sub ginit {
    my ($self) = @_;
    $self->MODS::Method::ginit();
    $self->{cmd} = "/usr/bin/python3 $GOPHER_BIN";
    $self->{qres} = 'mem=32G';
    $self->{output} = $self->{gopher_groups};
    $self->{output2} = "$self->{seqd}/Orthology/gopher.fas" if defined $self->{seqd};
    $self->{debug} = 0;
}

sub run {
    my ($self) = @_;
    die "Domains are not valid Gopher targets" if length($self->{gid}) > 6;
    die "Input sequence not defined" if not defined $self->{seqfn};
    die "Input file not found: $self->{seqfn}" if not -e $self->{seqfn};

    chdir $self->{wrkdir} or die "Cannot enter $self->{wrkdir}: $!";
    open my $input, '<', $self->{seqfn} or die "Cannot open $self->{seqfn}: $!";
    open my $gopher_input, '>', 'input.fa' or die "Cannot create input.fa: $!";
    my $header = <$input> // '';
    my $representative;
    if ($header =~ /RepID=(.*)/) {
        $representative = $1;
    } else {
        my @items = split /[ |]/, $header;
        for my $candidate (@items) {
            if ($candidate =~ /_/) {
                $representative = $candidate;
                last;
            }
        }
    }
    if (not defined $representative) {
        close $gopher_input;
        close $input;
        warn "No species identifier in FASTA header; skipping $self->{gid}\n";
        return;
    }
    chomp $representative;

    print {$gopher_input} ">sp|$self->{gid}|$representative\n";
    print {$gopher_input} $_ while <$input>;
    close $gopher_input;
    close $input;

    $self->{pgmopts} = "orthfas gopher=input.fa orthdb=$GOPHER_DB blastpath=$BLASTCMD";
    $self->MODS::Method::run();

    my $orthology_dir = "$self->{seqd}/Orthology";
    my $ortholog_fasta = "ORTH/$self->{gid}.orth.fas";
    if (not -e $ortholog_fasta) {
        warn "No orthologs found for $self->{gid}\n";
        return;
    }
    rename $ortholog_fasta, "$orthology_dir/gopher.fas"
        or die "Cannot move Gopher FASTA for $self->{gid}: $!";

    my $ortholog_ids = "ORTH/$self->{gid}.orth.id";
    open my $ids, '<', $ortholog_ids or die "Cannot open $ortholog_ids: $!";
    my @species;
    while (my $line = <$ids>) {
        chomp $line;
        push @species, $1 if $line =~ /__(.*)/;
    }
    close $ids;

    if (@species) {
        open my $output, '>', $self->{output} or die "Cannot open $self->{output}: $!";
        print {$output} 'gopher', "\t", join('|', @species), "|\n";
        close $output;
        chmod 0664, $self->{output};
    }

    if ($self->{debug} == 0) {
        unlink glob "$self->{wrkdir}/*.*";
        system('rm', '-rf', 'ORTH', 'PARA', 'BLAST');
    }
}

sub count_jobs {
    my ($self) = @_;
    return length($self->{gid}) > 6 ? 0 : 1;
}

sub complete {
    my ($self) = @_;
    return -e $self->{output} && -e $self->{output2};
}

1;

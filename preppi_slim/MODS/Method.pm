package MODS::Method;

use strict;
use warnings;

use MODS::Genome;

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;

    for my $key (keys %args) {
        if ($key eq 'step_parameters') {
            my $parameters = $args{$key};
            $self->{$_} = $parameters->{$_} for keys %{$parameters};
        } else {
            $self->{$key} = $args{$key};
        }
    }

    $self->{name} = $self->pname();
    $self->{quiet} //= 'yes';
    $self->{init} //= 'yes';
    $self->ginit();
    return $self;
}

sub ginit {
    my ($self) = @_;
    return if !defined($self->{gname}) || !defined($self->{gid});

    my $genome = MODS::Genome->new(gname => $self->{gname});
    $genome->mk_tgt_dir($self->{gid});
    $self->{genome} = $genome;
    $self->{uniId} = $genome->seqUniId($self->{gid});
    $self->{seq} = $genome->seq($self->{gid});
    $self->{desc} = $genome->desc($self->{gid});
    $self->{seqfn} = $genome->seqfn($self->{gid});
    $self->{seqd} = $genome->seqd($self->{gid});
    $self->{wrkdir} //= "$genome->{home}/Pipeline/Pipeline_$self->{gid}/$self->{name}";
    if (!-d $self->{wrkdir} && $self->{init} eq 'yes') {
        mkdir($self->{wrkdir}, 0775)
            or die "Cannot create method directory $self->{wrkdir}: $!";
    }

    $self->{gopher_groups} = "$self->{seqd}/Orthology/gopher.ort";
    $self->{motifs} = "$self->{seqd}/Motifs/motif.txt";
    $self->{motifs_elm} = "$self->{seqd}/Motifs/motif_elm.txt";
    $self->{prds_elm} = "$self->{seqd}/Motifs/prd_elm.txt";
}

sub default_opts { return ''; }

sub run {
    my ($self) = @_;
    $self->{pgmopts} = $self->default_opts() if not defined $self->{pgmopts};
    my $command = "$self->{cmd} $self->{pgmopts}";
    $command .= " 1> $self->{stdout}" if $self->{stdout};
    $command .= " 2> $self->{stderr}" if $self->{stderr};
    print STDERR "$command\n" unless $self->{quiet} eq 'yes';
    my $output = `$command`;
    my $status = $?;
    if ($status != 0) {
        my $detail = $status & 127
            ? "signal ".($status & 127)
            : "exit status ".($status >> 8);
        die "$self->{name} command failed with $detail: $command\n";
    }
    return $output;
}

sub count_jobs { return 1; }
sub count_tasks { return 1; }

sub output {
    my ($self) = @_;
    return if not defined $self->{output};
    print STDERR "$_\n" for split /,/, $self->{output};
}

sub check {
    my ($self, $step_args) = @_;
    return $self->complete($step_args);
}

sub complete {
    my ($self) = @_;
    return 0 if not defined $self->{output};
    for my $file (split /,/, $self->{output}) {
        return 0 if not -e $file;
    }
    return 1;
}

sub prep { }

sub process {
    my ($self) = @_;
    open my $marker, '>', "$self->{wrkdir}/process"
        or die "Cannot create process marker: $!";
    close $marker;
}

sub clean_output {
    my ($self) = @_;
    return if not defined $self->{output};
    unlink grep { -f $_ } split /,/, $self->{output};
}

sub compress {
    my ($self, $input, $output) = @_;
    return if not -e $input;
    (my $directory = $input) =~ s#[^/]+$##;
    (my $file = $input) =~ s#.*/##;
    system('tar', '-C', $directory || '.', '-czf', $output, $file) == 0
        or die "Could not compress $input";
    unlink $input or die "Could not remove $input: $!";
}

sub uncompress {
    my ($self, $input) = @_;
    return if not -e $input;
    (my $directory = $input) =~ s#/[^/]+$##;
    system('tar', '-C', $directory, '-xf', $input) == 0
        or die "Could not uncompress $input";
}

1;

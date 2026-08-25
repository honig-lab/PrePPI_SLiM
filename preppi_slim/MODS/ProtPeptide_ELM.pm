package MODS::ProtPeptide_ELM;

use strict;
use warnings;

use File::Path qw(make_path);
use MODS::Globals;
use MODS::Method;
our @ISA = qw(MODS::Method);

sub pname { return 'ProtPeptide_ELM'; }

sub ginit {
    my ($self) = @_;
    $self->MODS::Method::ginit();
    $self->{qres} = 'time=12:00:00';
    $self->{output_fn} = 'ProtPeptide_ELM.txt';
    $self->{orientation} //= 'motif';
    return $self if not defined $self->{seqd} or not defined $self->{gname};

    $self->{partner_gname} = $self->{external} // $self->{gname};
    $self->{genome2} = MODS::Genome->new(gname => $self->{partner_gname});
    die "Partner genome does not exist: $self->{genome2}->{home}\n"
        if not -d $self->{genome2}->{home};

    $self->{run_tag} //= "$self->{orientation}_$self->{partner_gname}";
    $self->{run_tag} =~ s/[^A-Za-z0-9_.-]+/_/g;
    $self->{wrkdir} = "$self->{genome}->{home}/Pipeline/Pipeline_$self->{gid}/ProtPeptide_ELM/$self->{run_tag}";
    make_path($self->{wrkdir}, { mode => 0775 }) if not -d $self->{wrkdir};

    my ($motif_gname, $prd_gname) = $self->{orientation} eq 'motif'
        ? ($self->{gname}, $self->{partner_gname})
        : ($self->{partner_gname}, $self->{gname});
    my $archive_name =
        "${motif_gname}_slim_${prd_gname}_prd_ProtPeptide_ELM.txt.tar.gz";
    $archive_name =~ s/[^A-Za-z0-9_.-]+/_/g;
    $self->{output} = "$self->{seqd}/Motifs/$archive_name";
    return $self;
}

sub run {
    my ($self) = @_;
    die "Unknown orientation: $self->{orientation}\n"
        if $self->{orientation} ne 'motif' and $self->{orientation} ne 'prd';

    my ($motif_genome, $prd_genome, @rows);
    if ($self->{orientation} eq 'motif') {
        $motif_genome = $self->{genome};
        $prd_genome = $self->{genome2};
        my @motifs = $self->_motifs($motif_genome, $self->{gid});
        for my $prd_id ($prd_genome->get_target_list()) {
            my @prds = $self->_prds($prd_genome, $prd_id);
            push @rows, $self->_matching_rows($self->{gid}, \@motifs, $prd_id, \@prds);
        }
    } else {
        $motif_genome = $self->{genome2};
        $prd_genome = $self->{genome};
        my @prds = $self->_prds($prd_genome, $self->{gid});
        for my $motif_id ($motif_genome->get_target_list()) {
            my @motifs = $self->_motifs($motif_genome, $motif_id);
            push @rows, $self->_matching_rows($motif_id, \@motifs, $self->{gid}, \@prds);
        }
    }

    my $raw_file = "$self->{wrkdir}/$self->{output_fn}";
    open my $out, '>', $raw_file or die "Cannot create $raw_file: $!\n";
    print {$out} "# record_type=PrePPI-SLiM_PRD-SLiM_candidates\n";
    print {$out} "# motif_genome=$motif_genome->{gname}\n";
    print {$out} "# prd_genome=$prd_genome->{gname}\n";
    print {$out} "# anchor_genome=$self->{gname}\tanchor_protein=$self->{gid}\tanchor_role=$self->{orientation}\n";
    print {$out} "# motif_protein\tprd_protein\tELM_class\tprd_start\tprd_end\tmotif_sequence\tmotif_start\tmotif_end\tconserved\tdisordered_fraction\n";
    print {$out} "$_\n" for sort @rows;
    close $out;

    local $ENV{COPYFILE_DISABLE} = 1;
    system('tar', '-C', $self->{wrkdir}, '-zcf', $self->{output}, $self->{output_fn}) == 0
        or die "Cannot archive $raw_file to $self->{output}\n";
    unlink $raw_file or warn "Cannot remove temporary result $raw_file: $!\n";
}

sub _matching_rows {
    my ($self, $motif_id, $motifs, $prd_id, $prds) = @_;
    my @rows;
    for my $motif (@{$motifs}) {
        for my $prd (@{$prds}) {
            next if $motif->{class} ne $prd->{class};
            push @rows, join "\t",
                $motif_id,
                $prd_id,
                $motif->{class},
                $prd->{start},
                $prd->{end},
                $motif->{sequence},
                $motif->{start},
                $motif->{end},
                $motif->{conserved},
                $motif->{disordered_fraction};
        }
    }
    return @rows;
}

sub _motifs {
    my ($self, $genome, $id) = @_;
    my $motif_file = "$genome->{home}/Seqs/$id/Motifs/motif_elm.txt";
    return () if not -e $motif_file;

    my %conserved;
    my $conservation_file = "$genome->{home}/Seqs/$id/Motifs/motif_elm.csv";
    if (-e $conservation_file) {
        open my $csv, '<', $conservation_file or die "Cannot read $conservation_file: $!\n";
        while (my $line = <$csv>) {
            next if $line =~ /^#/ or $line =~ /^\s*$/;
            chomp $line;
            my ($class, $sequence, $start) = split /\s+/, $line;
            $conserved{join "\t", $class, $sequence, $start} = 1;
        }
        close $csv;
    }

    my %disorder = $self->_read_disorder("$genome->{home}/Seqs/$id/disorder.fa");
    open my $motifs, '<', $motif_file or die "Cannot read $motif_file: $!\n";
    my @records;
    while (my $line = <$motifs>) {
        next if $line =~ /^#/ or $line =~ /^\s*$/;
        chomp $line;
        my ($class, $sequence, $start, $end) = split /\s+/, $line;
        next if not defined $end;
        my $disordered = 0;
        $disordered += $disorder{$_} // 0 for $start .. $end;
        push @records, {
            class               => $class,
            sequence            => $sequence,
            start               => $start,
            end                 => $end,
            conserved           => $conserved{join "\t", $class, $sequence, $start} ? 1 : 0,
            disordered_fraction => $disordered / ($end - $start + 1),
        };
    }
    close $motifs;
    return @records;
}

sub _prds {
    my ($self, $genome, $id) = @_;
    my $prd_file = "$genome->{home}/Seqs/$id/Motifs/prd_elm.txt";
    return () if not -e $prd_file;
    open my $prds, '<', $prd_file or die "Cannot read $prd_file: $!\n";
    my @records;
    while (my $line = <$prds>) {
        next if $line =~ /^#/ or $line =~ /^\s*$/;
        chomp $line;
        my ($class, $domain, $start, $end) = split /\s+/, $line;
        next if not defined $end;
        push @records, {
            class  => $class,
            domain => $domain,
            start  => $start,
            end    => $end,
        };
    }
    close $prds;
    return @records;
}

sub _read_disorder {
    my ($self, $file) = @_;
    my %positions;
    return %positions if not -e $file;
    open my $input, '<', $file or die "Cannot read $file: $!\n";
    my $position = 1;
    while (my $line = <$input>) {
        next if $line =~ /^>/ or $line =~ /^#/;
        chomp $line;
        for my $symbol (split //, $line) {
            $positions{$position++} = $symbol eq 'D' ? 1 : 0;
        }
    }
    close $input;
    return %positions;
}

sub count_jobs {
    my ($self) = @_;
    return length($self->{gid}) > 6 ? 0 : 1;
}

1;

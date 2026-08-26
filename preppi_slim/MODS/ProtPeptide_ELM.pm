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
    $self->{output_fn} = 'prd_slim_candidates.csv';
    $self->{orientation} //= 'motif';
    $self->{qres} = $self->{orientation} eq 'both'
        ? 'time=24:00:00'
        : 'time=12:00:00';
    return $self if not defined $self->{seqd} or not defined $self->{gname};

    $self->{partner_gname} = $self->{external} // $self->{gname};
    $self->{genome2} = MODS::Genome->new(gname => $self->{partner_gname});
    die "Partner genome does not exist: $self->{genome2}->{home}\n"
        if not -d $self->{genome2}->{home};

    $self->{run_tag} //= "$self->{orientation}_$self->{partner_gname}";
    $self->{run_tag} =~ s/[^A-Za-z0-9_.-]+/_/g;
    $self->{wrkdir} = "$self->{genome}->{home}/Pipeline/Pipeline_$self->{gid}/ProtPeptide_ELM/$self->{run_tag}";
    make_path($self->{wrkdir}, { mode => 0775 }) if not -d $self->{wrkdir};

    my $output_name;
    if ($self->{orientation} eq 'both' and $self->{gname} ne $self->{partner_gname}) {
        $output_name = "$self->{gname}_vs_$self->{partner_gname}_prd_slim_candidates.csv.gz";
    } else {
        my ($motif_gname, $prd_gname) = $self->{orientation} eq 'prd'
            ? ($self->{partner_gname}, $self->{gname})
            : ($self->{gname}, $self->{partner_gname});
        $output_name = "${motif_gname}_slim_${prd_gname}_prd_candidates.csv.gz";
    }
    $output_name =~ s/[^A-Za-z0-9_.-]+/_/g;
    $self->{output} = "$self->{seqd}/Motifs/$output_name";
    return $self;
}

sub run {
    my ($self) = @_;
    die "Unknown orientation: $self->{orientation}\n"
        if $self->{orientation} ne 'motif'
        and $self->{orientation} ne 'prd'
        and $self->{orientation} ne 'both';

    my @rows;
    if ($self->{orientation} eq 'motif' or $self->{orientation} eq 'both') {
        push @rows, $self->_motif_anchor_rows();
    }
    if ($self->{orientation} eq 'prd'
        or ($self->{orientation} eq 'both' and $self->{gname} ne $self->{partner_gname})) {
        push @rows, $self->_prd_anchor_rows();
    }

    my $raw_file = "$self->{wrkdir}/$self->{output_fn}";
    open my $out, '>', $raw_file or die "Cannot create $raw_file: $!\n";
    print {$out} "# record_type=PrePPI-SLiM_PRD-SLiM_candidates\n";
    print {$out} "# anchor_genome=$self->{gname}\tpartner_genome=$self->{partner_gname}\torientation=$self->{orientation}\n";
    print {$out} join(',', qw(
        motif_genome prd_genome anchor_genome anchor_protein anchor_role
        motif_protein prd_protein elm_class prd_start prd_end motif_sequence
        motif_start motif_end conserved disordered_fraction
    )), "\n";
    print {$out} "$_\n" for sort @rows;
    close $out;

    unlink "$raw_file.gz" if -e "$raw_file.gz";
    system('gzip', '-f', $raw_file) == 0
        or die "Cannot gzip $raw_file (exit status ".($? >> 8).")\n";
    rename "$raw_file.gz", $self->{output}
        or die "Cannot move $raw_file.gz to $self->{output}: $!\n";
}

sub _motif_anchor_rows {
    my ($self) = @_;
    my @motifs = $self->_motifs($self->{genome}, $self->{gid});
    my @rows;
    for my $prd_id ($self->{genome2}->get_target_list()) {
        my @prds = $self->_prds($self->{genome2}, $prd_id);
        push @rows, $self->_matching_rows(
            $self->{gname}, $self->{partner_gname}, 'motif',
            $self->{gid}, \@motifs, $prd_id, \@prds,
        );
    }
    return @rows;
}

sub _prd_anchor_rows {
    my ($self) = @_;
    my @prds = $self->_prds($self->{genome}, $self->{gid});
    my @rows;
    for my $motif_id ($self->{genome2}->get_target_list()) {
        my @motifs = $self->_motifs($self->{genome2}, $motif_id);
        push @rows, $self->_matching_rows(
            $self->{partner_gname}, $self->{gname}, 'prd',
            $motif_id, \@motifs, $self->{gid}, \@prds,
        );
    }
    return @rows;
}

sub _matching_rows {
    my ($self, $motif_gname, $prd_gname, $anchor_role,
        $motif_id, $motifs, $prd_id, $prds) = @_;
    my @rows;
    for my $motif (@{$motifs}) {
        for my $prd (@{$prds}) {
            next if $motif->{class} ne $prd->{class};
            push @rows, join ',',
                $motif_gname,
                $prd_gname,
                $self->{gname},
                $self->{gid},
                $anchor_role,
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

sub _first_existing {
    my ($self, @files) = @_;
    for my $file (@files) {
        return $file if -e $file;
    }
    return;
}

sub _fields {
    my ($self, $line) = @_;
    return split /,/, $line if $line =~ /,/;
    return split /\s+/, $line;
}

sub _motifs {
    my ($self, $genome, $id) = @_;
    my $motif_file = $self->_first_existing(
        "$genome->{home}/Seqs/$id/Motifs/slim_candidates.csv",
        "$genome->{home}/Seqs/$id/Motifs/motif_elm.txt",
    );
    return () if not defined $motif_file;

    my %conserved;
    my $conservation_file = $self->_first_existing(
        "$genome->{home}/Seqs/$id/Motifs/conserved_slims.csv",
        "$genome->{home}/Seqs/$id/Motifs/motif_elm.csv",
    );
    if (defined $conservation_file) {
        open my $csv, '<', $conservation_file
            or die "Cannot read $conservation_file: $!\n";
        while (my $line = <$csv>) {
            next if $line =~ /^#/ or $line =~ /^\s*$/ or $line =~ /^elm_class[,\t]/i;
            chomp $line;
            my ($class, $sequence, $start) = $self->_fields($line);
            $conserved{join "\t", $class, $sequence, $start} = 1;
        }
        close $csv;
    }

    my %disorder = $self->_read_disorder("$genome->{home}/Seqs/$id/disorder.fa");
    open my $motifs, '<', $motif_file or die "Cannot read $motif_file: $!\n";
    my @records;
    while (my $line = <$motifs>) {
        next if $line =~ /^#/ or $line =~ /^\s*$/ or $line =~ /^elm_class[,\t]/i;
        chomp $line;
        my ($class, $sequence, $start, $end) = $self->_fields($line);
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
    my $prd_file = $self->_first_existing(
        "$genome->{home}/Seqs/$id/Motifs/prd_candidates.csv",
        "$genome->{home}/Seqs/$id/Motifs/prd_elm.txt",
    );
    return () if not defined $prd_file;
    open my $prds, '<', $prd_file or die "Cannot read $prd_file: $!\n";
    my @records;
    while (my $line = <$prds>) {
        next if $line =~ /^#/ or $line =~ /^\s*$/ or $line =~ /^elm_class[,\t]/i;
        chomp $line;
        my ($class, $domain, $start, $end) = $self->_fields($line);
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

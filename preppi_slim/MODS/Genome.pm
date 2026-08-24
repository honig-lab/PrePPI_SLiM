package MODS::Genome;

use strict;
use warnings;

use MODS::Globals;

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    $self->{$_} = $args{$_} for keys %args;

    die "Error: Please specify a genome name.\n" if not defined $self->{gname};
    $self->{home} = "$GENOME_DIRECTORY/$self->{gname}";
    $self->{mk_tgt_dirs} = 'no';
    return $self;
}

sub init {
    my ($self, $fasta_file, %args) = @_;
    die "A FASTA file is required.\n" if not defined $fasta_file;

    $self->{mk_tgt_dirs} = $args{mk_tgt_dirs} if defined $args{mk_tgt_dirs};
    umask 000;

    for my $dir (
        $self->{home},
        "$self->{home}/Seqs",
        "$self->{home}/tmp",
        "$self->{home}/Pipeline",
        "$self->{home}/Interactions",
    ) {
        mkdir($dir, 0775) or die "Cannot create directory $dir: $!\n" if not -d $dir;
    }

    my @targets = $self->mk_fasta_dir($fasta_file);
    if ($self->{mk_tgt_dirs} eq 'yes') {
        $self->mk_tgt_dir($_) for @targets;
    }
    return 1;
}

sub mk_fasta_dir {
    my ($self, $fasta_file) = @_;
    my $fasta_dir = "$self->{home}/fasta";
    mkdir($fasta_dir, 0775) or die "Cannot create directory $fasta_dir: $!\n"
        if not -d $fasta_dir;

    my $id_list = "$fasta_dir/id_list";
    my $next_id = 1;
    if (-e $id_list) {
        open my $existing, '<', $id_list or die "Cannot open $id_list: $!";
        while (my $line = <$existing>) {
            chomp $line;
            $next_id = $line + 1 if $line =~ /^\d{6}$/ && $line >= $next_id;
        }
        close $existing;
    }

    open my $input, '<', $fasta_file or die "Cannot open $fasta_file: $!";
    open my $ids, '>>', $id_list or die "Cannot open $id_list: $!";

    my (@targets, @new_targets, $output, $write_record);
    while (my $line = <$input>) {
        if ($line =~ /^>/) {
            close $output if defined $output;
            undef $output;

            my $id = sprintf('%06d', $next_id++);
            if ($line =~ /HFPD_(\d{6}[.a-z0-9_-]*)/) {
                $id = $1;
            } else {
                $line =~ s/^>/>HFPD_$id;/;
            }

            push @targets, $id;
            my $target_file = "$fasta_dir/$id";
            $write_record = not -e $target_file;
            if ($write_record) {
                push @new_targets, $id;
                print {$ids} "$id\n";
                open $output, '>', $target_file or die "Cannot open $target_file: $!";
                print {$output} $line;
            }
            next;
        }

        print {$output} $line if $write_record && defined $output;
    }

    close $output if defined $output;
    close $ids;
    close $input;

    $self->create_mapping(@new_targets);
    return @targets;
}

sub mk_tgt_dir {
    my ($self, $id) = @_;
    my $seq_dir = "$self->{home}/Seqs/$id";
    my $work_dir = "$self->{home}/Pipeline/Pipeline_$id";

    for my $dir (
        $seq_dir,
        "$seq_dir/Aligns",
        "$seq_dir/Motifs",
        "$seq_dir/Orthology",
        $work_dir,
    ) {
        mkdir($dir, 0775) or die "Cannot create directory $dir: $!\n" if not -d $dir;
    }

    my $pipeline_link = "$seq_dir/Pipeline";
    if (!-e $pipeline_link && !-l $pipeline_link) {
        symlink($work_dir, $pipeline_link)
            or die "Cannot create symlink $pipeline_link: $!\n";
    }
}

sub get_target_list {
    my ($self) = @_;
    my $id_list = "$self->{home}/fasta/id_list";
    open my $targets, '<', $id_list or die "Cannot open $id_list: $!";
    my @ids;
    while (my $line = <$targets>) {
        chomp $line;
        next if $line =~ /\.g/ && (!$ENV{HFPD_WITHGAPS});
        push @ids, $line;
    }
    close $targets;
    return @ids;
}

sub tgt_list_fn {
    my ($self) = @_;
    return "$self->{home}/fasta/id_list";
}

sub get_tgt_id {
    my ($self, $index) = @_;
    die "No target index specified" if not defined $index;
    my @targets = $self->get_target_list();
    return $targets[$index - 1];
}

sub seq_data {
    my ($self, $id) = @_;
    my $file = "$self->{home}/fasta/$id";
    open my $fasta, '<', $file or die "Cannot open $file: $!\n";
    my ($sequence, $description) = ('', '');
    while (my $line = <$fasta>) {
        chomp $line;
        if ($line =~ /^>/) {
            $description = substr($line, 1);
        } else {
            $sequence .= $line;
        }
    }
    close $fasta;
    return ($sequence, $description);
}

sub seq {
    my ($self, $id) = @_;
    my ($sequence) = $self->seq_data($id);
    return $sequence;
}

sub seqfn {
    my ($self, $id) = @_;
    return "$self->{home}/fasta/$id";
}

sub seqd {
    my ($self, $id) = @_;
    return "$self->{home}/Seqs/$id";
}

sub seqUniId {
    my ($self, $id) = @_;
    my $file = "$self->{home}/Seqs/$id/Aligns/Uniprot_info.txt";
    return 'NULL' if not -e $file;
    open my $input, '<', $file or die "Cannot open $file: $!\n";
    my $line = <$input> // '';
    close $input;
    chomp $line;
    my ($uniprot_id) = split /\t/, $line;
    return $uniprot_id || 'NULL';
}

sub seqUniId_original {
    my ($self, $id) = @_;
    my (undef, $description) = $self->seq_data($id);
    return $1 if $description =~ /HFPD_[^;]+;([A-Z0-9]{6,10})/;
    return $1 if $description =~ /UniRef100_([A-Z0-9]{6,10})/;
    return $1 if $description =~ /\|([A-Z0-9]{6,10})\|/;
    return $self->seqUniId($id);
}

sub desc {
    my ($self, $id) = @_;
    my (undef, $description) = $self->seq_data($id);
    return $description;
}

sub home {
    my ($self) = @_;
    return $self->{home};
}

sub create_mapping {
    my ($self, @ids) = @_;
    my $map_file = "$self->{home}/fasta/map_list";
    open my $map, '>>', $map_file or die "Cannot open $map_file: $!";
    for my $id (@ids) {
        next if length($id) != 6;
        my $external_id = $self->seqUniId_original($id);
        $external_id = $id if !defined($external_id) || $external_id eq 'NULL';
        print {$map} "$id\t>$external_id\n";
    }
    close $map;
}

1;

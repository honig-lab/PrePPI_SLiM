#!/usr/bin/perl
use MODS::Globals;

my $fa = shift;
my $ofile = shift;

my $elm_file = "$ELM_CLASSES";
my %lig_class = read_motif_file_new($elm_file);

my $seq = "";
open IFH, "<", $fa or die "Cannot open $fa to read from!\n";
while (<IFH>) {
    next if (/^>/);
    chomp;
    $line = $_;
    $line =~ s/\s+//;
    $seq .= $line;
}
close IFH;

my @motifs = run_search_new($seq,\%lig_class);

open OFH, ">", $ofile or die "Cannot open $ofile to write into!\n";
foreach my $motif (@motifs)
{
    my $mseq = $motif->[0];
    my $class = $motif->[1];
    my $mstart = $motif->[2];
    my $mend = $motif->[3];

    print OFH "$class\t$mseq\t$mstart\t$mend\n";
}
close OFH;

sub read_motif_file_new
{
    my $motif_file = shift;
    my %lig_class;

    open MFH, "<", $motif_file or die "Cannot open file $motif_file to read!\n";
    while (<MFH>)
    {
        next if /^#/;
        chomp;

        my @fields = split /\t/, $_;
        next if $fields[0] =~ /Accession/;

        my $class = $fields[1];
        $class =~ s/^\"//;
        $class =~ s/\"$//;
        my $motif_regex = $fields[3];
        $motif_regex =~ s/^\"//;
        $motif_regex =~ s/\"$//;
        my $domain = $fields[7];
        $domain =~ s/^\"//;
        $domain =~ s/\"$//;

        next if $domain eq "NA";
        next if $domain =~ /SMART:/;

        $lig_class{$class}{domain} = $domain;
        $lig_class{$class}{regex} = $motif_regex;

        if ($#fields >= 8)
        {
            my $pdb_str = $fields[8];
            $pdb_str =~ s/^\"//;
            $pdb_str =~ s/\"$//;
            $lig_class{$class}{pdb} = $pdb_str;
        }
    }
    close MFH;

    return %lig_class;
}

sub run_search_new
{
    my $seq=shift;
    my $ref_lig_class=shift;

    my @output;

    my $fastaLength = length ( $seq );

    my %lig_class = %$ref_lig_class;

    foreach my $class (sort keys %lig_class)
    {
        my $regex = $lig_class{$class}{regex};

        if (($regex =~ /^\(*\^/) or ($regex =~ /\$\)*$/))
        {
            while ($seq =~ /($regex)/g)
            {
                my $motif = $1;
                my $end_pos = pos $seq;
                my $start_pos = $end_pos - length($motif) + 1;
                my @line = ($motif, $class, $start_pos, $end_pos);
                push(@output, [ @line ]);
            }
        }
        else
        {
            my $seq_len = length $seq;
            for (my $i = 0; $i < $seq_len; $i++)
            {
                my $tseq = substr $seq, $i;
                if ($tseq =~ /^($regex)/)
                {
                    my $motif = $1;
                    my $start_pos = $i+1;
                    my $end_pos = $start_pos + length($motif) - 1;
                    my @line = ($motif, $class, $start_pos, $end_pos);
                    push(@output, [ @line ]);
                }
            }
        }
    }

    return @output;
}


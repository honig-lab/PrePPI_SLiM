#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;


use MODS::Globals;

my $muscle_cmd = $MUSCLE;

## USAGE INFO -------------------------------------------------------------
my $PWD = `pwd`;
chomp $PWD;
my $PGM = $0;                   #name of program
$PGM =~ s#.*/##;                #remove part up to last slash
my $usage = <<USAGE;
USAGE:
        $PGM  -i fasta_file -f gopher_orthologs -o output
        options:
		-h	this help

USAGE

my %options = ();
getopts ( 'i:f:o:h', \%options );



if ( $options{h} || ( not defined ( $options{f} ) ) || ( not defined ( $options{i} ) ) || ( not defined ( $options{o} ) ) ) { print $usage, "\n"; exit; }


my $seq_id = $options{i};
my $output = $options{o};
my $gopher_fa = $options{f}; 


# get the fasta name for the query, so later we know which protein in the muscle alignment file is our query
my $ref_id;
open IFH, "<", $gopher_fa or die "Cannot open $gopher_fa to read from!\n";
while (<IFH>) {
    chomp;
    if (/^>/) {
        my @fields = split;
        $ref_id = substr $fields[0], 1;
        last;     
    }
}
close IFH;

# Run MUSCLE in the method working area.  $seq_id is an absolute path to the
# genome FASTA, so deriving the temporary filename from it incorrectly placed
# the alignment in the shared fasta directory instead of this job's workspace.
my $muscle_align_ofile = "$output.gopher.muscle";
system($muscle_cmd, '-in', $gopher_fa, '-out', $muscle_align_ofile, '-maxmb', '1000') == 0
    or die "MUSCLE failed for $seq_id (exit status ".($? >> 8).")\n";
-s $muscle_align_ofile
    or die "MUSCLE did not create a non-empty alignment: $muscle_align_ofile\n";

# read muscle alignment file, push all alignments into an array
# the alignment string will have gaps in them
my @align_seqs;
my $curr_seq = "";
my $curr_id = "";
open IFH, "<", $muscle_align_ofile or die "Cannot open $muscle_align_ofile to read from!\n";
while (<IFH>) {
    chomp;
    if (/^>/) {
        if ($curr_seq ne "") {
           my $h = {};
           $h->{id} = $curr_id;
           $h->{seq} = $curr_seq;
           push(@align_seqs,$h)    
        }
        my @fields = split;
        $curr_id = substr $fields[0], 1;
        $curr_seq = "";
    }
    else {
        $curr_seq .= $_;
    } 
}

if ($curr_seq ne "") {
    my $h = {};
    $h->{id} = $curr_id;
    $h->{seq} = $curr_seq;
    push(@align_seqs,$h)    
}

close IFH;
    
#if (scalar(@align_seqs) < 2) {
#    exit;
#}

# find out which protein is the query protein, and get its alignment string 
my $qaln_str;
foreach my $aln_entry (@align_seqs)
{
    my $aln_id = $aln_entry->{id};
    if ($aln_id eq $ref_id)
    {
        $qaln_str = $aln_entry->{seq}; 
    }   
}

my $qaln_nogap = $qaln_str;
$qaln_nogap =~ s/\-//g; 

# array specifying positions of the original query sequence in the alignment
# pos $i in the query sequence corresponds to the $positions[$i] column in the alignment
my @positions;
my $align_len = length $qaln_str;
for (my $i = 0; $i < $align_len; $i++)
{
    my $aa = substr $qaln_str, $i, 1;
    next if ($aa eq "-");
    push(@positions, $i);
}

# amino acid counts at each column in the alignment (only for columns for which the query is not gap)
my @aa_counts;
for (my $i = 0; $i <= $#positions; $i++)
{
    my $entry = {};
    push(@aa_counts, $entry);
}

foreach my $aln_entry (@align_seqs)
{
    my $taln_str = $aln_entry->{seq};
    for (my $i = 0; $i <= $#positions; $i++)
    {
        my $pos = $positions[$i];
        my $aa = substr $taln_str, $pos, 1;
        if (defined($aa_counts[$i]->{$aa}))
        {
            $aa_counts[$i]->{$aa} += 1;
        }
        else
        {
            $aa_counts[$i]->{$aa} = 1;
        }
    }
}

# calculate "conservation score" (essentially an information content-like score) for each position
my @ic_list;
my $base = 20*(-0.05*log(0.05)/log(2));
my $total_num = scalar(@align_seqs);
for (my $i = 0; $i <= $#positions; $i++)
{
    my $entry = $aa_counts[$i];
    my $nongap_perc = 1.0;
    my $se = 0.0;
    if (defined($entry->{"-"}))
    {
        my $gap_count = $entry->{"-"};
        my $gap_perc = ($gap_count+0.0) / $total_num;
        if ($gap_perc >= 0.5)
        {
            push(@ic_list, 0);
            next;
        }
        $nongap_perc = 1.0-$gap_perc;
    }  

    foreach my $aa (keys %$entry)
    {
        next if $aa eq "-";
        my $aa_count = $entry->{$aa};
        my $perc = ($aa_count+0.0)/$total_num/$nongap_perc; 
        $se = $se - $perc*log($perc)/log(2);
    }  
                 
    my $ic = $nongap_perc*($base - $se);
    push(@ic_list, $ic);
}
  
open OFH, ">", $output or die "Cannot open $output to write into!\n";
for (my $i = 0; $i <= $#positions; $i++)
{
    my $index = $i+1;
    my $aa = substr $qaln_nogap, $i, 1;
    my $ic = $ic_list[$i]; 
    print OFH "$index $aa $ic\n";
} 
close OFH;                
unlink $muscle_align_ofile
    or warn "Cannot remove temporary MUSCLE alignment $muscle_align_ofile: $!\n";



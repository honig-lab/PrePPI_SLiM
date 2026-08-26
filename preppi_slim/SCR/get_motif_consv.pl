#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;


use MODS::Globals;


## USAGE INFO -------------------------------------------------------------
my $PWD = `pwd`;
chomp $PWD;
my $PGM = $0;                   #name of program
$PGM =~ s#.*/##;                #remove part up to last slash
my $usage = <<USAGE;
USAGE:
        $PGM  -i init_position -f final_position -c motif_file
        options:
		-h	this help

USAGE

my %options = ();
getopts ( 'i:f:c:h', \%options );



if ( $options{h} || ( not defined ( $options{f} ) ) || ( not defined ( $options{i} ) ) || ( not defined ( $options{c} ) ) ) { print $usage, "\n"; exit; }


my $pstart = $options{i};
my $pend = $options{f};
my $consv_fname = $options{c}; 


my @consv = read_consv($consv_fname);

my $rlc_valid = 0;
my $below_count = 0; 
for (my $i = $pstart; $i <= $pend; $i++)
{
    my $calc_start = $i - 30;
    if ($calc_start < 1)
    {
        $calc_start = 1;
    }
    my $calc_end = $i + 30;
    if ($calc_end > scalar(@consv))
    {
        $calc_end = scalar(@consv);
    }
 
    my $score_sum = 0.0;
    for (my $j = $calc_start; $j <= $calc_end; $j++)
    {
        $score_sum += $consv[$j-1];
    }
    my $score_ave = $score_sum / ($calc_end-$calc_start+1);

    my $rlc = $consv[$i-1]-$score_ave;
    if ($rlc < 0)
    {
        $below_count += 1;
    }
}

if ($below_count < 1)
{
    $rlc_valid = 1;
}

print "$rlc_valid\n";

sub read_consv
{
    my $ifile = shift;

    my @consv;
    open IFH, "<", $ifile or die "Cannot open $ifile to read from!\n";
    while (<IFH>)
    {
        next if (/^#/);
        next if ($_ !~ /[0-9]/);
        next if (/^residue_position,/i);
        my @fields = /,/ ? split(/,/) : split(" ", $_);
        push(@consv, $fields[2]);
    }
    close IFH;

    return @consv;
}

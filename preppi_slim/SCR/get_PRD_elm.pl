#!/usr/bin/perl
use MODS::Globals;

my $fa = shift;
my $dfile = shift;
my $ofile = shift;
my $genome = shift // 'unknown';
my $protein = shift // 'unknown';

my $elm_file = $ELM_CLASSES;

# change to where the real HMM directory and where the script is
my $hmm_dir = $HMMS;
my $pfam_perl = "$IFS_HOME/shares/perl-5.40.0/install/bin/perl";
my $pfam_scan = "$MAIN_DIRECTORY/SCR/PfamScan/pfam_scan.pl";
local $ENV{PATH} = "$ENV{PATH}:$JACKHAMMER_DIR";

# read in the ELM class definitions
my %lig_class = read_motif_file_new($elm_file);
my %elm_domains;
foreach my $class (sort keys %lig_class)
{
    my $dname = $lig_class{$class}{domain};
    if ($dname =~ /\|/)
    {
        my @dname_list = split "/\|/", $dname;
        foreach my $dn (@dname_list)
        {
            $elm_domains{$dn}{$class} = 1;
        }
    }
    else
    {
        $elm_domains{$dname}{$class} = 1;
    }
}

if (-e $dfile)
{
    system "rm $dfile";
}

my @cmd = ($pfam_perl, '-w', $pfam_scan, '-fasta', $fa, '-dir', $hmm_dir, '-outfile', $dfile);
print STDERR join(' ', @cmd), "\n";
system(@cmd) == 0
    or die "PfamScan failed for $fa (exit status ".($? >> 8).")\n";
-e $dfile or die "PfamScan did not create its output: $dfile\n";

my $pfam_with_metadata = "$dfile.metadata.$$";
open my $pfam_in, '<', $dfile or die "Cannot read $dfile: $!\n";
open my $pfam_out, '>', $pfam_with_metadata
    or die "Cannot create $pfam_with_metadata: $!\n";
print {$pfam_out} "# record_type=PfamScan_domains\n";
print {$pfam_out} "# genome=$genome\tprotein=$protein\n";
print {$pfam_out} $_ while <$pfam_in>;
close $pfam_in;
close $pfam_out;
rename $pfam_with_metadata, $dfile
    or die "Cannot replace $dfile with metadata-annotated output: $!\n";

my %seq_domains = read_domains($dfile,\%elm_domains);
open OFH, ">", $ofile or die "Cannot open $ofile to write into!\n";
print OFH "# record_type=ELM_peptide_recognition_domains\n";
print OFH "# genome=$genome\tprotein=$protein\n";
print OFH "elm_class,pfam_domain,prd_start,prd_end\n";
foreach my $dname (sort keys %seq_domains)
{
    my @classes = sort keys %{$elm_domains{$dname}};
    foreach my $class (@classes) 
    {
        foreach my $dentry (@{$seq_domains{$dname}}) 
        {
            my $dstart = $dentry->{dstart};
            my $dend = $dentry->{dend};
            print OFH "$class,$dname,$dstart,$dend\n";
        } 
    }
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

sub read_domains {
    my $domain_file = shift;
    my $elm_domains = shift;

    my %seq_domains;
    open DFH, "<", $domain_file or die "Cannot open $domain_file to read from!\n";
    while (<DFH>)
    {
        next if ($_ !~ /^HFPD_[0-9]{6}/);

        chomp;
        my @fields = split " ", $_;
        my $dstart = $fields[1];
        my $dend = $fields[2];
        my $dname = $fields[6];
        my $dentry = {};
        $dentry->{dstart} = $dstart;
        $dentry->{dend} = $dend;
        if (defined($elm_domains->{$dname}))
        {
            if (defined $seq_domains{$dname})
            {
                push(@{$seq_domains{$dname}}, $dentry);
            }
            else
            {
                $seq_domains{$dname} = [ $dentry ];
            }
        }
    }
    close DFH;
    return %seq_domains;
}

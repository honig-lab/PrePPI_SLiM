package MODS::IUPRED;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;

our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

    my $s=shift;
    $s->MODS::Method::ginit();   
    $s->{cmd}="$IFS_HOME/shares/iupred/iupred";
    $ENV{IUPred_PATH} = "$IFS_HOME/shares/iupred" if not defined $ENV{IUPred_PATH};
    $s->{output}="$s->{seqd}/disorder.fa" if defined $s->{seqd};
    return $s;
}

sub default_opts() {

    my $s=shift;
    die "Input sequence not defined" if not defined $s->{seqfn}; 
    die "Input file not $s->{seqfn}" if not -e $s->{seqfn}; 
    my $pgmopts=" $s->{seqfn} long "; 

    return $pgmopts;
}

sub run {
    
    my $s=shift;

    my @dis=`$s->{cmd} $s->{seqfn} long}`;
    die "IUPRED Failed" if !@dis; 
    
    my $dis_fn="$s->{seqd}/disorder.fa";
    open(OUT,">$dis_fn") or die("Could not open $dis_fn.");
    print OUT ">disorder\n";
    foreach (@dis) {
        if ($_ =~ /^#/) { next; }
        my @parts = split (' ',$_);
        if ($parts[2] > .5 ) { print OUT "D"; }
        else { print OUT "-"; }
    }
    
    print OUT "\n";
    close OUT;

    `chmod 666 $dis_fn`;

}

sub complete {

    my $s=shift;
    return 1 if -e "$s->{seqd}/disorder.fa";
    return 0;

}

1;
        

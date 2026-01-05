package MODS::Orthologs;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::Method::ginit();
     $s->{qres}="time=4:00:00";
     $s->{cmd}="$MAIN_DIRECTORY/SCR/orthologs_search.pl";
     $s->{output}=$s->{ortho_groups};
}


sub run {
    my $s=shift;
    my $genome=$s->{genome};
    my $home=$genome->home();
    
    if(length($s->{gid}) > 6)
    {
        print STDERR "Not full protein. Ignore\n";
        return;
    }
    
    my $uni1=$genome->seqUniId_original($s->{gid});    
    
    if(! (-d "$s->{seqd}/Orthology"))
    {
	mkdir "$s->{seqd}/Orthology"; 
    }
        
    
    $s->{pgmopts}=" -p $uni1  > $s->{output}";
    $s->MODS::Method::run();
    `chmod g+rw $s->{output}`;

}

sub count_jobs {
    my $s=shift;
    return 0 if (length($s->{gid}) > 6);
    return 1;
}


package MODS::InParanoid;
use strict;
use warnings;
use MODS::Globals;
our @ISA=qw(MODS::Orthologs);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::Orthologs::ginit();
     $s->{cmd}="$MAIN_DIRECTORY/SCR/inparanoid_search.pl";
     $s->{output}=$s->{inparanoid_groups};
}

sub count_jobs {
    my $s=shift;
    return 0 if (length($s->{gid}) > 6);
    return 1;
}

package MODS::Gopher;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
#use MODS::PDB;

our @ISA=qw(MODS::Orthologs);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

    my $s=shift;
    $s->MODS::Method::ginit();
    $s->{cmd}="/usr/bin/python3 $GOPHER_BIN";
    $s->{qres}="mem=32G";
    $s->{output}= $s->{gopher_groups};

    # Set the following to 1 in order to debug the output of the gopher
    # program. We generally use the value of 0 to conserve file space.
    $s->{debug}=0;
}

sub run {
    
    my $s=shift;
    die "Domain. Not Orthology computed" if (length($s->{gid})>6);
    die "Input sequence not defined" if not defined $s->{seqfn}; 
    die "Input file not $s->{seqfn}" if not -e $s->{seqfn}; 
    chdir $s->{wrkdir};
    my $input=$s->{seqfn};
    my $output="./input.fa";
    open(INPUT,"<$input") or die("Could not open $input");
    open(OUTPUT,">$output") or die("Could not open $output");
    my $header=<INPUT>;
   
    my $repID;
    if($header=~m/RepID=(.*)/)
    {
	$repID=$1;
    }
    else
    {
	my @items=split(/[ \|]/,$header);
	$repID=$items[1];
	if(!($repID=~m/\_/))
	{
	    $repID=$items[2];
	    if(!($repID=~m/\_/))
	    {
		print STDERR "No Species known. Abort\n";
		return;
	    }
	}
    }
    
    my $new_header=">sp|$s->{gid}|$repID\n";
    print OUTPUT "$new_header";
    while (<INPUT>)
    {
	print OUTPUT $_;
    }
    close INPUT;
    close OUTPUT;
    
    $s->{pgmopts}=" orthfas gopher=input.fa orthdb=$GOPHER_DB blastpath=$BLASTCMD";
    $s->MODS::Method::run();
    
    if(!-e "ORTH/$s->{gid}.orth.fas")
    {
	print STDERR "No Orthologs found\n";
	return;
    }
    
    #this shold be done in Method
    my $dir="$s->{seqd}/Orthology";
    if(!-d $dir)
    {
	mkdir $dir;
    }
    
    print STDERR `mv ORTH/$s->{gid}.orth.fas $dir/gopher.fas`;
    
    open(INPUT2,"<ORTH/$s->{gid}.orth.id") or die("Could not open ORTH/$s->{gid}.orth.id");
    my $string="";
    while(<INPUT2>)
    {
	my $line=$_;
	chomp $line;
	$line=~m/__(.*)/;
	my $id=$1;
	$string.="$id|";
    }
    close INPUT2;
   
    if($string)
    {
	open(OUTPUT2,">$s->{output}") or die("Could not open $s->{output}");
	print OUTPUT2 "gopher\t$string\n";
	close OUTPUT2;
        `chmod g+rw $s->{output}`;
    }

    # The output of the gopher program will be produced if $s->{debug} is any
    # value other than 0. It will be located in $s->{wrkdir}, which is in the
    # "scratch" dir of shares/hfpd/PrePPI/{genome}/Pipeline_{id}/Gopher
    if($s->{debug} == 0)
    {
        print STDERR `rm $s->{wrkdir}/*.*`;
        print STDERR `rm -rf ORTH`;
        print STDERR `rm -rf PARA`;
        print STDERR `rm -rf BLAST`;
    }
    
}
    
sub count_jobs {
    my $s=shift;
    return 0 if (length($s->{gid}) > 6);
    return 1;
}

1;
        


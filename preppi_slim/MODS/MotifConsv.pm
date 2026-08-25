package MODS::MotifConsv;
use strict;
use warnings;
use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::Method::ginit();
     $s->{cmd}="$MAIN_DIRECTORY/SCR/get_motif_consv.pl";
     $s->{holds}="MuscleG,FindMotifs_ELM";
     return $s if not defined $s->{seqd};
     $s->{output}="$s->{seqd}/Motifs/motif_elm.csv";
     $s->{input}="$s->{seqd}/Aligns/Gopher.csv";
     $s->{input2}="$s->{seqd}/Motifs/motif_elm.txt";
     return $s;
}

sub run {
    
    my $s=shift;
    
    return if ( ($s->{gid} =~ m/\.e/) ||  ($s->{gid} =~ m/\.d/) || ($s->{gid} =~ m/\.g/)  );
    
    if(-e $s->{input} && -e $s->{input2}) {
        my $aux_out=$s->{wrkdir}."/output.txt";
        
        open MOTIFS, "<", $s->{input2} or die "Cannot open file $s->{input2} to read from!\n";
        open OUT, ">", $aux_out or die "Cannot open file $aux_out to read from!\n";
        print OUT "# record_type=conserved_ELM_SLIM_candidates\n";
        print OUT "# genome=$s->{gname}\tprotein=$s->{gid}\n";
        print OUT "# ELM_class\tmotif_sequence\tmotif_start\n";
        while(<MOTIFS>)
        {
            my $line=$_;
            next if $line =~ /^#/ || $line =~ /^\s*$/;
            chomp $line;
            my ($pdb,$seq,$init)=split(' ',$line);
            my $final=$init+length($seq)-1;
            $s->{pgmopts}=" -i ".$init." -f ".$final."  -c ".$s->{input} ;
            my ($consv)=$s->MODS::Method::run();
            chomp($consv);
            print STDERR "$consv\n";
            print OUT "$pdb\t$seq\t$init\n" if ($consv==1);
        }
        close MOTIFS;
        close OUT;
        print STDERR `mv $aux_out $s->{output}`;    
    }
    
}

sub count_jobs {
    my $s=shift;
    return 0 if ( ($s->{gid} =~ m/\.e/) ||  ($s->{gid} =~ m/\.d/) || ($s->{gid} =~ m/\.g/)  );
    return 1;
}

1;
        

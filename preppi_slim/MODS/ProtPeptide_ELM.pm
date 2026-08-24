package MODS::ProtPeptide_ELM;

use strict;
use warnings;

use MODS::Globals;
use MODS::Method;
our @ISA=qw(MODS::Method);

sub pname { __PACKAGE__ =~ /MODS::(.+)/; return $1; }

sub ginit {

     my $s=shift;
     $s->MODS::Method::ginit();
     $s->{holds}="FindPRDs_ELM,FindMotifs_ELM,MotifConsv,IUPRED";
     $s->{qres}="time=12:00:00";
     $s->{output_fn}="ProtPeptide_ELM.txt";
     return $s if not defined $s->{seqd} or not defined $s->{gname};
     $s->{disorder}="$s->{seqd}/disorder.fa";
     $s->{motif}="$s->{seqd}/Motifs/motif_elm.txt";
     $s->{csv}="$s->{seqd}/Motifs/motif_elm.csv";
     
     $s->{output}=$s->{seqd}."/Motifs/$s->{output_fn}.tar.gz";
     $s->{genome2}=$s->{genome}; # Default: genome2 = genome1
     # Mentioning the full path because $s->{pipedir} is not working.
     # ProtPeptide_ELM is the name of the pipeline as per run_PrP_ELM_batches.pl
     my $g2_file = "$GENOME_DIRECTORY/$s->{gname}/Pipeline/ProtPeptide_ELM.pip/ProtPeptide_ELM.g2";

     if (-e $g2_file) {
         open(G2, "<", $g2_file) or die "Cannot open $g2_file to read genome2\n";
         my $external_genome = <G2>;
         chomp $external_genome;
         close G2;

         if ($external_genome ne "") {
             if (!-d "$GENOME_DIRECTORY/$external_genome") {
                 print STDERR "Error: Genome $external_genome does not exist\n";
                 return 0;
             }
             $s->{genome2} = new MODS::Genome(gname => $external_genome);
             $s->{output} = "$s->{seqd}/Motifs/$external_genome\_$s->{output_fn}.tar.gz";
         }
     }
     return $s;
}

sub run {
    my $s=shift;
    
    #check PRDs which over the cutoffs
    if(-e $s->{motif})
    {
        
        my %motif=();
        my %motif_class=();
        my %motif_init=();
        my %motif_end=();
        my %motif_csv=();
        my $cont_motif=0;
        open MTF, "<", $s->{motif} or die "Cannot open file $s->{motif} to read from!\n";
        while(<MTF>)
        {
            my $line=$_;
            chomp $line;
            my ($class,$peptide,$init,$end)=split(' ',$line);
            my $label=$peptide."_".$class."_".$init;
            $motif{$label}=$peptide;
            $motif_class{$label}=$class;
            $motif_init{$label}=$init;
            $motif_end{$label}=$end;
            $motif_csv{$label}=0;
            $cont_motif++;
        }
        close MTF;
        	
        if ($cont_motif==0) {
            my $aux_out=$s->{wrkdir}."/$s->{output_fn}";
            open OUT, ">", $aux_out or die "Cannot create empty result $aux_out!\n";
            close OUT;
            system('tar', '-C', $s->{wrkdir}, '-zcf', $s->{output}, $s->{output_fn}) == 0
                or die "Cannot archive empty protein-peptide result for $s->{gid}\n";
            return;
        }
        if(-e $s->{csv})
        {
            open CSV, "<", $s->{csv} or die "Cannot open file $s->{csv} to read from!\n";
            while(<CSV>)
            {
                my $line=$_;
                chomp $line;
                my ($class,$peptide,$init)=split(' ',$line);
                my $label=$peptide."_".$class."_".$init;
                $motif_csv{$label}=1 if(defined $motif_csv{$label});
            }
            close CSV; 
        }
        
        my %pos=read_disorder($s->{disorder});
        my %motif_dis=();
        foreach my $key (sort keys %motif)
        {
            my $cont=0;
            for(my $i=$motif_init{$key};$i<=$motif_end{$key};$i++)
            {
                $cont+=$pos{$i};
            }
            my $final=$cont/($motif_end{$key}-$motif_init{$key}+1);
            $motif_dis{$key}=$final;
        }
        my $aux_out=$s->{wrkdir}."/$s->{output_fn}";
        open OUT, ">", $aux_out or die "Cannot open file $aux_out to read from!\n";
            my @targets=$s->{genome2}->get_target_list(); 
            foreach my $target (@targets)
            {    
                my $motifF="$s->{genome2}->{home}/Seqs/$target/Motifs/prd_elm.txt";     
                if(-e $motifF)
                {
                    open MOTIF, "<", $motifF or die "Cannot open file $motifF to read from!\n";
                    while(<MOTIF>)
                    {
                        my $line=$_;
                        chomp $line;
                        my ($class,$type,$init,$end)=split(' ',$line);
                        foreach my $key (sort keys %motif)
                        {
                            next if(!($class eq $motif_class{$key}));
                            print OUT "$s->{gid}\t$target\t$class\t$init\t$end\t$motif{$key}\t$motif_init{$key}\t$motif_end{$key}\t$motif_csv{$key}\t$motif_dis{$key}\n";
                        }
                    }
                    close MOTIF;
                }
            }
        close OUT;
        print STDERR `sort -o $aux_out $aux_out`;
        print STDERR `cd $s->{wrkdir} && tar -zcf $s->{output} $s->{output_fn}`;
    }
    
    
}

sub count_jobs {
    my $s=shift;
    return 0 if length($s->{gid})>6;
    return 1;
}
    
sub read_disorder
{
    my $input=shift;
    my %pos=();
    if(-e $input)
    {
        open DIS, "<", $input or die "Cannot open file $input to read from!\n";
        my $cont=1;
        while(<DIS>)
        {
            my $line=$_;
            chomp $line;
            next if($line =~ m/disorder/);
            my @positions=split(//,$line);
            foreach my $position (@positions)
            {
                if($position eq "D")
                { $pos{$cont}=1;}
                else {$pos{$cont}=0;}
                $cont++;
            }
        }
        close DIS;
    }
    return %pos;
}

1;

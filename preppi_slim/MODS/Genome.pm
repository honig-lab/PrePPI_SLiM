package MODS::Genome;
use File::Temp qw/ tempfile /;
use strict;
use warnings;
use Carp;

use MODS::Globals;

sub new {

    my ( $class, %args ) = @_;

    my $s = bless {}, $class;

    foreach (keys %args) { $s->{$_}=$args{$_}; }

    die( "Error: Please specify a genome name.\n") if not defined $s->{gname};
    my $gdir=$GENOME_DIRECTORY;
    $gdir.="/server" if $s->{gname}=~/^HFPD/;
    $s->{home}="$gdir/$s->{gname}";
    $s->{ixndir}="$s->{home}/Interactions";
    $s->{parse}='no';
    $s->{mk_tgt_dirs}='no';
    return $s;

}

#create Directory project
sub init {
    
    my $s = shift;
    my $fastafn=shift;
    my %args=@_;
 
    $s->{parse}=$args{parse} if defined $args{parse};
    $s->{domdb}=$args{domdb} if defined $args{domdb};
    $s->{mk_tgt_dirs}=$args{mk_tgt_dirs} if defined $args{mk_tgt_dirs};

    umask 000;

    my $home=$s->{home};
    do { mkdir ($home,0775) or die("Error: cannot create genome directory $home: $!\n"); }
    unless -d $home;  
    print STDERR "Using home directory $home.\n";
    
    my $rcdir="$s->{home}/Rescorr";
    print STDERR "Creating rescorr directory $rcdir ...\n";
    do { mkdir ($rcdir,0775) or die("Error: cannot create seq directory $rcdir: $!\n"); }
    unless -d $rcdir;  
    my @dirs=`ls -f $PDBCHAIN_DIR | grep -P "^..\$"`;
    for(@dirs) { chomp; mkdir ("$s->{home}/Rescorr/$_",0775) if not -d $_; }
    @dirs=`ls -f $DOM_DIR | grep -P "^..\$"`;
    for(@dirs) { chomp; mkdir ("$s->{home}/Rescorr/$_",0775) if not -d $_; }

    my $seqdir="$s->{home}/Seqs";
    do { mkdir ($seqdir,0775) or die("Error: cannot create seq directory $seqdir: $!\n"); }
    unless -d $seqdir;  
    print STDERR "Using seq directory $seqdir.\n";

    my $tmpdir="$s->{home}/tmp";
    do { mkdir ($tmpdir,0775) or die("Error: cannot create tmp directory $tmpdir: $!\n"); }
    unless -d $tmpdir;  
    print STDERR "Using tmp directory $tmpdir.\n";
    
    my $pipedir="$s->{home}/Pipeline";
    do { mkdir ($pipedir,0775) or die("Error: cannot create pipeline directory $pipedir: $!\n"); }
    unless -d $pipedir;  
    print STDERR "Using pipeline directory $pipedir.\n";

    my $ixndir="$s->{home}/Interactions";
    do { mkdir ($ixndir,0775) or die("Error: cannot create interaction directory $ixndir: $!\n"); }
    unless -d $ixndir;  
    print STDERR "Using interaction directory $ixndir.\n";

    $s->mk_fasta_dir($fastafn);
    if($s->{mk_tgt_dirs} eq 'yes') {
        print STDERR "Making target directories...\n";
        my @tgts=$s->get_target_list();
        for(@tgts) {
           $s->mk_tgt_dir($_);
        }
    }
    return 1;

}

sub mk_fasta_dir {

    my $s=shift;
    my $fastafn=shift;
    
    umask 000;
    my $fastadir="$s->{home}/fasta";
    do { mkdir ($fastadir,0775) or die("Error: cannot create fasta directory $fastadir: $!\n"); }
    unless -d $fastadir;  
    print STDERR "Using fasta directory $fastadir.\n";

    my $i=1;
    `cat $fastadir/id_list | cut -c 1-6 | sort -u | wc -l`=~/(\d+)/ if -e "$fastadir/id_list";
    $i=$1+1 if -e "$fastadir/id_list";

    my $idlist="$fastadir/id_list";
    open OUTPUT_LIST, ">>", $idlist or die "Can't open $idlist: $!";
    
    open INPUT, "<", $fastafn or die "Can't open $fastafn: $!";

    print STDERR "Creating fasta files...\n";

    my @tgts;
    while(<INPUT>)
    {
        my $line=$_;
        if($line =~ m/^>/)
        {
            my $id=sprintf("%06i",$i++);
            if($line=~/HFPD_\d{6}[.a-z0-9\-_]*/) {
                $line=~/HFPD_(\d{6}[.a-z0-9\-_]*)/;
                $id=$1;
            }
            else { $line=~ s/^>/>HFPD_$id;/; }
	    push(@tgts,$id); 
                
            if(-e "$fastadir/$id") { 
                print STDERR "Fasta file for $id exists.  Skipping.\n";
                next;
            }

            print OUTPUT_LIST "$id\n";
	    
            close OUTPUT;
            open OUTPUT, ">", "$fastadir/$id" or die "Can't open $fastadir/$id: $!";
            
        }
        
        print OUTPUT $line;
        
    }
    
    close INPUT;
    close OUTPUT;
    close OUTPUT_LIST;
    
    if($s->{parse} eq 'yes') { $s->parse_domains($s->{domdb},@tgts); }
    
    $s->create_mapping(@tgts);

}


sub mk_tgt_dir {

    my $s=shift;
    my $seq=shift;
    my $seqdir="$s->{home}/Seqs";
    umask 000;
    do { mkdir ("$seqdir/$seq",0775) or die("Error: cannot create directory $seqdir/$seq.\n"); } unless -d "$seqdir/$seq";  
    do { mkdir ("$seqdir/$seq/Profiles",0775) or die("Error: cannot create directory $seqdir/$seq/Profiles.\n"); } unless -d "$seqdir/$seq/Profiles";  
    do { mkdir ("$seqdir/$seq/Models",0775) or die("Error: cannot create directory $seqdir/$seq/Models.\n"); } unless -d "$seqdir/$seq/Models";  
    do { mkdir ("$seqdir/$seq/GO",0775) or die("Error: cannot create directory $seqdir/$seq/GO.\n"); } unless -d "$seqdir/$seq/GO";  
    do { mkdir ("$seqdir/$seq/Aligns",0775) or die("Error: cannot create directory $seqdir/$seq/Aligns.\n"); } unless -d "$seqdir/$seq/Aligns";  
    do { mkdir ("$seqdir/$seq/Templates",0775) or die("Error: cannot create directory $seqdir/$seq/Templates.\n"); } unless -d "$seqdir/$seq/Templates";  
    do { mkdir ("$seqdir/$seq/Nbr",0775) or die("Error: cannot create directory $seqdir/$seq/Nbr.\n"); } unless -d "$seqdir/$seq/Nbr";
    do { mkdir ("$seqdir/$seq/Coexpression",0775) or die("Error: cannot create directory $seqdir/$seq/Coexpression.\n"); } unless -d "$seqdir/$seq/Coexpression";  
    do { mkdir ("$seqdir/$seq/Structure",0775) or die("Error: cannot create directory $seqdir/$seq/Structure.\n"); } unless -d "$seqdir/$seq/Structure";  
    do { mkdir ("$s->{home}/Pipeline/Pipeline_$seq",0775) or die("Error: cannot create directory $s->{home}/Pipeline/Pipeline_$seq.\n"); } unless -d "$s->{home}/Pipeline/Pipeline_$seq";  
    do { print STDERR `ln -s $s->{home}/Pipeline/Pipeline_$seq $seqdir/$seq/Pipeline`; } unless -d "$seqdir/$seq/Pipeline";
    do { mkdir ("$seqdir/$seq/PredInterface",0775) or die("Error: cannot create directory $seqdir/$seq/PredInterface.\n"); } unless -d "$seqdir/$seq/PredInterface";
    do { mkdir ("$seqdir/$seq/Interactions",0775) or die("Error: cannot create directory $seqdir/$seq/Interactions.\n"); } unless -d "$seqdir/$seq/Interactions"; 
    do { mkdir ("$seqdir/$seq/Motifs",0775) or die("Error: cannot create directory $seqdir/$seq/Motifs.\n"); } unless -d "$seqdir/$seq/Motifs"; 

}


#Extract domains (and regions between domains) and introduces them in new fasta files
sub parse_domains
{
    my $s = shift;
    my $domdb=shift;
    my @tgts=@_;

    if(not defined($domdb)) { $domdb="cdd"; }

    die "No targets specified for parse_domains." if not scalar(@tgts);

    my $fastadir="$s->{home}/fasta";
    my $idlist="$fastadir/id_list";
    open OUTPUT_LIST,">>",$idlist or die "Can't open $idlist: $!";
    foreach my $id (@tgts) {
	my ($seq,$desc)=$s->seq_data($id);
	if(length($seq)<50) { next; }
	my %doms=MODS::CDSearch_Service->run_extended_search($id,$seq,$domdb);
	 
	for (keys %doms)
	{
	    my $newid=$_;
	    chomp $newid;
	    open FASTA, ">", "$fastadir/$newid" or warn "Can't open $fastadir/$newid: $!";
	    $doms{$newid}=~s/\n/$desc\n/;
	    print FASTA "$doms{$newid}";
	    close FASTA;
	    print OUTPUT_LIST $newid."\n";
	}
	
    }
    close OUTPUT_LIST;
}
    
#return all targets (proteins and domains) in the genome
sub get_target_list
{
    my $s=shift;
    my $model_lr_cutoff=shift;
    
    my $idlist="$s->{home}/fasta/id_list";
    my @list=();
    open TARGET, "<", $idlist or die  "Can't open $idlist: $!";
    while(<TARGET>)
    {
	my $line=$_;
	chomp $line;
	next if($line=~m/\.g/ && (!defined($ENV{HFPD_WITHGAPS}) || $ENV{HFPD_WITHGAPS}==0) );
	push @list,$line;
    }
    close TARGET;
    return @list if (! defined $model_lr_cutoff);
    
    my @list2={};
    foreach my $target (@list)
    {
	if($s->check_model_lr($target,$model_lr_cutoff))
	{
	    push @list2,$target;
	}
    }
    return @list2;
}

sub tgt_list_fn {

    my $s=shift;

    return "$s->{home}/fasta/id_list";

}

sub get_tgt_id {

    my $s=shift;
    my $tgtidx=shift;
    die "No target id specified" if not defined $tgtidx;
    my $tgtid=`head -$tgtidx $s->{home}/fasta/id_list | tail -1`;
    chomp $tgtid;
    return $tgtid;

}

    
sub seq_data 
{

    my $s=shift;
    my $id=shift;

    my $fastadir="$s->{home}/fasta";
    my $fn="$fastadir/$id";

    open FASTA, "<", $fn or die("Could not open $fn.\n");
    my @data=<FASTA>;
    close FASTA;

    my ($seq,$desc);

    for(@data) {
      chomp;
      if(/^>/) { $desc=substr($_,1); next; }
      $seq.=$_;
      } 

    return ($seq,$desc)
}

sub seq
{
    my $s=shift;
    my $id=shift;
    my ($seq,$desc)=$s->seq_data($id);
    return $seq;
}

sub seqfn 
{
    my $s=shift;
    my $id=shift;
    return "$s->{home}/fasta/$id";
}

sub seqd 
{
    my $s=shift;
    my $id=shift;

    return "$s->{home}/Seqs/$id";
}

sub seqUniId
{
    my $s=shift;
    my $id=shift;
    my $seqsdir="$s->{home}/Seqs";
    
    my $file=$seqsdir."/$id/Aligns/Uniprot_info.txt";
    
    if(! (-e  $file))
    {
	return "NULL";
    }
    open UNI, "<", $file or die("Could not open $file.\n");
    my $line=<UNI>;
    close UNI;

    chomp $line;
    my @words=split(/\t/,$line);
    
    if($words[0])
    {
	return $words[0];
    }
    
    return "NULL";
}

sub seqUniId_original
{
    my $s=shift;
    my $id=shift;
    
    my $desc=$s->seq_data($id);
    if(defined $desc)
    {
	if($desc=~ /UniRef100_([A-Z0-9]{6,10})/)
	{
	    return $1;
	}
	elsif($desc=~ /\|([A-Z0-9]{6,10})\|/)
	{
	    return $1;
	}	
    }
    
    return $s->seqUniId($id);
}

sub desc
{
    my $s=shift;
    my $id=shift;
    my ($seq,$desc)=$s->seq_data($id);
    return $desc;
}

sub home
{
    my $s=shift;
    return $s->{home};
}


#returns file with PDB structure if exists.
sub getStructure
{
    my $s=shift;
    my $id=shift;
    
    my $file="$s->{home}/Seqs/$id/Models/$id.pdb";
    my $file2="$s->{home}/Seqs/$id/Models/$id"."_m.pdb";
    
    if(-s $file)
    {
	return $file;
    }
    elsif(-s $file2)
    {
	return $file2;
    }
    
    return "NULL";
}

sub get_native_struct {

  my $s=shift;
  my $id=shift;
  my $desc=$s->desc($id);
  return "nf" unless $desc=~/pdb:(\w+)/;
  return $1 if -e $1;
  return "nf";

}

sub get_alignment
{
    my $s=shift;
    my $id=shift;
    my $nbr=shift;
    my $chain=shift;
    
    my ($fh, $fn) = tempfile( "XXXXX", DIR => "/tmp", SUFFIX=>".rescorr");
    my $file=$s->seqd($id)."/Nbr/rescorr.txt";
    if(-e "$file.gz") {
        `cp $file.gz $fn.gz`;
        `gzip -d $fn.gz`;
    } else {
        `cp $file $fn`;
    }
    $file=$fn;
    $file=~s/\.gz//;
    my $protein=lc($nbr)."_".uc($chain);
    my $domain="d".lc($nbr).lc($chain);
    my @aligns=();; 
    return @aligns if (! -s $file);
    
    my %explored=();
    open FILE, $file or die "Can't open $file: $!";
    while(<FILE>)
    {
	my $line=$_;
	chomp $line;
	next if( (!($line =~ m/($protein)/)) && (!($line =~ m/($domain)/)));
	my @elements=split(/\t/,$line);
	next if(! defined $elements[2] );
	if(! defined $explored{$elements[2]})
	{
	    $explored{$elements[2]}=1;
	    push @aligns,$elements[2];
	}
    }
    close FILE;
    `rm $file`;
    
    return @aligns;
}
  
sub check_model_lr  {
  my $s=shift;
  my $id=shift;
  my $cutoff=shift;
  
  my $model=$s->getStructure($id);
  my $s4="$s->{home}/Seqs/$id/Models/MODELLER_S4_m_p.eval";
  my $modeller="$s->{home}/Seqs/$id/Models/MODELLER_m_p.eval";
  my $pdb="$s->{home}/Seqs/$id/Models/Model_from_pdb";

  return 1 if(-e $pdb && -s $model);
  return 0 if(! -s $model);

  my $eval_file;
  if(-s  $s4){ $eval_file=$s4;}
  elsif(-s $modeller) { $eval_file=$modeller; }

  return 0 if (! defined $eval_file);

  open FILE, "<", $eval_file or die("Could not open $eval_file.\n");
  my $firstLine = <FILE>; 
  close FILE;

  my @tokens=split(' ',$firstLine);
  my $ratio=$tokens[2];
  if($ratio>=$cutoff){ return 1;}
  return 0;
}

  
sub create_mapping
{
  my $s=shift;
  my @list=@_;
  my $fastadir="$s->{home}/fasta";
  my $maplist="$fastadir/map_list";
  
  open OUTPUT_LIST, ">>", $maplist or die "Can't open $maplist: $!";
  foreach my $id (@list)
  {
    if(length($id) == 6)
    {
	my $id2=$s->seqUniId_original($id);
	if(! defined $id2 || $id2 eq "NULL")
	{
	    $id2=$id;
	}
	print OUTPUT_LIST "$id\t>$id2\n"
    }
  }
  close OUTPUT_LIST;
}
 
sub get_mapping
{
  my $s=shift;
  my $inverse=shift;
  my $fastadir="$s->{home}/fasta";
  my $maplist="$fastadir/map_list";
  my %hash=();
  open INPUT,$maplist or die "Can't open $maplist: $!";
  while (<INPUT>)
  {
    my $line=$_;
    chomp $line;
    my($id,$uni)=split(/\t>/,$line);
    if((! defined $inverse) || ($inverse==0))
    {
	$hash{$id}=$uni;
    }
    else
    {
	$hash{$uni}=$id;
    }
  }
  close INPUT;
  
  return \%hash;
}

sub get_mapping_uni_gene
{
  my $s=shift;
  my $inverse=shift;
  my $fastadir="$s->{home}/fasta";
  my $maplist="$fastadir/Uniprot_gene";
  my %hash=();
  open INPUT,$maplist or die "Can't open $maplist: $!";
  while (<INPUT>)
  {
    my $line=$_;
    chomp $line;
    my($uni,$genes)=split(/\t/,$line);
    if((! defined $inverse) || ($inverse==0))
    {
	$hash{$uni}=$genes;
    }
    else
    {
	 my @Genes=split(' ',$genes);
	foreach my $gene (@Genes)
	{
	    if(defined $hash{$gene}){$hash{$gene}.=" $uni"}
	    else{$hash{$gene}="$uni"}
	}
    }
  }
  close INPUT;
  
  return \%hash;
}

sub get_mapping_id_gene
{
  my $s=shift;
  my $inverse=shift;
  my $map1=$s->get_mapping($inverse);
  my $map2=$s->get_mapping_uni_gene($inverse);
  my %hash=();
  
  if(!(defined $inverse) || ($inverse==0))
  {
    foreach my $key (keys %$map1)
    {
	if( defined $map2->{$map1->{$key}} ){
	    $hash{$key}=$map2->{$map1->{$key}};
	}
    }
  }
  else
  {
    foreach my $key (keys %$map2)
    {
	my @unis=split(' ',$map2->{$key});
	foreach my $uni (@unis)
	{
	    if( defined $map1->{$uni} ){
		if(defined $hash{$key}){$hash{$key}.=" ".$map1->{$uni}}
		else {$hash{$key}=$map1->{$uni}}
	    }
	}
    }
  }
  return \%hash;
}


sub interaction_reference
{
    my $s=shift;
    my %posiHQ_ppi=();
    my %posi_ppi=();
    ## read in HQ positive interaction reference set
    my $ppiCount = 0;
    
    #HC
    print STDERR "Reading HC interactions\n";
    open ( HQ, $INTERACTIONS_HC );
    while ( my $line = <HQ> )
    {
        chomp $line;
        next if ( $line =~ /^#/ );

	my @fields = split ( /\t/, $line );
	my ($p1,$p2)= split(/\|/,$fields[1]);
	my $pp1 = $p1 . "|" . $p2;
	my $pp2 = $p2 . "|" . $p1;
	$posiHQ_ppi{$pp1} = 1;
	$posiHQ_ppi{$pp2} = 1;
    
	$ppiCount++;
	#last if ( $ppiCount >= 10 );
	if ( ( $ppiCount % 100000 == 0 ) )
	{
	    print STDERR "interactions read: $ppiCount\n";
	    print STDERR "\tTime: ", `date`;
	}
    }
    close HQ;

    #ALL
    print STDERR "Reading All interactions\n";
    open ( ALL, $INTERACTIONS );
    while ( my $line = <ALL> )
    {
        chomp $line;
        next if ( $line =~ /^#/ );

	my @fields = split ( /\t/, $line );
	my ($p1,$p2)= split(/\|/,$fields[1]);
	my $pp1 = $p1 . "|" . $p2;
	my $pp2 = $p2 . "|" . $p1;
	$posi_ppi{$pp1} = 1;
	$posi_ppi{$pp2} = 1;
    
	$ppiCount++;
	#last if ( $ppiCount >= 10 );
	if ( ( $ppiCount % 100000 == 0 ) )
	{
	    print STDERR "interactions read: $ppiCount\n";
	    print STDERR "\tTime: ", `date`;
	}
    }
    close HQ;
    
    return (\%posiHQ_ppi,\%posi_ppi);

}

#Check which analysis has been performed for a target
sub check_target
{
  my $s=shift;
  my $id=shift;
  
  my $dir="$s->{home}/Seqs/$id/";
  
  my $check_model;
  my $check_neigh="NULL";
  my $check_predInt="NULL";
  my $check_ResCorr="NULL";
  my $check_int="NULL";
  my $check_lr="NULL";
  
  #check model
  my $model="$dir/Models/$id.pdb";
  my $model2="$dir/Models/$id"."_m.pdb";
  if(!(-s $model) && !(-s $model2))
  {
    $check_model="NULL";
  }
  else
  {
    if(-e "$dir/Models/Model_from_pdb")
    {
	$check_model="pdb";
    }
    elsif(-e "$dir/Models/Model_from_Modbase")
    {
	$check_model="Modbase";
    }
    elsif(-e "$dir/Models/Model_from_Skybase")
    {
	$check_model="Skybase";
    }
    else
    {
	$check_model="S4";
    }
    
    
    #check skan
    my $neigh="$dir/Nbr/$id.neigh";
  
    if(-s $neigh )
    {
	$check_neigh="OK";
	
	 my $rescorr="$dir/Nbr/rescorr.txt";
	if((-s $rescorr) )
	{
	  $check_ResCorr="OK"; 
	}
	else
	{
	   $check_ResCorr="FAIL"; 
	}
    }
    elsif( -e $neigh)
    {
	$check_neigh="EMPTY";
    }
    else
    {
	$check_neigh="FAIL";
    }
    
    #check Predicted Interface
    my $pred="$dir/PredInterface/$id.int";
    if(-s $pred )
    {
	my @lines=`cat $pred`;
        my $cont= scalar @lines;
        if($cont!=3)
	{
	    $check_predInt="FAIL";
	}
	else
	{
	    $check_predInt="OK";
	}
    }
    else
    {
	$check_predInt="FAIL";
    }
    
    if( ($check_ResCorr eq "OK") && ($check_predInt eq "OK"))
    {
	my $int="$dir/Interactions/$id.int.tar.gz";
	if(-s $int )
	{
	  $check_int="OK";
	}
	elsif( -e $int )
	{
	    $check_int="EMPTY";
	}
	else
	{
	    #print STDERR "$id\n";
	    $check_int="FAIL";
	}
  
    }
#    elsif ($check_ResCorr eq "OK")
#    {
#	print STDERR "no PredInt $id\n";
#    }
#    elsif ($check_predInt eq "OK")
#    {
#	print STDERR "no ResCorr $id\n";
#    }

	my $lr="$dir/Interactions/$id.lr";
	if(-s $lr )
	{
	  $check_lr="OK";
	}
	elsif( -e $lr )
	{
	    $check_lr="EMPTY";
	}
	else
	{
	    $check_lr="FAIL";
	}
  


  }
  
  return ($check_model,$check_neigh,$check_predInt,$check_ResCorr,$check_int,$check_lr);
  
}

sub genome_statistics
{
   my $s=shift;
   my @targets=$s->get_target_list();
   
   my $num_pdb=0;
   my $num_modbase=0;
   my $num_skybase=0;
   my $num_nomodel=0;
    my $num_s4=0;
   
   my $num_pdb_d=0;
   my $num_modbase_d=0;
   my $num_skybase_d=0;
   my $num_nomodel_d=0;
    my $num_s4_d=0;
    
    my $num_skan=0;
    my $num_skan_d=0;
    
    my $num_rescorr=0;
    my $num_rescorr_d=0;
    
    my $num_predint=0;
    my $num_predint_d=0;
    
    my $num_int=0;
    my $num_int_d=0;
    
     my $num_lr=0;
    my $num_lr_d=0;
    
     my $num_red=0;
    my $num_red_d=0;
    
     my $num_phy=0;
    my $num_phy_d=0;
    
     my $num_ort=0;
    my $num_ort_d=0;
    
     my $num_coex=0;
    my $num_coex_d=0;
    
     my $num_mot=0;
    my $num_mot_d=0;
    
    my $num_goa=0;
    my $num_goa_pred=0;
    
   foreach my $target (@targets)
   {
    #print STDERR "$target\n";
    my ($check_model,$check_neigh,$check_predInt,$check_ResCorr,$check_int,$check_lr)=$s->check_target($target);
    
    my $domain=0;
    if(length($target)>6) {$domain=1}
    
    if($check_model eq "NULL")
    {
	$num_nomodel++;
	if($domain) { $num_nomodel_d++}
    }
    elsif($check_model eq "pdb")
    {
	$num_pdb++;
	if($domain) { $num_pdb_d++}
    }
    elsif($check_model eq "Modbase")
    {
	$num_modbase++;
	if($domain) { $num_modbase_d++}
    }
    elsif($check_model eq "Skybase")
    {
	$num_skybase++;
	if($domain) { $num_skybase_d++}
    }
    else
    {
	$num_s4++;
	if($domain) { $num_s4_d++}
    }
    
    if($check_neigh eq "OK")
    {
	$num_skan++;
	if($domain) { $num_skan_d++}
    }
    #elsif(!($check_model eq "NULL"))
    #{
	#print STDERR "$target\n";
    #}
    
    if($check_ResCorr eq "OK")
    {
	$num_rescorr++;
	if($domain) { $num_rescorr_d++}
    }
    
    if($check_predInt eq "OK")
    {
	$num_predint++;
	if($domain) { $num_predint_d++}
    }
    
    if($check_int eq "OK" || $check_int eq "EMPTY" )
    {
	$num_int++;
	if($domain) { $num_int_d++}
    }
    
    if($check_lr eq "OK")
    {
	$num_lr++;
	if($domain) { $num_lr_d++}
    }
    
    my $dir="$s->{home}/Seqs/$target/";
    
    if(-e "$dir/Interactions/Redundancy.lr")
    {
	$num_red++;
	if($domain) { $num_red_d++}
    }
    
    if(-e "$dir/Profiles/PhylogeneticP.lr")
    {
	$num_phy++;
	if($domain) { $num_phy_d++}
    }
    
    if(-e "$dir/Orthology/ortho_pairs.lr")
    {
	$num_ort++;
	if($domain) { $num_ort_d++}
    }
    
    if(-e "$dir/Coexpression/coexpscore.lr")
    {
	$num_coex++;
	if($domain) { $num_coex_d++}
    }

    if(-e "$dir/Motifs/ProtPeptide.lr")
    {
	$num_mot++;
	if($domain) { $num_mot_d++}
    }
    
    if(-e "$dir/GO/$target.goa")
    {
	$num_goa++;
    }
    
    if(-e "$dir/GO/$target.com")
    {
	$num_goa_pred++;
    }
    
    
   }
   
   print STDOUT "Num of targets with pdb model: $num_pdb ($num_pdb_d)\n";
   print STDOUT "Num of targets with Modbase model: $num_modbase ($num_modbase_d)\n";
   print STDOUT "Num of targets with Skybase model: $num_skybase ($num_skybase_d)\n";
   print STDOUT "Num of targets with S4 model: $num_s4 ($num_s4_d)\n";
   print STDOUT "Num of targets with no model: $num_nomodel ($num_nomodel_d)\n";
   
   print STDOUT "\nNum of targets with structural neigbors: $num_skan ($num_skan_d)\n";
   
   print STDOUT "\nNum of targets with residue correspondence: $num_rescorr ($num_rescorr_d)\n";
   
   print STDOUT "\nNum of targets with predicted interface: $num_predint ($num_predint_d)\n";
   
   print STDOUT "\nNum of targets with predicted interactions: $num_int ($num_int_d)\n";
   print STDOUT "Num of targets with LR: $num_lr ($num_lr_d)\n";
   
   print STDOUT "Num of targets with LR redundancy: $num_red ($num_red_d)\n";
   print STDOUT "Num of targets with LR phylogenetic: $num_phy ($num_phy_d)\n";
   print STDOUT "Num of targets with LR orthology: $num_ort ($num_ort_d)\n";
   print STDOUT "Num of targets with LR co-expression: $num_coex ($num_coex_d)\n";
   print STDOUT "Num of targets with LR motif: $num_mot ($num_mot_d)\n";
   print STDOUT "Num of targets with Go terms: $num_goa Predicted: $num_goa_pred\n";
}


sub read_lr
{
    my $pair=shift;
    my $file=shift;
    my $pos_prot=shift;
    my $pos=shift;
    my $pred=shift;
    my $check=shift;
    return if (!(-s $file));
    
    open FILE1,$file or die "cannot open file $file";
    while(<FILE1>)
    {
	my $line=$_;
	chomp $line;
	my @elements=split(' ',$line);
	next if ( !(defined($elements[$pos])) || ($elements[$pos] eq "NULL"));
	
	my $prot1;
	my $prot2;
	
	if($pair==1)
	{
	    my($aux1,$aux2)=split(/[\|-]/,$elements[$pos_prot]);
	    $prot1=substr($aux1,0,6);
	    $prot2=substr($aux2,0,6);
	}
	else
	{
	    $prot1=substr($elements[$pos_prot],0,6);
	    $prot2=substr($elements[$pos_prot+1],0,6);
	}
	my $value=$elements[$pos];
	my $key="$prot1|$prot2";
	if($prot2<$prot1)
	{
	    $key="$prot2|$prot1";
	}

	$check->{$key}=1;
	if( !(defined $pred->{$key}) || ($pred->{$key}<$value))
	{
	    $pred->{$key}=$value;
	}
    }
    close FILE1;
}

sub read_domains_template
{
    my $file=shift;
    my $pred=shift;
    my $info=shift;
    return if (!(-s $file));
    
    open FILE1,$file or die "cannot open file $file";
    while(<FILE1>)
    {
	my $line=$_;
	chomp $line;
	my @elements=split(' ',$line);
	next if ( !(defined($elements[4])) );
	
	my $prot1;
	my $prot2;
	my($aux1,$aux2)=split(/[\|-]/,$elements[0]);
	$prot1=substr($aux1,0,6);
	$prot2=substr($aux2,0,6);

	my $value=$elements[4];
	my $key="$prot1|$prot2";
	my $domains=$elements[1]."|".$elements[2]."|".$elements[5];
	if($prot2<$prot1)
	{
	    $key="$prot2|$prot1";
	    my ($pdb,$chains,$psd1,$psd2,$score1,$score2,$score3)=split(/[\:\(\)\,]/,$elements[5]); #3eab:CE(0.47,0.54,34/38,11,3)
	    my($chain1,$chain2)=split('',$chains);
	    my $newTemplate="$pdb:$chain2$chain1($psd2,$psd1,$score1,$score2,$score3)";
	    $domains=$elements[2]."|".$elements[1]."|".$newTemplate;
	}
	
	if( (defined $pred->{$key}) && ($pred->{$key}==$value))
	{
	    $info->{$key}=$domains;
	}
    }
    close FILE1;
}

sub recollect_all_predictions
{
   my $s=shift;
   my $prefix=shift;
   my @targets=$s->get_target_list(); 
   my %check=();
   my %pred_sc=();
   my %domain_sc=();
   my %pred_ort=();
   my %pred_phy=();
   my %pred_motif=();
   my %pred_coexp=();
   my %pred_predgo=();
   my %pred_predgo_avg=();
   my %pred_redundancy=();
   my %pred_redundancy_pairs=();
   my %pred_combined=();
   my %struct; 
    my $cont=0;
    
    if(defined $prefix)
    {
	$prefix.="_";
    }
    else
    {
	$prefix="";
    }
    
   foreach my $target1 (@targets)
   {
	if(length($target1)==6)
	{
	    my $structF="$s->{home}/Seqs/$target1/Models/$target1"."_m.pdb";
	    $struct{$target1}=1 if (-e $structF);
	}
	
	print STDERR "$target1\n";
	my $file_sc="$s->{home}/Seqs/$target1/Interactions/$prefix$target1.lr";
	my $file_ort="$s->{home}/Seqs/$target1/Orthology/".$prefix."ortho_pairs.lr";
	my $file_phy="$s->{home}/Seqs/$target1/Profiles/".$prefix."PhylogeneticP.lr";
	my $file_motif="$s->{home}/Seqs/$target1/Motifs/".$prefix."ProtPeptide.lr";
	my $file_redundancy="$s->{home}/Seqs/$target1/Interactions/".$prefix."Redundancy.lr";
	my $file_redundancy_pairs="$s->{home}/Seqs/$target1/Interactions/".$prefix."Redundancy_pairs.lr";
	my $file_coexp="$s->{home}/Seqs/$target1/Coexpression/".$prefix."coexpscore.lr";
	my $file_predgo="$s->{home}/Seqs/$target1/GO/".$prefix."GO.lr";
	#my $file_predgo_avg="$s->{home}/Seqs/$target1/GO/GO_avg.lr";
	#my $file_combined="$s->{home}/Seqs/$target1/Interactions/CombinedStLR.lr";
	#my $file_combined="$s->{home}/Seqs/$target1/Interactions/Combined2.lr";
	
	
	read_lr(1,$file_sc,0,4,\%pred_sc,\%check);
	read_domains_template($file_sc,\%pred_sc,\%domain_sc);
	read_lr(1,$file_ort,1,2,\%pred_ort,\%check);
	read_lr(0,$file_phy,0,2,\%pred_phy,\%check);
	read_lr(0,$file_motif,0,5,\%pred_motif,\%check);
	read_lr(0,$file_redundancy,0,2,\%pred_redundancy,\%check);
	read_lr(0,$file_redundancy_pairs,0,2,\%pred_redundancy_pairs,\%check);
	read_lr(0,$file_predgo,0,2,\%pred_predgo,\%check);
	#read_lr(0,$file_predgo_avg,0,2,\%pred_predgo_avg,\%check);
	read_lr(0,$file_coexp,0,2,\%pred_coexp,\%check);
	
	#read_lr(1,$file_combined,0,3,\%pred_combined,\%check);
	$cont++;
	#if($cont==1) {last;}
   }
   my %output=();
    foreach my $key (keys %check)
    {
	my $line;
	my $total_score=-1;	
	
	if(defined $pred_sc{$key}) {  $total_score=$pred_sc{$key} ; $line=sprintf("%.4f",$pred_sc{$key})} else {$line="NULL"}
	
	if( (defined $pred_motif{$key}) && ($pred_motif{$key}>$total_score)) { $total_score=$pred_motif{$key}; }
	
	if(defined $pred_motif{$key}){	$line.="\t".sprintf("%.4f",$pred_motif{$key}) } else { $line.="\tNULL"}

	
	if($total_score==-1) {
	    my ($t1,$t2)=split(/\|/,$key);
	    if((defined $struct{$t1}) && (defined $struct{$t2})) { $line.="\t0.81"; $total_score="\t0.81" }
	    else {$line.="\tNULL"}
	}
	else{$line.="\t".sprintf("%.4f",$total_score)}
	
	if( defined $pred_ort{$key}) {
	    
	    if($total_score==-1){$total_score=$pred_ort{$key}}
	    else{$total_score*=$pred_ort{$key}}
	    $line.="\t".sprintf("%.4f",$pred_ort{$key});
	} else {$line.="\tNULL"}
	
	if( defined $pred_phy{$key}) {
	    if($total_score==-1){$total_score=$pred_phy{$key}}
	    else{$total_score*=$pred_phy{$key}}
    	    $line.="\t".sprintf("%.4f",$pred_phy{$key});
	} else {$line.="\tNULL"}
	
	
	
	if( defined $pred_coexp{$key}) {
	    if($total_score==-1){$total_score=$pred_coexp{$key}}
	    else{$total_score*=$pred_coexp{$key}}
	    $line.="\t".sprintf("%.4f",$pred_coexp{$key});
	} else {$line.="\tNULL"}
	
	my $redundancy_score;
	if( defined $pred_redundancy{$key}) {
	    $redundancy_score=$pred_redundancy{$key};
	} 
	
	if(! defined $redundancy_score)
	{
	 if( defined $pred_redundancy_pairs{$key}) {
	    $redundancy_score=$pred_redundancy_pairs{$key};
	 }   
	}
	
	if( defined $redundancy_score) {
	    if($total_score==-1){$total_score=$redundancy_score}
	    else{$total_score*=$redundancy_score}
	    $line.="\t".sprintf("%.4f",$redundancy_score);
	} else {$line.="\tNULL"}
	
	if( defined $pred_predgo{$key}) {
	    if($total_score==-1){$total_score=$pred_predgo{$key}}
	    else{$total_score*=$pred_predgo{$key}}
	    $line.="\t".sprintf("%.4f",$pred_predgo{$key});
	} else {$line.="\tNULL"}
	
	
	$line.="\t".sprintf("%.4f",$total_score);
	
	
	if(defined $domain_sc{$key})
	{
	    $line.="\t$domain_sc{$key}";
	}
	else
	{
	   $line.="\tNULL"; 
	}	
	$output{$key}=$line;
    }
    return \%output;
}

sub recollect_all_predictions2
{
   my $s=shift;
   my @targets=$s->get_target_list(); 
   my %max_score=();
   my %output=();
   my %struct=();

    my $cont=0;
    
    print STDERR "reading structures\n";
    foreach my $target1 (@targets)
   {
	if(length($target1)==6)
	{
	    my $structF="$s->{home}/Seqs/$target1/Models/$target1"."_m.pdb";
	    $struct{$target1}=1 if (-e $structF);
	}
   }
   print STDERR "finish reading structures\n";
   foreach my $target1 (@targets)
   {
	my %aux_check=();
	my %aux_pred_sc=();
	my %aux_domain_sc=();
	my %aux_pred_ort=();
	my %aux_pred_phy=();
	my %aux_pred_motif=();
	my %aux_pred_coexp=();
	my %aux_pred_redundancy=();
	my %aux_pred_redundancy_pairs=();
	
	
	print STDERR "$target1\n";
	my $file_sc="$s->{home}/Seqs/$target1/Interactions/$target1.lr";
	my $file_ort="$s->{home}/Seqs/$target1/Orthology/ortho_pairs.lr";
	my $file_phy="$s->{home}/Seqs/$target1/Profiles/PhylogeneticP.lr";
	my $file_motif="$s->{home}/Seqs/$target1/Motifs/ProtPeptide.lr";
	my $file_redundancy="$s->{home}/Seqs/$target1/Interactions/Redundancy.lr";
	my $file_redundancy_pairs="$s->{home}/Seqs/$target1/Interactions/Redundancy_pairs.lr";
	my $file_coexp="$s->{home}/Seqs/$target1/Coexpression/coexpscore.lr";	
	
	
	read_lr(1,$file_sc,0,4,\%aux_pred_sc,\%aux_check);
	read_domains_template($file_sc,\%aux_pred_sc,\%aux_domain_sc);
	read_lr(1,$file_ort,1,2,\%aux_pred_ort,\%aux_check);
	read_lr(0,$file_phy,0,2,\%aux_pred_phy,\%aux_check);
	read_lr(0,$file_motif,0,5,\%aux_pred_motif,\%aux_check);
	read_lr(0,$file_redundancy,0,2,\%aux_pred_redundancy,\%aux_check);
	read_lr(0,$file_redundancy_pairs,0,2,\%aux_pred_redundancy_pairs,\%aux_check);
	read_lr(0,$file_coexp,0,2,\%aux_pred_coexp,\%aux_check);
	$cont++;
	
	foreach my $key (keys %aux_check)
	{
	    my $line;
	    my $total_score=0;	
	    my $total_score_redundancy=0;
	    my $total_score_redundancy_pairs=0;
	    if(defined $aux_pred_sc{$key}) { $total_score=$aux_pred_sc{$key} ; $line="$aux_pred_sc{$key}"} else {$line="NULL"}
	    
	    if( (defined $aux_pred_motif{$key}) && ($aux_pred_motif{$key}>$total_score)) { $total_score=$aux_pred_motif{$key}; }
	    
	    if(defined $aux_pred_motif{$key}){	$line.="\t$aux_pred_motif{$key}" } else { $line.="\tNULL"}
    
	    
	    if($total_score==0) {
		my ($t1,$t2)=split(/\|/,$key);
		if((defined $struct{$t1}) && (defined $struct{$t2})) { $line.="\t0.81"; $total_score="\t0.81" }
		else {$line.="\tNULL"}
	    }
	    else{$line.="\t$total_score"}
	    
	    if( defined $aux_pred_ort{$key}) {
		if($total_score==0){$total_score=$aux_pred_ort{$key}}
		else{$total_score*=$aux_pred_ort{$key}}
		$line.="\t$aux_pred_ort{$key}"
	    } else {$line.="\tNULL"}
	    
	    if( defined $aux_pred_phy{$key}) {
		if($total_score==0){$total_score=$aux_pred_phy{$key}}
		else{$total_score*=$aux_pred_phy{$key}}
		$line.="\t$aux_pred_phy{$key}"
	    } else {$line.="\tNULL"}
	    
	    
	    
	    if( defined $aux_pred_coexp{$key}) {
		if($total_score==0){$total_score=$aux_pred_coexp{$key}}
		else{$total_score*=$aux_pred_coexp{$key}}
		$line.="\t$aux_pred_coexp{$key}"
	    } else {$line.="\tNULL"}
	    
	    $total_score_redundancy=$total_score;
	    if( defined $aux_pred_redundancy{$key}) {
		if($total_score_redundancy==0){$total_score_redundancy=$aux_pred_redundancy{$key}}
		else{$total_score_redundancy*=$aux_pred_redundancy{$key}}
		$line.="\t$aux_pred_redundancy{$key}"
	    } else {$line.="\tNULL"}
	    
	    
	    $total_score_redundancy_pairs=$total_score;
	    if( defined $aux_pred_redundancy_pairs{$key}) {
		if($total_score_redundancy_pairs==0){$total_score_redundancy_pairs=$aux_pred_redundancy_pairs{$key}}
		else{$total_score_redundancy_pairs*=$aux_pred_redundancy_pairs{$key}}
		$line.="\t$aux_pred_redundancy_pairs{$key}"
	    } else {$line.="\tNULL"}
	    
	    $line.="\t$total_score_redundancy";
	    $line.="\t$total_score_redundancy_pairs";
	    
	    if(defined $aux_domain_sc{$key})
	    {
		$line.="\t$aux_domain_sc{$key}";
	    }
	    else
	    {
	       $line.="\tNULL"; 
	    }
	    
	    next if((defined $max_score{$key}) && ($max_score{$key}>$total_score_redundancy));
	    
	    $max_score{$key}=$total_score_redundancy;
	    $output{$key}=$line;
	}
	#if($cont==10) {last;}
   }
	
   return \%output;
}

sub recollect_Motif_predictions
{
   my $s=shift;
   my @targets=$s->get_target_list(); 
   my %check=();
   
   my %pred_motif=();
   my %pred_motif_elm=();
   my %struct; 
    my $cont=0;   
   foreach my $target1 (@targets)
   {
	
	print STDERR "$target1\n";
	my $file_motif="$s->{home}/Seqs/$target1/Motifs/ProtPeptide.lr";
	my $file_motif_elm="$s->{home}/Seqs/$target1/Motifs/ProtPeptide_ELM.lr";
	
	read_lr(0,$file_motif,0,5,\%pred_motif,\%check);
	read_lr(0,$file_motif_elm,0,2,\%pred_motif_elm,\%check);
	
	$cont++;
	#last if($cont==100);
   }
   my %output=();
    foreach my $key (keys %check)
    {
	my $line;
	my $total_score=-1;	
	
	if( (defined $pred_motif{$key}) ) { $total_score=$pred_motif{$key}; $line="\t".sprintf("%.4f",$pred_motif{$key})}
	else{$line="\tNULL"}
	
	if( (defined $pred_motif_elm{$key}) && ($pred_motif_elm{$key}>$total_score)) { $total_score=$pred_motif_elm{$key} }
	
	if( (defined $pred_motif_elm{$key})) {  $line.="\t".sprintf("%.4f",$pred_motif_elm{$key}) }
	else{$line.="\tNULL"}
	
	if($total_score > -1){	$line.="\t".sprintf("%.4f",$total_score) } else { $line.="\tNULL"}
	
	$output{$key}=$line;
    }
    return \%output;
}


sub compute_phy_LR
{
   my $s=shift;
   my $out=shift;
   my $IRatio1 = 43999/(6535*6534/2+6535-274606);
   my $map=$s->get_mapping();
   my @totalBin;
   my @posiBin;
   for ( my $binIdx = 0; $binIdx <= 10; $binIdx++ ) {    $totalBin[$binIdx]=0 ; $posiBin[$binIdx]=0 }
   my @targets=$s->get_target_list();
    
   my  ($posiHQ_ppi,$posi_ppi)=$s->interaction_reference();
   my %totalBin=();
   my %posiBin=();
my $cont=0;
   foreach my $target (@targets)
   {
	my $input="$s->{home}/Seqs/$target/Profiles/$target".".corr";
	if(-e $input)
	{
	    open FILE,$input or die "cannot open file $input";
	    while(<FILE>)
	    {
		my $pred=$_;
		chomp $pred;
		my ($tgt1,$tgt2,$sc1,$sc2,$corr)=split(' ',$pred);
		if(not defined $corr)
		{
		    print STDERR "error in file $input: $pred\n";
		    next;
		}
		next if ($corr eq "NULL");
		my $bin=int($corr*10.0);
		my $basic_target=substr($tgt1,0,6);
		my $basic_target2=substr($tgt2,0,6);
		if($basic_target<=$basic_target2)
		{
		   my $aux=$basic_target;
		   $basic_target=$basic_target2;
		   $basic_target2=$aux;
		}
		my $uniprot1=$map->{$basic_target};
		my $uniprot2=$map->{$basic_target2};
		
		next if ( ( defined ($posi_ppi->{"$uniprot1|$uniprot2"}) ) && ( not defined ($posiHQ_ppi->{"$uniprot1|$uniprot2"}) ) );

		
		$totalBin[$bin]++;
		if(defined ($posiHQ_ppi->{"$uniprot1|$uniprot2"}) ) {$posiBin[$bin]++;}
	    }
	    close FILE;
	}
	print STDERR "target $target read\n";
	$cont++;
	#if($cont==1000) {last}
   }
    
    open ( LR, ">$out" ) or die "cannot open file $out";
    for ( my $binIdx = 0; $binIdx <= 10; $binIdx++ )
    {
	my $LR1 = 0;
	if ( $totalBin[$binIdx] == 0 )  {  $LR1 = "NA";   }
	elsif ( $totalBin[$binIdx] == $posiBin[$binIdx] )  {  $LR1 = "INF";   }
	else
	{
	    $LR1 = ($posiBin[$binIdx]/($totalBin[$binIdx]-$posiBin[$binIdx]))/$IRatio1;
	}
    
	print LR $binIdx+1, "\t",$binIdx*0.1, "~", $binIdx*0.1+0.099999, "\t", $posiBin[$binIdx], "\t", $totalBin[$binIdx], "\t", $LR1,  "\n";
    }
    close LR; 
}



sub create_hash_neighbors
{
    my $s=shift;
    
    my $file=$s->{home}."/hash_pdb_targets_old.txt";
    my %hash=();
    my %checked=();
    if(-e $file)
    {
	open ( HASH, "$file" ) or die "cannot open file $file";
	while(<HASH>)
	{
	    my $line=$_;
	    chomp($line);
	    
	    my ($pdb,$targets)=split(' ',$line);
	    $hash{$pdb}=$targets;
	    my @Targets=split(/\|/,$targets);
	    foreach my $target (@Targets)
	    {
		$checked{$target}=1;
	    }
	}
	close HASH;
    }
    
    
    my @targets=$s->get_target_list();
    my $cont=0;
    foreach my $target (@targets)
    {
	$cont++;
	#last if($cont==1000);
	next if($checked{$target});
	
	my $neighbors_file=$s->seqd($target)."/Nbr/$target.neigh.compact";
	if(-e $neighbors_file)
	{
	    my %done=();
	    open ( NEIGH, "$neighbors_file" ) or die "cannot open file $neighbors_file";
	    while(<NEIGH>)
	    {
		my $line=$_;
		chomp $line;
		my($neigh,$psd1,$psd2,$psd3)=split(' ',$line);
		my $pdb;
		if(length($neigh)==6){$pdb=substr($neigh,0,4);}
		else{$pdb=substr($neigh,1,4);}
		next if(defined $done{$pdb});
		if(defined $hash{$pdb})
		{
		    $hash{$pdb}.="|$target";
		}
		else
		{
		    $hash{$pdb}=$target;
		}
		$done{$pdb}=1;
	    }
	    close NEIGH;
	}
    }
    my $file_aux=$s->{home}."/hash_pdb_targets_aux.txt";
    open ( HASH2, ">$file_aux" ) or die "cannot open file $file_aux";
    foreach my $key (sort(keys %hash)) {
	print HASH2 "$key\t".$hash{$key}."\n";
    }
    close HASH2;
    
    print STDERR `mv $file_aux $file `; 
}


sub read_cluster_structures
{
     my $s=shift;
     my %cluster=();
     $s->read_cluster_file(\%cluster,"$PDBCHAIN_DIR/domain60.fa.clstr");
     $s->read_cluster_file(\%cluster,"$PDBCHAIN_DIR/chain60.fa.clstr");
     return \%cluster;
}

sub read_cluster_file
{
    my $s=shift;
    my $cluster=shift;
    my $file=shift;
    
    my $head="empty";
    my $body="";
	
    open (CLS, $file);
    while ( my $line = <CLS> )
    {
	chomp $line;
	if( $line =~ m/^>/ )
	{
	    if (!(defined eq "empty"))
	    {
		$cluster->{$head}=$body;
		$head="empty";
		$body="";
	    }
	}
	else
	{
	    my @elems=split(' ',$line);
	    my $id=$elems[2];
	    my $percent=$elems[-1];
	    $id =~ s/>//;
	    
	    if($percent eq "*")
	    {
		$head=$id;
	    }
	    else
	    {
		$body.="$id-$percent|";
	    }
	}
    }
    close CLS;
}

sub Interface_contacts 
{
    my $s=shift;
    return "$s->{home}/Interface_contacts";
}

sub Neighborhoods
{
    my $s=shift;
    return "$s->{home}/Neighborhoods";
}


sub GOA_Uniprot
{
    my $s=shift;
    return "$s->{home}/GOA_annotations/GOA_uniprot";
}

sub Uniprot_GOA
{
    my $s=shift;
    return "$s->{home}/GOA_annotations/uniprot_GOA";
}

1;

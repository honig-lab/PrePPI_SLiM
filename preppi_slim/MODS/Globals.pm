package MODS::Globals;
use strict;
use warnings;

require Exporter;  
our $VERSION=2.0;  
our @ISA = qw(Exporter);  
our @EXPORT=qw(

    $IFS_HOME
    $IFS_DATA
    $IFS_SCRATCH
    
    $MAIN_DIRECTORY
    $DATABASE_DIR
    $GENOME_DIRECTORY
    $SCRATCH_DIRECTORY
    $SCRATCH_SHARES
    $HFPD_BIN
    $JACKAL_BIN
    $HFPD_SCR
    $HFPD_TEMPLATE_DIR
    $HFPD_TEMPLATES
    $PREPPI_SOURCES
    
    $BLASTBIN
    $BLASTCMD
    $PUDGE
    $SUBMAT
    $TROLLTOP

    $EV_THRESHOLD

    $PDBDOM_DIR
    $DOM_DIR
    $DOM_SEQ
    $DOM_SEQ100

    $PDB_DIR
    $PDBCHAIN_DIR
    $PDBCHAINSEQ100
    $KNOWN_AA
    $PDB_LATEST
    $PDBCHAINSEQ
    $PDBATOMSEQ
    $PDBSEQRES
    $PDBPROT60
    $PDBPROTEIN
    $CD_HIT
    
    $PISA_DIR
    $PISA_WEB
    $PISA_WEB_ASSEMBLIES
    $PISA_WEB_ASSEMBLIES_PDB
    
    $BLAST_DB
    $MEM_BLAST
    $TIME_BLAST

    $UNIPROTDIR
    $UNIPROT100
    $UNIPROT100_TAB
    $UNIPROT90
    $UNIPROT2GO

    $MODBASE_ALIGN
    $MODBASE_EV_HIGH
    $MODBASE_EV_LOW
    $MODBASE_MPQS_HIGH
    $MODBASE_MPQS_LOW
    $MODBASE_FILE
    $MODBASE_DIR

    $UNIPROTMAPPING
    $SKYBASEDB
    $SKYMODELINFO
    
    $PDB_SKAN
    $PDB_SKAN60
    $SKADS
    $SKADS60
    $SKADS_DIR
    $MEM_SKAN
    $TIME_SKAN
    $SKAN_CUTOFF
    $SKAN_SSESIM
    $SKAN_MINLENGTH

    $MEM_INTERFACE 
    $TIME_INTERFACE
    $INTERFACE_BIN
    $PINUPBIN
    $PREDROTPRO
    $PREDUSINTF
    $PREDUS_V2
    $CONSPPISPBIN
    $CONSPPISPWGTL
    $CONSPPISPWGT
    $CONSPPISPMSG
    
    $MEM_LINK
    $TIME_LINK
    $MEM_RESCORR
    $TIME_RESCORR
    $MEM_SCORE
    $TIME_SCORE
    $MAX_ARRAY_VAL

    
    $HUMAN_ALL_POSIT_INT
    $HUMAN_HC_POSIT_INT
    $YEAST_ALL_POSIT_INT
    $YEAST_HC_POSIT_INT
    
    $PDB2PQS
    $PQSINTERFACE
    $PDBINTERFACE
    $BIOUNITINTERFACE
    $PISAINTERFACE
  
    
    $HMAPDIR
    $HMAPCHAIN_DIR
    $HMAPDOM_DIR
    $HMAPALL_DIR 

    $PSDNET
    $BN72NET
    $BN24NET
    $BN56NET
    $BN120NET
    $BN36NET
    
    $BABEL_DATADIR
    
    $MEM_PHYLOGENETIC
    $ORGAUNIPROT
    $NOGCLUSTER
    $NOGPROFILES
    $BNPHYLO
    
    $DBTYPE
    $DBNAME
    $DBHOST
    $DBUSER
    $DBPWD
    $BNCOEXP
    
    $GOPHER_BIN
    $GOPHER_MEM
    $GOPHER_DB
    
    $CDDDIR

    $INTERACTIONS
    $INTERACTIONS_HC
    $ORTHOLOGY_DATABASES
    $ORTHOLOGY_DIRECTORY
    $BNORTHO
    
    $GO_ANCESTORS
    $GO_DEEP
    $GO_INFO
    $BNPREDGO_MIN
    $BNPREDGO_AVG
    
    $GODIR3_HUMAN
	$GODIR4_HUMAN
	$GODIR5_HUMAN
    
    
    $CLUSTER_FILE_PEP
    $IDENTICAL_FILE_PEP
    $CUTS_FILE_PEP
    $IUPRED_PATH
    $INTERFACE_CONTACTS_D
    $PRD_CUTOFF
    $BNMOTIF
    $BNMOTIF_ELM
    $ELM_CLASSES
    $HMMS
    
    $FIBE_DIR
    $FIBE_MEM
    $FIBE_TIME
    
    $DNA_ANALYSIS
    
    $SURF_BIN
    $ATOM_SIZE
    
    $BNRED
    $BNREDP
    
    $BNCOMBINED
    $BNCOMBINED2
    $BNCOMBINED_ST_RED
    
    $CLUSTALW
    $JACKHAMMER
    $JACKHAMMER_DIR
    $MUSCLE
    $UNI_SPROT
    
    $EMAIL_DIR
    $MAILSENDER
    $SENDMAIL
    
    $JOBS_DIR
    
    $DB_HOST
    $DB_USER
    $DB_PASS
    $DB_NAME
    $DB_NAME_SQLITE
    
    $DB_BGSC
    $DB_IASC
    $DB_DPSC
    $DB_MPSC
    $DB_MNSC
    $DB_HPSC
    $DB_MANY
    
    $Rscript
    
    $PREPPI_INTERACTIONS
    $PREPPI_INTERACTIONS_NO_GO
    
    $GSEA_C5_ALL
	$GSEA_KEGG
	$GSEA_LABELS
);

our $MAIN_DIRECTORY;
our $DATABASE_DIR;
our $GENOME_DIRECTORY;
our $SCRATCH_DIRECTORY;
our $SCRATCH_SHARES;
our $JACKAL_BIN;
our $HFPD_BIN;
our $HFPD_SCR;
our $HFPD_TEMPLATE_DIR;
our $HFPD_TEMPLATES;
our $PREPPI_SOURCES;

our $BLASTBIN;
our $BLASTCMD;
our $PUDGE;
our $SUBMAT;
our $TROLLTOP;

our $EV_THRESHOLD;

our $PDBDOM_DIR;
our $DOM_DIR;
our $DOM_SEQ;
our $DOM_SEQ100;

our $PDB_DIR;
our $PDBCHAIN_DIR;
our $PDBCHAINSEQ100;
our $PDBCHAINSEQ;
our $PDBATOMSEQ;
our $KNOWN_AA;
our $PDB_LATEST;
our $PDBSEQRES;
our $PDBPROT60;
our $PDBPROTEIN;
our $CD_HIT;

our $PISA_DIR;
our $PISA_WEB;
our $PISA_WEB_ASSEMBLIES;
our $PISA_WEB_ASSEMBLIES_PDB;

our $BLAST_DB;
our $MEM_BLAST;
our $TIME_BLAST;
    
our $UNIPROTDIR;
our $UNIPROT90;
our $UNIPROT100;
our $UNIPROT100_TAB;
our $UNIPROT2GO;

our $MODBASE_ALIGN;
our $MODBASE_EV_HIGH;
our $MODBASE_EV_LOW;
our $MODBASE_MPQS_HIGH;
our $MODBASE_MPQS_LOW;
our $MODBASE_FILE;
our $MODBASE_DIR;

our $UNIPROTMAPPING;
our $SKYBASEDB;
our $SKYMODELINFO;

our $PDB_SKAN;
our $PDB_SKAN60;
our $SKADS;
our $SKADS60;
our $SKADS_DIR;
our $MEM_SKAN;
our $TIME_SKAN;
our $SKAN_CUTOFF;
our $SKAN_SSESIM=0.6;
our $SKAN_MINLENGTH=3;
    
our $MEM_INTERFACE; 
our $TIME_INTERFACE;
our $INTERFACE_BIN;
our $PINUPBIN;
our $PREDROTPRO;
our $PREDUSINTF;
our $PREDUS_V2;
our $CONSPPISPBIN;
our $CONSPPISPWGTL;
our $CONSPPISPWGT;
our $CONSPPISPMSG;

our $MEM_LINK;
our $TIME_LINK;
our $MEM_RESCORR;
our $TIME_RESCORR;
our $MEM_SCORE;
our $TIME_SCORE;
our $MAX_ARRAY_VAL;


our $HUMAN_ALL_POSIT_INT;
our $HUMAN_HC_POSIT_INT;
our $YEAST_ALL_POSIT_INT;
our $YEAST_HC_POSIT_INT;


our $PDB2PQS;
our $PQSINTERFACE;
our $PDBINTERFACE;
our $BIOUNITINTERFACE;
our $PISAINTERFACE;


our $HMAPDIR;
our $HMAPCHAIN_DIR;
our $HMAPDOM_DIR;
our $HMAPALL_DIR;

our $PSDNET;
our $BN72NET;
our $BN24NET;
our $BN56NET;
our $BN120NET;
our $BN36NET;
our $BABEL_DATADIR;

our $MEM_PHYLOGENETIC;
our $ORGAUNIPROT;
our $NOGCLUSTER;
our $NOGPROFILES;
our $BNPHYLO;

our $DBTYPE;
our $DBNAME;
our $DBHOST;
our $DBUSER;
our $DBPWD;
our $BNCOEXP;

our $GOPHER_BIN;
our $GOPHER_MEM;
our $GOPHER_DB;

our $CDDDIR;

our $INTERACTIONS;
our $INTERACTIONS_HC;
our $ORTHOLOGY_DATABASES;
our $ORTHOLOGY_DIRECTORY;
our $BNORTHO;

our $GO_ANCESTORS;
our $GO_DEEP;
our $GO_INFO;
our $BNPREDGO_MIN;
our $BNPREDGO_AVG;

our $GODIR3_HUMAN;
our	$GODIR4_HUMAN;
our	$GODIR5_HUMAN;

our $CLUSTER_FILE_PEP;
our $IDENTICAL_FILE_PEP;
our $CUTS_FILE_PEP;
our $IUPRED_PATH;
our $INTERFACE_CONTACTS_D;
our $PRD_CUTOFF;
our $BNMOTIF;
our $BNMOTIF_ELM;
our $ELM_CLASSES;
our $HMMS;

our $FIBE_DIR;
our $FIBE_MEM;
our $FIBE_TIME;

our $DNA_ANALYSIS;

our $SURF_BIN;
our $ATOM_SIZE;

our $BNRED;
our $BNREDP;

our $BNCOMBINED;
our $BNCOMBINED2;
our $BNCOMBINED_ST_RED;

our $CLUSTALW;
our $JACKHAMMER;
our $JACKHAMMER_DIR;
our $MUSCLE;
our $UNI_SPROT;

our $EMAIL_DIR;
our $MAILSENDER;
our $SENDMAIL;

our $JOBS_DIR;

our $DB_HOST;
our $DB_USER;
our $DB_PASS;
our $DB_NAME;
our $DB_NAME_SQLITE;

our $DB_BGSC;
our $DB_IASC;
our $DB_DPSC;
our $DB_MPSC;
our $DB_MNSC;
our $DB_HPSC;
our $DB_MANY;

our $Rscript;

our $PREPPI_INTERACTIONS;
our $PREPPI_INTERACTIONS_NO_GO;

our $GSEA_C5_ALL;
our $GSEA_KEGG;
our $GSEA_LABELS;

    #Main variables
    our $IFS_HOME="/groups/bh6_gp/home";
    if($ENV{HFPD_IFS_HOME})
    {
        $IFS_HOME=$ENV{HFPD_IFS_HOME};
    }
    our $IFS_DATA="/groups/bh6_gp/data";
    if($ENV{HFPD_IFS_DATA})
    {
        $IFS_DATA=$ENV{HFPD_IFS_DATA};
    }
    our $IFS_SCRATCH="/groups/bh6_gp/scratch";
    if($ENV{HFPD_IFS_SCRATCH})
    {
        $IFS_SCRATCH=$ENV{HFPD_IFS_SCRATCH};
    }
    
    
    $MAIN_DIRECTORY="$IFS_HOME/shares/hfpd"; # A copy of CVS export.
    if($ENV{HFPD_DIR})
    {
        $MAIN_DIRECTORY=$ENV{HFPD_DIR};
    }
    -d $MAIN_DIRECTORY or die "Main HFPD directory does not exist (\$MAIN_DIRECTORY=$MAIN_DIRECTORY).\n";
    
    #Databases
    $DATABASE_DIR="$IFS_DATA/shares/databases";
     
    $GENOME_DIRECTORY="$DATABASE_DIR/hfpd/genomes"; 
    if($ENV{HFPD_DATA_DIR})
    {
        $GENOME_DIRECTORY=$ENV{HFPD_DATA_DIR};
    }
    -d $GENOME_DIRECTORY or die "Genome directory does not exist (\$GENOME_DIRECTORY=$GENOME_DIRECTORY).\n";

    $SCRATCH_DIRECTORY="$IFS_SCRATCH/shares/hfpd/PrePPI";
    if($ENV{HFPD_SCRATCH_DIR})
    {
        $SCRATCH_DIRECTORY=$ENV{HFPD_SCRATCH_DIR};
    }
    -d $SCRATCH_DIRECTORY or die "Scratch directory does not exist (\$SCRATCH_DIRECTORY=$SCRATCH_DIRECTORY).\n";

    $SCRATCH_SHARES="$IFS_SCRATCH/shares";
    $JACKAL_BIN="$IFS_HOME/shares/jackal/bin";
    $HFPD_BIN="$IFS_DATA/shares/bin";  # should this be moved to IFS_HOME?
    -d $HFPD_BIN or die "Binaries directory does not exist (\$HFPD_BIN=$HFPD_BIN).\n";
    
    $HFPD_SCR="$MAIN_DIRECTORY/SCR";
    -d $HFPD_SCR or die "Scripts directory does not exist (\$HFPD_SCR=$HFPD_SCR).\n";
    
    $PREPPI_SOURCES="$IFS_DATA/shares/hfpd/data";
 
    #Auxiliar programs
    $BLASTBIN = "$IFS_HOME/shares/rpsblast/ncbi-blast-2.10.1+/bin"; #Blast bin directory
    $BLASTCMD = "$IFS_HOME/shares/blast/current/x64-linux/bin"; #Blast bin directory
    $PUDGE="$IFS_DATA/shares/bin";
    $SUBMAT="$IFS_DATA/shares/hfpd/data/submat/blosum62";
    $TROLLTOP="$IFS_DATA/shares/hfpd/dat/allh.top";
    die "SUBMAT envionment variable not set." if not defined $ENV{SUBMAT};
    die "File not found: $ENV{SUBMAT} (\$ENV{SUBMAT}=\"$ENV{SUBMAT}\")" unless -e $ENV{SUBMAT};
    die "TROLLTOP envionment variable not set." if not defined $ENV{TROLLTOP};
    die "File not found: $ENV{TROLLTOP} (\$ENV{TROLLTOP}=\"$ENV{TROLLTOP}\")" unless -e $ENV{TROLLTOP};
    
    #CD_Search. Domains
    $EV_THRESHOLD=1.0e-20;
    
    #DOM database
    $PDBDOM_DIR="$DATABASE_DIR/scop/pdbstyle";
    $DOM_DIR="$DATABASE_DIR/ECOD";
    $DOM_SEQ="$DOM_DIR/domains.fa";
    $DOM_SEQ100="$DOM_DIR/domains_100.fa";
    
    #PDB_chain database
    $PDB_DIR="$DATABASE_DIR/pdb";
    $PDBCHAIN_DIR="$DATABASE_DIR/pdb_chain";
    $KNOWN_AA="$PDB_DIR/known_aa.txt"; 
    $PDBCHAINSEQ100="$PDB_DIR/pdb_chain_100.fa";
    $PDBCHAINSEQ="$SCRATCH_SHARES/databases/pdb/pdb_chain.fa";
    $PDBATOMSEQ="$SCRATCH_SHARES/databases/pdb/pdb_atom_seq.fa";
    $PDBSEQRES="$SCRATCH_SHARES/databases/pdb/pdb_seqres.fa";
    $PDBPROT60="$SCRATCH_SHARES/databases/pdb/pdb_prot60.fa";
    $PDBPROTEIN="$SCRATCH_SHARES/databases/pdb/pdb_protein.fa";
    $CD_HIT="$IFS_SCRATCH/shares/cdhit/cd-hit-v4.6.5-2016-0304/cd-hit";
    
    #PISA database
    $PISA_DIR="$DATABASE_DIR/PISA";
    $PISA_WEB="http://www.ebi.ac.uk/pdbe/pisa/cgi-bin/interfaces.pisa?";
    $PISA_WEB_ASSEMBLIES="http://www.ebi.ac.uk/pdbe/pisa/cgi-bin/multimers.pisa?";
    $PISA_WEB_ASSEMBLIES_PDB="http://www.ebi.ac.uk/pdbe/pisa/cgi-bin/multimer.pdb?";

    $UNIPROTDIR="$DATABASE_DIR/uniprot";
    -d $UNIPROTDIR or die "UniProt directory does not exist (\$UNIPROTDIR=$UNIPROTDIR).\n";
    $UNIPROT100="$UNIPROTDIR/uniref100";
    -e $UNIPROT100 or die "uniref100.fa does not exist (\$UNIPROT100=$UNIPROT100).\n";
    $UNIPROT100_TAB="$UNIPROTDIR/uniref100.tab";
    $UNIPROT90="$UNIPROTDIR/uniref90";
    -e $UNIPROT90 or die "uniref90.fa does not exist (\$UNIPROT90=$UNIPROT90).\n"; 
    $UNIPROT2GO="$IFS_DATA/shares/databases/goa/uniprot2go/201311/";
    -e $UNIPROT90 or die "Mapping of uniprot to GO directory does not exist (\$UNIPROT2GO=$UNIPROT2GO).\n"; 
    
    #Modbase
    $MODBASE_ALIGN=0.8;   #proportion of aligment neccesary 
    $MODBASE_EV_HIGH=1e-6;    #High model evuation limit 
    $MODBASE_EV_LOW=1;        #Low model evuation limit 
    $MODBASE_MPQS_HIGH=1;     #High model MPQS limit 
    $MODBASE_MPQS_LOW=0.5;    #Low model MPQS limit
    $MODBASE_FILE="$IFS_DATA/shares/hfpd/data/modbase/models.txt";    #List of modbase models
    $MODBASE_DIR="$IFS_DATA/shares/hfpd/data/modbase/models";    #Directory with models
    
    #SKYBASE
    $UNIPROTMAPPING="$IFS_DATA/shares/hfpd/data/skybase/uniprot.orgn.map";
    $SKYBASEDB="$IFS_HOME/qz2126/data/databases/skybase/data/";
    $SKYMODELINFO="$IFS_DATA/shares/hfpd/data/skybase/yeast.tab";
    
    #Skan
    $PDB_SKAN="$DATABASE_DIR/pdb_skads";
    $PDB_SKAN60="$DATABASE_DIR/pdb_skads60";
    $SKADS=$PDB_SKAN.'/skads/all_templates.skads';
    $SKADS_DIR="$IFS_SCRATCH/shares/databases/skads";
    $SKADS60="$SKADS_DIR/pdb60.skads";
    $MEM_SKAN='10G';
    $TIME_SKAN='48::';
    $SKAN_CUTOFF=0.60;
    $SKAN_SSESIM=0.6;
    $SKAN_MINLENGTH=3;
    
    
    #interface prediction
    $MEM_INTERFACE="20G"; #Memory necessary for interface prediction jobs
    $TIME_INTERFACE="48:00:00"; #Time necessary for interface prediction jobs
    $INTERFACE_BIN="$IFS_DATA/shares/interface_prediction";
    $PINUPBIN=$INTERFACE_BIN."/PINUP/pinup";     #Binary executable for PINUP
    $PREDROTPRO="$HFPD_SCR/predrotpro_web.pl";  #Auxilar executable for PredUs  
    $PREDUSINTF=$INTERFACE_BIN."/PREDUS/interface.pl"; #Binary executable for PredUs
    $PREDUS_V2=$INTERFACE_BIN."/PREDUS/run_predus.pl"; #Binary executable for PredUS V2
    $CONSPPISPBIN=$INTERFACE_BIN."/CONS_PPISP/cons-PPISP";    #Binary executable for cons-PPISP
    $CONSPPISPWGTL=$INTERFACE_BIN."/CONS_PPISP/wghtlst.all"; #Auxiliar file for cons-PPISP
    $CONSPPISPWGT=$INTERFACE_BIN."/CONS_PPISP/WGT/";  #Auxiliar file for cons-PPISP
    $CONSPPISPMSG=$INTERFACE_BIN."/CONS_PPISP/message.txt";   #Auxiliar file for cons-PPISP

    #Score
    $MEM_LINK="3G"; 
    $TIME_LINK="5:00:00"; 
    $MEM_RESCORR="3G"; 
    $TIME_RESCORR="24:00:00";
    $MEM_SCORE="6G"; #Memory neccessary for score jobs
    #$TIME_SCORE="240:00:00"; #Time neccessary for score jobs
	$TIME_SCORE="24:00:00"; #Time neccessary for score jobs
    $MAX_ARRAY_VAL=1000; # Maximum permissible array value on HPC

    
    #PrePPI General data
    $HUMAN_ALL_POSIT_INT="$IFS_DATA/shares/hfpd/data/datasets/human.all.201311";
    $HUMAN_HC_POSIT_INT="$IFS_DATA/shares/hfpd/data/datasets/human.hc.201311";
    $YEAST_ALL_POSIT_INT="$IFS_DATA/shares/hfpd/data/datasets/yeast.all.201311";
    $YEAST_HC_POSIT_INT="$IFS_DATA/shares/hfpd/data/datasets/yeast.hc.201311";
    
    #PDB-PQS Interface
    $PDB2PQS=$PREPPI_SOURCES."/pqs/pdb2pqs.lst";
    $PQSINTERFACE="$DATABASE_DIR/interface/near/interface.noligand.pqs";
    $PDBINTERFACE="$DATABASE_DIR/interface/near/interface.noligand.pdb";
    $BIOUNITINTERFACE="$DATABASE_DIR/interface/near/interface.noligand.biounit";
    $PISAINTERFACE="$DATABASE_DIR/interface/near/interface.noligand.pisa";
    
    $HMAPDIR="$IFS_DATA/petrey/hmap";
    -d $HMAPDIR or die "HMAP directory does not exist (\$HMAPDIR=$HMAPDIR).\n";
    $HMAPCHAIN_DIR="$IFS_DATA/shares/databases/1dhmap/chains/new"; # AS: Not copied. Consult if needed.
    -d $HMAPCHAIN_DIR or die "HMAPCHAIN_DIR directory does not exist (\$HMAPCHAIN_DIR=$HMAPCHAIN_DIR).\n";
    $HMAPDOM_DIR="$IFS_DATA/shares/databases/1dhmap/domains/new"; # AS: Not copied. Consult if needed.
    -d $HMAPDOM_DIR or die "HMAPDOM_DIR directory does not exist (\$HMAPDOM_DIR=$HMAPDOM_DIR).\n";
    $HMAPALL_DIR="$IFS_DATA/shares/databases/1dhmap/all/new"; # AS: Not copied. Consult if needed.
    -d $HMAPALL_DIR or die "HMAPALL_DIR directory does not exist (\$HMAPALL_DIR=$HMAPALL_DIR).\n";

    #Bayessian Network
    $PSDNET=$PREPPI_SOURCES."/bayessian/psd.highQ.lr";
    #$BN72NET=$PREPPI_SOURCES."/bayessian/bn72.highQ.lr";
    $BN72NET=$PREPPI_SOURCES."/bayessian/bn72.highQ.lr.newYeast";
    $BN24NET=$PREPPI_SOURCES."/bayessian/bn24.highQ.lr.newYeast";
    $BN56NET=$PREPPI_SOURCES."/bayessian/bn56.highQ.lr.newYeast";
    $BN120NET=$PREPPI_SOURCES."/bayessian/bn120.highQ.lr.newYeast";
    $BN120NET=$PREPPI_SOURCES."/bayessian/bn120.highQ.lr.newYeast";
    $BN36NET=$PREPPI_SOURCES."/bayessian/bn36.highQ.lr.newYeast";
    
    $BABEL_DATADIR="$IFS_HOME/shares/lbias/source/babel_data"; # AS: Not copied. Consult if needed.
    -d $BABEL_DATADIR or die "Babel data directory not found (\$BABEL_DATADIR=$BABEL_DATADIR)";
    
    #Phylogenetics Profile
    $MEM_PHYLOGENETIC="7G";
    $ORGAUNIPROT="$PREPPI_SOURCES/phylogenetics/orga.uniprot";
    $NOGCLUSTER="$IFS_DATA/shares/hfpd/data/eggNOG/NOG_cluster.txt";
    $NOGPROFILES="$IFS_DATA/shares/hfpd/data/eggNOG/cog_profiles_all_allprot.txt";
    $BNPHYLO=$PREPPI_SOURCES."/bayessian/phylogenetic.lr";
	
    #Database Coexpression
    $DBTYPE = "mysql";
    $DBNAME = "Coexpression";
    $DBHOST = "156.145.28.137";
    $DBUSER = "root";
    $DBPWD = "Abc#123";
    $BNCOEXP=$PREPPI_SOURCES."/bayessian/coexpression.lr";
        
    #Gopher
    $GOPHER_BIN="$IFS_HOME/shares/slimsuite_2024/legacy/gopher_V2.py";
    $GOPHER_MEM="20G";
    $GOPHER_DB="$IFS_DATA/shares/databases/uniprot/uniref100";

    $CDDDIR="/groups/bh6_gp/scratch/shares/databases/cddle";

    #Orthology
    $INTERACTIONS="$IFS_DATA/shares/hfpd/data/datasets/db.all.201311";
    $INTERACTIONS_HC="$IFS_DATA/shares/hfpd/data/datasets/db.hc.201311";
    $ORTHOLOGY_DATABASES="eggnog,genetree,hogenom,hovergen,ko,oma,orthodb,protclustdb,treefam";
    $ORTHOLOGY_DIRECTORY="$IFS_DATA/shares/hfpd/data/Orthology_groups";
    $BNORTHO=$PREPPI_SOURCES."/bayessian/Ortho.lr";
    
    #GO Terms
    $GO_ANCESTORS="$IFS_DATA/shares/hfpd/data/GO/go_ancestors.txt";
    $GO_DEEP="$IFS_DATA/shares/hfpd/data/GO/go_deep.txt";
    $GO_INFO="$IFS_DATA/shares/hfpd/data/GO/go_info.txt";
    $BNPREDGO_MIN=$PREPPI_SOURCES."/bayessian/PredGO.min.lr";
    $BNPREDGO_AVG=$PREPPI_SOURCES."/bayessian/PredGO.avg.lr";
    
    $GODIR3_HUMAN="$IFS_DATA/shares/hfpd/data/GO/GO_human_Level3";
    $GODIR4_HUMAN="$IFS_DATA/shares/hfpd/data/GO/GO_human_Level4";
    $GODIR5_HUMAN="$IFS_DATA/shares/hfpd/data/GO/GO_human_Level5";
    
    #Protein-Peptides
    $CLUSTER_FILE_PEP="$IFS_DATA/shares/hfpd/data/Peptides/ialign_750_noclusters.txt";
    $IDENTICAL_FILE_PEP="$IFS_DATA/shares/hfpd/data/Peptides/ialign_750_identicals.txt";
    $CUTS_FILE_PEP="$IFS_DATA/shares/hfpd/data/Peptides/cuts_total.txt";
    $IUPRED_PATH="$IFS_HOME/shares/iupred";
    $INTERFACE_CONTACTS_D="$IFS_DATA/shares/hfpd/data/Peptides/interface_contacts/";
    $PRD_CUTOFF=0.75;
    $BNMOTIF=$PREPPI_SOURCES."/bayessian/Motif.lr";
    $BNMOTIF_ELM=$PREPPI_SOURCES."/bayessian/Motif_ELM.lr";
    # ELM & HMMer 2025
    $ELM_CLASSES="$IFS_DATA/shares/hfpd/data/Peptides/elm_2025/elm_classes_2025.tsv";
    $HMMS="$IFS_DATA/shares/hfpd/data/Peptides/hmms_2025";
    
    #FIBE
    $FIBE_DIR="$MAIN_DIRECTORY/bin/FIBE/"; #ALERT: Last slash needed
    $FIBE_MEM="4G";
    $FIBE_TIME="2:00:00";
    
    #DNAnalysis
    $DNA_ANALYSIS="$IFS_HOME/shares/x3dna/runDNA_analysis.pl"; # AS: Not copied. Consult if needed.
    
    #Surface
    $SURF_BIN="$IFS_HOME/shares/SURFace/surfv";
    $ATOM_SIZE="$IFS_DATA/shares/hfpd/data/Surfv/parse_mod.siz";
    
    #redundancy
    $BNRED=$PREPPI_SOURCES."/bayessian/Redundancy.lr";
    $BNREDP=$PREPPI_SOURCES."/bayessian/Redundancy_pairs.lr";
    
    #Combination of analysis
    $BNCOMBINED=$PREPPI_SOURCES."/bayessian/Combined.lr";
    $BNCOMBINED2=$PREPPI_SOURCES."/bayessian/Combined2.lr";
    $BNCOMBINED_ST_RED=$PREPPI_SOURCES."/bayessian/CombinedStRed.lr";
  
    #MultiAlign
    $CLUSTALW="$IFS_HOME/shares/clustalw/clustalw";
    $JACKHAMMER="$IFS_HOME/shares/hmmer-3.1b2-linux-intel-x86_64/binaries/jackhmmer";
    $JACKHAMMER_DIR="$IFS_HOME/shares/hmmer-3.1b2-linux-intel-x86_64/binaries/";
    $MUSCLE="$IFS_HOME/shares/muscle/muscle";
    $UNI_SPROT="$IFS_DATA/shares/hfpd/data/Uniprot/uniprot_sprot.fasta";
    
    $JOBS_DIR="$IFS_SCRATCH/shares/hfpd/Jobs";
    
    #Database
    #$DB_HOST = "156.145.30.114";
    $DB_HOST = "mysql1.c2b2.columbia.edu";
    $DB_USER = "nacho";
    $DB_PASS = "Struct\$4u";
    #$DB_NAME = "preppi";
    $DB_NAME = "predusdb";
    $DB_NAME_SQLITE = "$IFS_HOME/shares/hfpd_database/preppi-fast.sqlite";
 
    #Scores for prot-prot databases
    #$DB_BGSC=122.509;
    #$DB_IASC=70.9;
    #$DB_DPSC=5.534;
    #$DB_MPSC=171.551;
    #$DB_MNSC=5.656;
    #$DB_MANY=1099.46;
    #
    $DB_BGSC=957.82;
    $DB_IASC=102.536;
    $DB_DPSC=396.329;
    $DB_MPSC=171.551;
    $DB_MNSC=130.646;
    $DB_HPSC=1802.05;
    $DB_MANY=4625.64;
    
    #R Program for mutual information
    $Rscript="/nfs/apps/R/3.1.2/bin/Rscript";
    
    #Compilation of interactions
    $PREPPI_INTERACTIONS="$IFS_DATA/shares/hfpd/data/Predictions/human_v2/final_v11.txt";
    $PREPPI_INTERACTIONS_NO_GO="$IFS_DATA/shares/hfpd/data/Predictions/human_v2/final_v11_withoutGO.txt";
    
    #GSEA
    $GSEA_C5_ALL="$IFS_DATA/shares/hfpd/data/GSEA/c5.all.v5.0.symbols.gmt";
    $GSEA_KEGG="$IFS_DATA/shares/hfpd/data/GSEA/c2.cp.kegg.v5.1.symbols.gmt";
    $GSEA_LABELS="$IFS_DATA/shares/hfpd/data/GSEA/labels.cls";

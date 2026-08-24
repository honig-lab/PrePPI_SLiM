package MODS::Globals;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
    $IFS_HOME
    $MAIN_DIRECTORY
    $GENOME_DIRECTORY
    $HFPD_SCR
    $BLASTCMD
    $GOPHER_BIN
    $GOPHER_DB
    $ELM_CLASSES
    $HMMS
    $JACKHAMMER_DIR
    $MUSCLE
    $EMAIL_DIR
    $MAX_ARRAY_VAL
);

our $IFS_HOME = $ENV{HFPD_IFS_HOME} // "/groups/bh6_gp/home";
our $IFS_DATA = $ENV{HFPD_IFS_DATA} // "/groups/bh6_gp/data";

our $MAIN_DIRECTORY = $ENV{HFPD_DIR} // "$IFS_HOME/shares/hfpd";
our $DATABASE_DIR = "$IFS_DATA/shares/databases";
our $GENOME_DIRECTORY = $ENV{HFPD_DATA_DIR} // "$DATABASE_DIR/hfpd/genomes";
our $HFPD_BIN = "$IFS_DATA/shares/bin";
our $HFPD_SCR = "$MAIN_DIRECTORY/SCR";

-d $MAIN_DIRECTORY
    or die "PrePPI-SLiM directory does not exist (HFPD_DIR=$MAIN_DIRECTORY).\n";
-d $GENOME_DIRECTORY
    or die "Genome directory does not exist (HFPD_DATA_DIR=$GENOME_DIRECTORY).\n";
-d $HFPD_BIN
    or die "Shared binary directory does not exist (HFPD_BIN=$HFPD_BIN).\n";
-d $HFPD_SCR
    or die "PrePPI-SLiM SCR directory does not exist (HFPD_SCR=$HFPD_SCR).\n";

# Sequence and orthology resources used by the SLiM pipeline.
our $BLASTCMD = "$IFS_HOME/shares/blast/current/x64-linux/bin";
our $GOPHER_BIN = "$IFS_HOME/shares/slimsuite_2024/legacy/gopher_V2.py";
our $GOPHER_DB = "$DATABASE_DIR/uniprot/uniref100";
our $MUSCLE = "$IFS_HOME/shares/muscle/muscle";
our $JACKHAMMER_DIR = "$IFS_HOME/shares/hmmer-3.1b2-linux-intel-x86_64/binaries/";

# ELM/Pfam resources used by motif and PRD detection.
our $ELM_CLASSES = "$IFS_DATA/shares/hfpd/data/Peptides/elm_2025/elm_classes_2025.tsv";
our $HMMS = "$IFS_DATA/shares/hfpd/data/Peptides/hmms_2025";

our $EMAIL_DIR = "$IFS_HOME/shares/hfpd/Email";
our $MAX_ARRAY_VAL = $ENV{HFPD_MAX_ARRAY_VAL} // 1000;

1;

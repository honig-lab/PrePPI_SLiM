package MODS::Methods;

use strict;
use warnings;

# All perl modules for PrePPI pipeline steps that we have not begun the
# migration process to hpc.c2b2.columbia.edu are commented out. As we
# migrate and test additional modules, they will be uncommented below.

use MODS::Globals;
use MODS::Genome;
use MODS::Pipeline;
use MODS::Method;
use MODS::NEST;
use MODS::BLAST;
use MODS::IUPRED;
# use MODS::HMAP;
use MODS::HH;
# use MODS::Modbase;
use MODS::PredInterface;
use MODS::Skan;
# use MODS::Skads;
# use MODS::Ska;
# use MODS::ResCorr;
# use MODS::Interaction;
# use MODS::InteractionModel;
use MODS::Interaction_LR;
# use MODS::LR;
# use MODS::PhyloProfile;
# use MODS::PhyloCorr;
# use MODS::Coexpression;
# use MODS::PredGO;
# use MODS::PredGO_Corr;
use MODS::MODELLER; # NEST falls back to Modeller when it fails
# use MODS::S4;
# use MODS::PSIPRED;
# use MODS::DFIRE;
# use MODS::PG;
# use MODS::TM;
# use MODS::ModLR;
# use MODS::XPLOR;
# use MODS::SCWRL;
# use MODS::SCAP;
# use MODS::PLOP;
use MODS::Orthologs;
# use MODS::OrthoPairs;
# use MODS::OrthoSeq;
# use MODS::OrthoTaxonomies;
use MODS::FindMotifs;
use MODS::FindPRDs;
# use MODS::FIBE;
# use MODS::DNAnalysis;
# use MODS::Surface;
use MODS::MultiAlign;
# use MODS::ProtPeptide;
use MODS::ProtPeptide_ELM;
# use MODS::Redundancy;
# use MODS::End_mark;
# use MODS::Compress;
# use MODS::MutualInfo;
use MODS::MotifConsv;
# use MODS::InterfaceRes;
# use MODS::GSEA;
# use MODS::GO_Enrichment;
# use MODS::GO_Enrichment_wA;
# use MODS::Count_models;
# use MODS::Evaluate_GSEA;
# use MODS::FindDisruptions;
# use MODS::FunctionalPartners;
# use MODS::MapRes;
# use MODS::LBias;
# use MODS::Custom;
# use MODS::Partners;
# use MODS::PredUs2;
# use MODS::Setup;
return 1;

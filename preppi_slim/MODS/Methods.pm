package MODS::Methods;

use strict;
use warnings;

# Pipeline infrastructure.
use MODS::Globals;
use MODS::Genome;
use MODS::Pipeline;
use MODS::Method;

# PrePPI-SLiM stages registered dynamically by MODS::Pipeline.
use MODS::IUPRED;
use MODS::Orthologs;
use MODS::FindMotifs;
use MODS::FindPRDs;
use MODS::MultiAlign;
use MODS::ProtPeptide_ELM;
use MODS::MotifConsv;

return 1;

# Building Perl 5.40.0 used with PfamScan

## Summary

[PfamScan](https://github.com/SMRUCC/GCModeller/blob/master/src/interops/scripts/PfamScan/PfamScan/pfam_scan.pl) 
is required for identifying peptide recognition domains (PRD) and is
required by PrePPI's ELM-based protein-peptide interaction pipeline (e.g.
run_elm.py). The Python pipeline calls the third-party PfamScan program, which
has two required dependencies in the form of
Perl modules (Moose, BioPerl) that must be installed by CPAN.

However, the versions of CPAN (/usr/bin/cpan) that are installed on the test
cluster (login6.c2b2.columbia.edu) and hpc cluster (hpc.c2b2.columbia.edu)
produce the error shown below when attempting to install Moose:

```
cc1: fatal error: inaccessible plugin file /apps/ohpc/pub/compiler/gcc/13.2.0/bin/../lib/gcc/x86_64-pc-linux-gnu/13.2.0/plugin/annobin.so expanded from short plugin name annobin: No such file or directory
compilation terminated.
```

This documentation describes a work-around to this problem by installing
[Perl 5.40.0](https://www.cpan.org/src/README.html) directly from source code,
and configuring CPAN to install modules to a directory that is
write-accessible by members of the Honig lab.

## Installation

The instructions for installing Perl 5.40.0 follow from the README file
published with the official distribution.

1. Create directories for Perl 5.40.0

```
# These directories are on hpc.c2b2.columbia.edu

mkdir -p /groups/bh6_gp/home/shares/perl-5.40.0/download
mkdir -p /groups/bh6_gp/home/shares/perl-5.40.0/install
mkdir -p /groups/bh6_gp/home/shares/perl-5.40.0/modules
cd /groups/bh6_gp/home/shares/perl-5.40.0/download
```

2. Install Perl 5.40.0

```
# See also https://www.cpan.org/src/README.html

wget https://www.cpan.org/src/5.0/perl-5.40.0.tar.gz
tar -xvzf perl-5.40.0.tar.gz
cd perl-5.40.0
./Configure -des -Dprefix=/groups/bh6_gp/home/shares/perl-5.40.0/install
make
make test  # this will take some time and is skippable
make install
```

3. Configure CPAN where to install Perl modules.

```
export PATH=/groups/bh6_gp/home/shares/perl-5.40.0/install/bin:$PATH
export PERL5lib=/groups/bh6_gp/home/shares/perl-5.40.0/modules/lib/perl5:$PERL5LIB

# Ensure the correct version of cpan is executed:
# /groups/bh6_gp/home/shares/perl-5.40.0/install/bin/cpan

which cpan
cpan

# Type the following:
o conf makepl_arg INSTALL_BASE=/groups/bh6_gp/home/shares/perl-5.40.0/modules
o conf mbuildpl_arg '--install_base /groups/bh6_gp/home/home/shares/perl-5.40.0/modules'
o conf commit

quit
```

4. Install preliminary modules:
```
cpan
install Term::ReadLine::Perl
install Term::ReadKey
quit  # quit to ensure newly installed modules are loaded
```

5. Update CPAN:
```
cpan
install CPAN
install CPAN::DistnameInfo
quit  # quit to ensure newly installed modules are loaded
```

6. Install Module/Runtime.pm (required by Moose.pm):
```
# Important: the installation script for Module/Runtime.pm does not respect
# the `makepl_arg` or `mbuildpl_arg` in CPAN so the following are needed

export PERL_LOCAL_LIB_ROOT=/groups/bh6_gp/home/shares/perl-5.40.0/modules
export PERL_MB_OPT='--install_base /groups/bh6_gp/home/shares/perl-5.40.0/modules'
export PERL_MM_OPT='INSTALL_BASE=/groups/bh6_gp/home/shares/perl-5.40.0/modules'

cpan
install YAML
quit  # quit to ensure newly installed modules are loaded
perl -MYAML -e 1  # check YAML was indeed installed

cpan
install inc::latest
quit  # quit to ensure newly installed modules are loaded
perl -Minc::latest -e 1  # check inc/latest was indeed installed

cpan
install Software::License
quit  # quit to ensure newly installed modules are loaded
perl -MSoftware::License -e 1  # check Software/License was indeed installed

cpan
install Module::Build
quit  # quit to ensure newly installed modules are loaded
perl -MModule::Build -e 1  # check Module/Build was indeed installed

cpan
install Module::Runtime
quit  # quit to ensure newly installed modules are loaded
perl -MModule::Runtime -e 1  # check Module/Runtime was indeed installed
```

Important note: there should *not* be `~/perl5` in your *home* directory. All
modules should be installed into `/groups/bh6_gp/home/home/shares/perl-5.40.0/modules`.
If `~/perl5` has been created, you may need to delete this directory, double
check `PERL_LOCAL_LIB_ROOT`, `PERL_MB_OPT` and `PERL_MM_OPT` and redo Step 6.

7. Install Moose:
```
cpan
install Moose  # this will take some time
quit

perl -MMoose -e 1  # check that Moose was indeed installed
```

8. Install BioPerl:
```
# Don't install BioPerl using CPAN. Instead copy the module files from git source.

mkdir -p /groups/bh6_gp/home/shares/BioPerl
cd /groups/bh6_gp/home/shares/BioPerl
git clone git@github.com:bioperl/bioperl-live.git
cp bioperl-live/lib/BioPerl.pm /groups/bh6_gp/home/shares/perl-5.40.0/modules/lib/perl5/
cp -r bioperl-live/lib/Bio /groups/bh6_gp/home/shares/perl-5.40.0/modules/lib/perl5/

perl -MBio::Seq -e 1  # check that BioPerl was indeed installed
```


| | |
|-|-|
| Author | Chris Tang |
| Created | Dec 9, 2024 |

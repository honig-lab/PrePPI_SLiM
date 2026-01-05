# Building Perl dependencies for Pfam (PfamScan)

## Summary

On the Isilon file system `/ifs/data/c2b2/bh_lab/shares/hfpd/perl5/lib/perl5/`
contains the non-standard Perl dependencies required by PfamScan (see
`hfpd/SCR/PfamScan/README`). It contains the Moose framework and BioPerl
installation, both built using CPAN.

These notes were created for the old cluster `login.c2b2.columbia.edu`. See
Addendum for relevant differences for building on the test cluster
`login6.c2b2.columbia.edu`.

## Installation Notes

Installation was performed under the following conditions:

* `cpan` is installed on the compute nodes of the cluster, not as part of the
  login environment.

* Installation was performed into a `local::lib` to avoid using `sudo`
  privileges

## Installation

1. Execute `qrsh` to log onto a compute node and access `cpan`.

   a. As mentioned `cpan` will not be found on the login node.

2. Execute `cpan`.

   a. If this is the first time using `cpan`, you will automatically drop into
      `cpan`'s configuration mode.

   b. If this is not the first time using `cpan`, you should enter
      configuration mode using the command `o conf init`.

3. Select the following configuration options. Note they will all be the
   default options:

```
Would you like to configure as much as possible automatically? [yes]
```

```
What approach do you want?  (Choose 'local::lib', 'sudo' or 'manual') [local::lib]
```

4. Wait for `cpan` to self-configure.
   
   a. Important note: there is a time-skew between the server and the
      filesystem, and it is possible for the build process to fail. In the case
      of failure, return to step 1 and repeat the steps. A failure will
      generate output that looks like the following, and drop you out of the
      `qrsh` session.
   
   b. Success will produce a message like the following.

*Failure*
```
make: *** wait: No child processes.  Stop.
make: *** Waiting for unfinished jobs....
make: *** wait: No child processes.  Stop.
```

*Success*
```
local::lib is installed. You must now add the following environment variables
to your shell configuration files (or registry, if you are on Windows) and
then restart your command line shell and CPAN before installing modules:
```

5. Answer "yes" to the prompt to add environment variables to your `.bashrc` file:

```
Would you like me to append that to /ifs/home/c2b2/bh_lab/dm527/.bashrc now? [yes]
```

6. Restart your `qrsh` session.

7. Restart `cpan` and install PfamScan's dependencies.

   a. Execute `install Moose`. If this succeeds, you will see many lines
      reporting `Installing ...` and a summary line: `/bin/make install -- OK`

   b. Execute `install BioPerl`. Likewise, make sure this succeeds by checking
      as above.

8. Success! Locate the libraries you have built in your home directory under
   `~/perl5`.



| | |
|-|-|
| Author | Chris Tang |
| Created | Aug 16, 2024 |
| Consulted | Diana Murray, Donald Petrey |

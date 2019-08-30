#!/usr/bin/perl

use strict;
use warnings;

use Path::Tiny;

use constant EMPTY => q{};

my $testpath = $ARGV[0];

print "Reading from $testpath/desc\n";
my $desc = path("$testpath/desc")->slurp;

my @testfields = qw/Check Default-Lintian-Options Lintian-Command-Line Match-Strategy Options Output-Format Profile References Test-Against Test-Architectures Test-Conflicts Test-Depends Todo/;


my @lines = split(/\n/, $desc);

my $builddesc;
my $testdesc;
my $buildfield;

for my $line (@lines) {
  if ($line =~ qr/^ /) {
    die unless defined $buildfield;
    if ($buildfield) {
      $builddesc .= "$line\n";
    } else {
      $testdesc .= "$line\n";
    }
  } elsif ($line =~ qr/^([^:]+):/) {
    if (grep {/$1/ } @testfields) {
      $testdesc .= "$line\n";
      $buildfield = 0;
    } else {
      $builddesc .= "$line\n";
      $buildfield = 1;
    }
  } else {
    $testdesc .= "$line\n";
    $builddesc .= "$line\n";
  }
}

path("$testpath/test-spec")->spew($testdesc // EMPTY);

my $buildspecpath = "$testpath/build-spec";
path($buildspecpath)->mkpath
  unless -e $buildspecpath;
path("$buildspecpath/fill-values")->spew($builddesc // EMPTY);

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

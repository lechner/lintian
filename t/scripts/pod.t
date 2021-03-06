#!/usr/bin/perl
#
# Test POD formatting.  Taken essentially verbatim from the examples in the
# Test::Pod documentation.

use strict;
use warnings;
use Test::More;
plan skip_all => 'Not needed for coverage of Lintian'
  if $ENV{'LINTIAN_COVERAGE'};
eval 'use Test::Pod 1.00';
plan skip_all => 'Test::Pod 1.00 required for testing POD' if $@;

my $dir = $ENV{'LINTIAN_TEST_ROOT'} // '.';

my @POD_FILES = all_pod_files("$dir/lib", "$dir/doc/tutorial");
push(@POD_FILES, map { "$dir/man/$_" } 'lintian-info.pod', 'lintian.pod.in');

all_pod_files_ok(@POD_FILES);

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

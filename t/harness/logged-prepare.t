#!/usr/bin/perl

# Copyright © 2018 Felix Lechner
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA

use strict;
use warnings;
use autodie;

BEGIN {
  die('Cannot find LINTIAN_TEST_ROOT') unless length $ENV{'LINTIAN_TEST_ROOT'};
}

use File::Basename qw(basename);
use File::Temp;
use File::stat;
use List::Util qw(max);
use Test::More;

use lib "$ENV{'LINTIAN_TEST_ROOT'}/lib";
use Test::Lintian::Prepare qw(logged_prepare);
use Test::Lintian::ConfigFile qw(read_config);
use Test::Lintian::Helper qw(rfc822date);

# dummy test name; used in desc and directory name
my $TESTNAME = 'shared-libs-non-pic-i386';

# temporary work directory
my $tempdir = Path::Tiny->tempdir();

# specification path
my $specpath = $tempdir->child('spec')->child($TESTNAME);
$specpath->mkpath;

# test description
my $desctext =<<EOSTR;
Testname: $TESTNAME
Version: 1.0-2
Test-Architectures: any-amd64 any-i386
Package-Architecture: any
Test-Depends: debhelper (>= 9.20151004~)
Description: Test checks related to non-pic code
Test-For: shlib-with-non-pic-code
EOSTR
my $descpath = $specpath->child('desc');
$descpath->spew($desctext);

my $runpath = $tempdir->child('run')->child($TESTNAME);
$runpath->mkpath;

logged_prepare($specpath->stringify, $runpath->stringify, 'tests', 't');

# read resulting test description
my $constraints = read_config($runpath->child('constraints')->stringify);
my $options = read_config($runpath->child('test-options')->stringify);
my $fill = read_config($runpath->child('template-fill')->stringify);

my @testarches = split(/\s+/, $constraints->{'test_architectures'});

# test plan
plan tests => 26 + scalar @testarches;

is($fill->{testname}, $TESTNAME, 'Correct name');

is($fill->{version}, '1.0-2', 'Correct version');
is($fill->{'upstream_version'}, '1.0', 'Correct upstream version');

is($constraints->{'test_architectures'}, 'any-amd64 any-i386', 'Correct test architectures');
isnt($constraints->{'test_architectures'}, 'any', 'Correct test architectures');
foreach my $testarch (@testarches) {
  my @known = qx{dpkg-architecture --list-known --match-wildcard $testarch};
  cmp_ok(scalar @known, '>', 1, "Known test architecture $testarch");
}

is($fill->{host_architecture}, $ENV{'DEB_HOST_ARCH'}, 'Correct host architecture');
isnt($fill->{host_architecture}, $constraints->{'test-architectures'}, 'Test and host architectures are different');

is($fill->{package_architecture}, 'any', 'Changed package architecture');
isnt($fill->{package_architecture}, 'all', 'Not the default package architecture');

is($options->{skeleton}, 'default', 'Default skeleton');
isnt($options->{skeleton}, 'pedantic', 'Not the pedantic skeleton');

is($fill->{'test_depends'}, 'debhelper (>= 9.20151004~)', 'Correct test dependencies');

is($options->{'test_for'}, 'shlib-with-non-pic-code', 'Correct Test-For');
is($options->{'test_against'}, '', 'Correct Test-Against');

is($fill->{'standards_version'}, $ENV{'POLICY_VERSION'}, 'Correct policy version');

is($fill->{date}, rfc822date(max(stat($descpath)->mtime, $ENV{'POLICY_EPOCH'})), 'Correct policy date');

is($options->{sort}, 'yes', 'Sort boolean was not converted from string');

is($options->{todo}, 'no', 'Todo disabled');

is($fill->{type}, 'native', 'Test is native');
isnt($fill->{type}, 'yes', 'Native type not yes.');

is($options->{'output_format'}, 'EWI', 'Output format is EWI');

is($options->{options}, '-I -E', 'Correct lintian options');

is($fill->{'dh_compat_level'}, $ENV{'DEFAULT_DEBHELPER_COMPAT'}, 'Default debhelper compat level');

is($fill->{description}, 'Test checks related to non-pic code', 'Correct description');
isnt($fill->{description}, 'No Description Available', 'Not default description');

is($fill->{author}, 'Debian Lintian Maintainers <lintian-maint@debian.org>', 'Default author');

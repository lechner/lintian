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
    die('Cannot find LINTIAN_TEST_ROOT')
      unless length $ENV{'LINTIAN_TEST_ROOT'};
}

use Cwd qw(realpath);
use File::Basename qw(dirname);
use List::Util qw(max);

use lib "$ENV{'LINTIAN_TEST_ROOT'}/lib";

use Test::Lintian::Run qw(logged_runner);
use Test::ScriptAge qw(our_modification_epoch perl_modification_epoch);

$ENV{'RUNNER_EPOCH'}= max(our_modification_epoch, perl_modification_epoch);

my $runpath = realpath(dirname($0));

logged_runner($runpath);

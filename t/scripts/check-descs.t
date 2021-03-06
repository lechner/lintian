#!/usr/bin/perl

# Copyright (C) 2012 Niels Thykier
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
# MA 02110-1301, USA.

use strict;
use warnings;

use Test::More import => ['done_testing'];

use Test::Lintian;

$ENV{'LINTIAN_TEST_ROOT'} //= '.';

load_profile_for_test('debian/main', $ENV{'LINTIAN_TEST_ROOT'});

my $opts = {'coll-dir' => "$ENV{'LINTIAN_TEST_ROOT'}/collection",};

test_check_desc($opts, "$ENV{'LINTIAN_TEST_ROOT'}/checks");
test_check_desc($opts, "$ENV{'LINTIAN_TEST_ROOT'}/doc/examples/checks");

done_testing;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

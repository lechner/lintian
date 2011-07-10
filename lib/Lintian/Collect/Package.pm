# -*- perl -*-
# Lintian::Collect::Package -- interface to data collection for packages

# Copyright (C) 2011 Niels Thykier
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.

# This handles common things for things available in source and binary packages
package Lintian::Collect::Package;

use strict;
use warnings;
use base 'Lintian::Collect';

use Carp qw(croak);

# Returns the path to the dir where the package is unpacked
#  or a file therein (see pod below)
# May croak if the package has not been unpacked.
# sub unpacked Needs-Info unpacked
sub unpacked {
    my ($self, $file) = @_;
    my $unpacked = $self->{unpacked};
    if ( not defined $unpacked ) {
	my $base_dir = $self->base_dir;
	$unpacked = "$base_dir/unpacked";
	croak "Unpacked not available" unless defined $unpacked && -d "$unpacked/";
	$self->{unpacked} = $unpacked;
    }
    if ($file) {
	# strip leading ./ - if that leaves something, return the path there
	$file =~ s,^\.?/*+,,go;
	return "$unpacked/$file" if $file;
    }
    return $unpacked;
}


1;

=head1 NAME

Lintian::Collect::Package - Lintian base interface to binary and source package data collection

=head1 SYNOPSIS

    my ($name, $type) = ('foobar', 'source');
    my $collect = Lintian::Collect->new($name, $type);
    my $file;
    eval { $file = $collect->unpacked('/bin/ls'); };
    if ( $file && -e $file ) {
        # work with $file
        ;
    } elsif ($file) {
        print "/bin/ls is not available in the Package\n";
    } else {
        print "Package has not been unpacked\n";
    }

=head1 DESCRIPTION

Lintian::Collect::Package provides part of an interface to package
data for source and binary packages.  It implements data collection
methods specific to all packages that can be unpacked (or can contain
files)

This module is in its infancy.  Most of Lintian still reads all data from
files in the laboratory whenever that data is needed and generates that
data via collect scripts.  The goal is to eventually access all data about
source packages via this module so that the module can cache data where
appropriate and possibly retire collect scripts in favor of caching that
data in memory.

=head1 INSTANCE METHODS

=over 4

=item unpacked([$name])

Returns the path to the directory in which the package has been
unpacked.  If C<$name> is given, it will return the path to that
specific file (or dir).  The method will strip any leading "./" and
"/" from C<$name>, but it will not check if C<$name> actually exists
nor will it check for path traversals.
  Caller is responsible for checking the sanity of the path passed to
unpacked and verifying that the returned path points to the expected
file.

The path returned is not guaranteed to be inside the Lintian Lab as
the package may have been unpacked outside the Lab (e.g. as
optimization).

The following code may be helpful in checking for path traversal:

 use Cwd qw(realpath);

 my $collect = ... ;
 my $file = '../../../etc/passwd';
 # Append slash to follow symlink if $collect->unpacked returns a symlink
 my $uroot = realpath($collect->unpacked() . '/');
 my $ufile = realpath($collect->unpacked($file));
 if ($ufile =~ m,^$uroot,) {
    # has not escaped $uroot
    do_stuff($ufile);
 } else {
    # escaped $uroot
    die "Possibly path traversal ($file)";
 }

Alternatively one can use Util::resolve_pkg_path.

=back

=head1 AUTHOR

Originally written by Niels Thykier <niels@thykier.net> for Lintian.

=head1 SEE ALSO

lintian(1), Lintian::Collect(3), Lintian::Collect::Binary(3),
Lintian::Collect::Source(3)

=cut


# files/empty-package -- lintian check script -*- perl -*-

# Copyright (C) 1998 Christian Schwarz and Richard Braakman
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

package Lintian::files::empty_package;

use strict;
use warnings;
use autodie;

use Moo;

with('Lintian::Check');

# Common files stored in /usr/share/doc/$pkg that aren't sufficient to
# consider the package non-empty.
my $STANDARD_FILES = Lintian::Data->new('files/standard-files');

sub always {
    my ($self) = @_;

    # check if package is empty
    my $is_dummy = $self->info->is_pkg_class('any-meta');

    return
      if $is_dummy;

    my $pkg = $self->package;
    my $ppkg = quotemeta($self->package);

    my $is_empty = 1;
    for my $file ($self->info->sorted_index) {

        # ignore directories
        next
          if $file->name =~ m,/$,;

        # skip if file is outside /usr/share/doc/$pkg directory
        if ($file->name !~ m,^usr/share/doc/\Q$pkg\E,) {
            # - except if it is a lintian override.
            next
              if $file->name =~ m{\A
                             # Except for:
                             usr/share/ (?:
                                 # lintian overrides
                                 lintian/overrides/$ppkg(?:\.gz)?
                                 # reportbug scripts/utilities
                             | bug/$ppkg(?:/(?:control|presubj|script))?
                             )\Z}xsm;

            $is_empty = 0;
            last;
        }

        # skip if /usr/share/doc/$pkg has files in a subdirectory
        if ($file->name =~ m,^usr/share/doc/\Q$pkg\E/[^/]++/,) {
            $is_empty = 0;
            last;
        }

        # skip /usr/share/doc/$pkg symlinks.
        next
          if $file->name eq "usr/share/doc/$pkg";

        # For files directly in /usr/share/doc/$pkg, if the
        # file isn't one of the uninteresting ones, the
        # package isn't empty.
        next
          if $STANDARD_FILES->known($file->basename);

        # ignore all READMEs
        next
          if $file->basename =~ m/^README(?:\..*)?$/i;

        my $pkg_arch = $self->processable->pkg_arch;
        unless ($pkg_arch eq 'all') {
            # binNMU changelog (debhelper)
            next
              if $file->basename eq "changelog.Debian.${pkg_arch}.gz";
        }

        # buildinfo file (dh-buildinfo)
        next
          if $file->basename eq "buildinfo_${pkg_arch}.gz";

        $is_empty = 0;
        last;
    }

    if ($is_empty) {

        $self->tag('empty-binary-package')
          if $self->type eq 'binary';

        $self->tag('empty-udeb-package')
          if $self->type eq 'udeb';
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

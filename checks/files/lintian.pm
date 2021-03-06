# files/lintian -- lintian check script -*- perl -*-

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

package Lintian::files::lintian;

use strict;
use warnings;
use autodie;

use Moo;

with('Lintian::Check');

has ppkg => (is => 'rwp');

sub setup {
    my ($self) = @_;

    $self->_set_ppkg(quotemeta($self->package));
    return;
}

sub files {
    my ($self, $file) = @_;

    my $ppkg = $self->ppkg;

    # misplaced overrides
    if ($file->name =~ m,^usr/share/doc/$ppkg/override\.[lL]intian(?:\.gz)?$,
        or $file->name =~ m,^usr/share/lintian/overrides/$ppkg/.+,) {

        $self->tag('override-file-in-wrong-location', $file->name);

    } elsif ($file->name =~ m,^usr/share/lintian/overrides/(.+)/.+$,) {

        $self->tag('override-file-in-wrong-package', $file->name)
          unless $1 eq $self->package;
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

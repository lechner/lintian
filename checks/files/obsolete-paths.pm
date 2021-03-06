# files/obsolete-paths -- lintian check script -*- perl -*-

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

package Lintian::files::obsolete_paths;

use strict;
use warnings;
use autodie;

use Moo;

with('Lintian::Check');

my $OBSOLETE_PATHS = Lintian::Data->new(
    'files/obsolete-paths',
    qr/\s*\->\s*/,
    sub {
        my @sliptline =  split(/\s*\~\~\s*/, $_[1], 2);

        if (scalar(@sliptline) != 2) {
            die "Syntax error in files/obsolete-paths $.";
        }

        my ($newdir, $moreinfo) =  @sliptline;

        return {
            'newdir' => $newdir,
            'moreinfo' => $moreinfo,
            'match' => qr/$_[0]/x,
            'olddir' => $_[0],
        };
    });

sub files {
    my ($self, $file) = @_;

    # check for generic obsolete path
    foreach my $obsolete_path ($OBSOLETE_PATHS->all) {

        my $obs_data = $OBSOLETE_PATHS->value($obsolete_path);
        my $oldpathmatch = $obs_data->{'match'};

        if ($file->name =~ m{$oldpathmatch}) {

            my $oldpath  = $obs_data->{'olddir'};
            my $newpath  = $obs_data->{'newdir'};
            my $moreinfo = $obs_data->{'moreinfo'};

            $self->tag('package-installs-into-obsolete-dir',
                $file->name, ':', $oldpath, '->', $newpath, $moreinfo);
        }
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

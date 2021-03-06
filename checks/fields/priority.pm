# fields/priority -- lintian check script (rewrite) -*- perl -*-
#
# Copyright (C) 2004 Marc Brockschmidt
#
# Parts of the code were taken from the old check script, which
# was Copyright (C) 1998 Richard Braakman (also licensed under the
# GPL 2 or higher)
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

package Lintian::fields::priority;

use strict;
use warnings;
use autodie;

use List::MoreUtils qw(any);
use Moo;

use Lintian::Data ();

with('Lintian::Check');

my $KNOWN_PRIOS = Lintian::Data->new('fields/priorities');

sub binary {
    my ($self) = @_;

    my $info = $self->info;

    my $priority = $info->unfolded_field('priority');

    unless (defined $priority) {
        $self->tag('no-priority-field');
        return;
    }
}

sub always {
    my ($self) = @_;

    my $pkg = $self->package;
    my $type = $self->type;
    my $info = $self->info;

    my $priority = $info->unfolded_field('priority');

    return
      unless defined $priority;

    if ($type eq 'source' || !$info->is_pkg_class('auto-generated')) {

        $self->tag('priority-extra-is-replaced-by-priority-optional')
          if $priority eq 'extra';

        # Re-map to optional to avoid an additional warning from
        # lintian
        $priority = 'optional'
          if $priority eq 'extra';
    }

    $self->tag('unknown-priority', $priority)
      unless $KNOWN_PRIOS->known($priority);

    $self->tag('excessive-priority-for-library-package', $priority)
      if $pkg =~ m/^lib/o
      && $pkg !~ m/-bin$/o
      && $pkg !~ m/^libc[0-9.]+$/o
      && (any { $_ eq $info->field('section', '') } qw(libdevel libs))
      && (any { $_ eq $priority } qw(required important standard));

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

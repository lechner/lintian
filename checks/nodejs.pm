# nodejs -- lintian check script -*- perl -*-

# Copyright (C) 2019, Xavier Guimard <yadd@debian.org>
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

package Lintian::nodejs;

use strict;
use warnings;
use autodie;

use List::MoreUtils qw(any);
use Moo;

use Lintian::Relation;

with('Lintian::Check');

sub source {
    my ($self) = @_;

    my $pkg = $self->package;
    my $info = $self->info;

    # debian/control check
    my @testsuites = split(m/\s*,\s*/, $info->source_field('testsuite', ''));
    if (any { /^autopkgtest-pkg-nodejs$/ } @testsuites) {
        # Check control file exists in sources
        my $filename = 'debian/tests/pkg-js/test';
        my $path = $info->index_resolved_path($filename);

        # Ensure test file contains something
        if ($path and $path->is_open_ok) {
            $self->tag('pkg-js-autopkgtest-test-is-empty', $filename)
              unless any { /^[^#]*\w/m } $path->file_contents;
        } else {
            $self->tag('pkg-js-autopkgtest-test-is-missing', $filename);
        }

        # Ensure all files referenced in debian/tests/pkg-js/files exist
        $path = $info->index_resolved_path('debian/tests/pkg-js/files');
        if ($path) {
            my @list = map { chomp; s/^\s+(.*?)\s+$/$1/; $_ }
              grep { /\w/ } split /\n/, $path->file_contents;
            $self->path_exists($_) foreach (@list);
        }
    }
    # debian/rules check
    my $droot = $info->index_resolved_path('debian/') or return;
    my $drules = $droot->child('rules') or return;
    return unless $drules->is_open_ok;
    my $rules_fd = $drules->open;
    my $command_prefix_pattern = qr/\s+[@+-]?(?:\S+=\S+\s+)*/;
    my ($seen_nodejs,$override_test,$seen_dh_dynamic);
    while (<$rules_fd>) {
        # reconstitute splitted lines
        while (s,\\$,, and defined(my $cont = <$rules_fd>)) {
            $_ .= $cont;
        }
        # skip comments
        next if /^\s*\#/;
        if (m,^(?:$command_prefix_pattern)dh\s+,) {
            $seen_dh_dynamic = 1 if m/\$[({]\w/;
            while (m/\s--with(?:=|\s+)(['"]?)(\S+)\1/go) {
                my $addon_list = $2;
                for my $addon (split(m/,/o, $addon_list)) {
                    $seen_nodejs = 1 if $addon eq 'nodejs';
                }
            }
        } elsif (/^([^:]*override_dh_[^:]*):/) {
            $override_test = 1 if $1 eq 'auto_test';
        }
    }
    if(     $seen_nodejs
        and not $override_test
        and not $seen_dh_dynamic) {
        my $filename = 'debian/tests/pkg-js/test';
        my $path = $info->index_resolved_path($filename);
        # Ensure test file contains something
        if ($path) {
            $self->tag('pkg-js-tools-test-is-empty', $filename)
              unless any { /^[^#]*\w/m } $path->file_contents;
        } else {
            $self->tag('pkg-js-tools-test-is-missing', $filename);
        }
    }
    return;
}

sub binary {
    my ($self) = @_;

    my $pkg = $self->package;
    my $info = $self->info;

    if ($pkg !~ /-dbg$/) {
        foreach my $file ($info->sorted_index) {
            my $fname = $file->name;
            if (    $file->is_file
                and $fname =~ m,^usr/(?:share|lib(?:/[^/]+)?)/nodejs/,) {
                $self->tag('nodejs-module-installed-in-usr-lib', $fname)
                  if $fname =~ m#usr/lib/nodejs/.*#;
                $self->tag('node-package-install-in-nodejs-rootdir', $fname)
                  if $fname
                  =~ m#usr/(?:share|lib(?:/[^/]+)?)/nodejs/(?:package\.json|[^/]*\.js)$#;
            }
        }
    }
    return;
}

sub path_exists {
    my ($self, $expr) = @_;

    my $info = $self->info;

    # Split each line in path elements
    my @elem= map { s/\*/.*/g; s/^\.\*$/.*\\w.*/; $_ ? qr{^$_/?$} : () }
      split m#/#,
      $expr;
    my @dir = ('.');

    # Follow directories
  LOOP: while (my $re = shift @elem) {
        foreach my $i (0 .. $#dir) {
            my ($dir, @tmp);

            next unless defined($dir = $info->index_resolved_path($dir[$i]));
            next unless $dir->is_dir;
            last LOOP
              unless (
                @tmp= map { $_->basename }
                grep { $_->basename =~ $re } $dir->children
              );

            # Stop searching: at least one element found
            return unless @elem;

            # If this is the last element of path, store current elements
            my $pwd = $dir[$i];
            $dir[$i] .= '/' . shift(@tmp);

            push @dir, map { "$pwd/$_" } @tmp if @tmp;
        }
    }

    # No element found
    $self->tag('pkg-js-autopkgtest-file-does-not-exist', $expr);
    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

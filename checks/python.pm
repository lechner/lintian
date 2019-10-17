# python -- lintian check script -*- perl -*-
#
# Copyright (C) 2016 Chris Lamb
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

package Lintian::python;

use strict;
use warnings;
use autodie;

use List::MoreUtils qw(any none);
use Moo;

use Lintian::Relation qw(:constants);
use Lintian::Relation::Version qw(versions_lte);

with('Lintian::Check');

my @FIELDS = qw(Depends Pre-Depends Recommends Suggests);
my @IGNORE = qw(-dev$ -docs?$ -common$ -tools$);
my @PYTHON2 = qw(python python2.7 python-dev);
my @PYTHON3 = qw(python3 python3-dev);

my %DJANGO_PACKAGES = (
    '^python3-django-' => 'python3-django',
    '^python2?-django-' => 'python-django',
);

my %REQUIRED_DEPENDS = (
    'python2' => 'python-minimal:any | python:any',
    'python3' => 'python3-minimal:any | python3:any',
);

my %MISMATCHED_SUBSTVARS = (
    '^python3-.+' => '${python:Depends}',
    '^python2?-.+' => '${python3:Depends}',
);

my $VERSIONS = Lintian::Data->new('python/versions', qr/\s*=\s*/o);
my @VERSION_FIELDS = qw(x-python-version xs-python-version x-python3-version);

sub source {
    my ($self) = @_;

    my $pkg = $self->package;
    my $info = $self->info;

    my @package_names = $info->binaries;
    foreach my $bin (@package_names) {
        # Python 2 modules
        if ($bin =~ /^python2?-(.*)$/) {
            my $suffix = $1;
            next if any { $bin =~ /$_/ } @IGNORE;
            next if any { $_ eq "python3-${suffix}" } @package_names;
            # Don't trigger if we ship any Python 3 module
            next if any {
                $info->binary_relation($_, 'all')
                  ->implies('${python3:Depends}')
            }
            @package_names;
            $self->tag('python-foo-but-no-python3-foo', $bin);
        }
    }

    my $build_all = $info->relation('build-depends-all');
    $self->tag('build-depends-on-python-sphinx-only')
      if $build_all->implies('python-sphinx')
      and not $build_all->implies('python3-sphinx');

    $self->tag(
        'alternatively-build-depends-on-python-sphinx-and-python3-sphinx')
      if $info->field('build-depends', '')
      =~ m,\bpython-sphinx\s+\|\s+python3-sphinx\b,g;

    # Mismatched substvars
    foreach my $regex (keys %MISMATCHED_SUBSTVARS) {
        my $substvar = $MISMATCHED_SUBSTVARS{$regex};
        for my $binpkg ($info->binaries) {
            next if any { $binpkg =~ /$_/ } @IGNORE;
            next if $binpkg !~ qr/$regex/;
            $self->tag('mismatched-python-substvar', $binpkg, $substvar)
              if $info->binary_relation($binpkg, 'all')->implies($substvar);
        }
    }

    foreach my $field (@VERSION_FIELDS) {
        my $pyversion = $info->source_field($field);
        next unless defined($pyversion);

        my @valid = (
            ['\d+\.\d+', '\d+\.\d+'],['\d+\.\d+'],
            ['\>=\s*\d+\.\d+', '\<\<\s*\d+\.\d+'],['\>=\s*\d+\.\d+'],
            ['current', '\>=\s*\d+\.\d+'],['current'],
            ['all']);

        my @pyversion = split(/\s*,\s*/, $pyversion);

        if ($pyversion =~ m/^current/) {
            $self->tag('python-version-current-is-deprecated', $field);
        }

        if (@pyversion > 2) {
            if (any { !/^\d+\.\d+$/ } @pyversion) {
                $self->tag('malformed-python-version', $field, $pyversion);
            }
        } else {
            my $okay = 0;
            for my $rule (@valid) {
                if (
                    $pyversion[0] =~ /^$rule->[0]$/
                    && ((
                               $pyversion[1]
                            && $rule->[1]
                            && $pyversion[1] =~ /^$rule->[1]$/
                        )
                        || (!$pyversion[1] && !$rule->[1]))
                ) {
                    $okay = 1;
                    last;
                }
            }
            $self->tag('malformed-python-version', $field, $pyversion)
              unless $okay;
        }

        if ($pyversion =~ /\b(([23])\.\d+)$/) {
            my ($v, $major) = ($1, $2);
            my $old = $VERSIONS->value("old-python$major");
            my $ancient = $VERSIONS->value("ancient-python$major");

            if (versions_lte($v, $ancient)) {
                $self->tag('ancient-python-version-field', $field, $v);
            } elsif (versions_lte($v, $old)) {
                $self->tag('old-python-version-field', $field, $v);
            }
        }
    }

    $self->tag('source-package-encodes-python-version')
      if $info->name =~ m/^python\d-/
      and $info->name ne 'python3-defaults';

    return;
}

sub binary {
    my ($self) = @_;

    my $pkg = $self->package;
    my $info = $self->info;

    my $deps = Lintian::Relation->and($info->relation('all'),
        $info->relation('provides'), $pkg);
    my @entries
      = $info->changelog
      ? @{$info->changelog->entries}
      : ();

    # Check for missing dependencies
    if ($pkg !~ /-dbg$/) {
        foreach my $file ($info->sorted_index) {
            if (    $file->is_file
                and $file
                =~ m,usr/lib/(?<version>python[23])[\d.]*/(?:site|dist)-packages,
                and not $deps->implies($REQUIRED_DEPENDS{$+{version}})) {
                $self->tag('python-package-missing-depends-on-python');
                last;
            }
        }
    }

    # Check for duplicate dependencies
    for my $field (@FIELDS) {
        my $dep = $info->relation($field);
      FIELD: for my $py2 (@PYTHON2) {
            for my $py3 (@PYTHON3) {
                if ($dep->implies("$py2:any") and $dep->implies("$py3:any")) {
                    $self->tag('depends-on-python2-and-python3',
                        "$field: $py2, [..], $py3");
                    last FIELD;
                }
            }
        }
    }

    # Python 2 modules
    if (    $pkg =~ /^python2?-/
        and none { $pkg =~ /$_$/ } @IGNORE
        and @entries == 1
        and $entries[0]->Changes
        !~ /\bpython ?2(?:\.x)? (?:variant|version)\b/im
        and index($entries[0]->Changes, $pkg) == -1) {
        $self->tag('new-package-should-not-package-python2-module', $pkg);
    }

    # Python applications
    if ($pkg !~ /^python[23]?-/ and none { $_ eq $pkg } @PYTHON2) {
        for my $field (@FIELDS) {
            for my $dep (@PYTHON2) {
                $self->tag(
                    'dependency-on-python-version-marked-for-end-of-life',
                    "($field: $dep)")
                  if $info->relation($field)->implies("$dep:any");
            }
        }
    }

    # Django modules
    foreach my $regex (keys %DJANGO_PACKAGES) {
        my $basepkg = $DJANGO_PACKAGES{$regex};
        next if $pkg !~ /$regex/;
        next if any { $pkg =~ /$_/ } @IGNORE;
        $self->tag('django-package-does-not-depend-on-django', $basepkg)
          if not $info->relation('strong')->implies($basepkg);
    }

    if ($pkg =~ /^python([23]?)-/ and none { $pkg =~ /$_/ } @IGNORE) {
        my $version = $1 || '2'; # Assume python-foo is a Python 2.x package
        my @prefixes = ($version eq '2') ? 'python3' : ('python', 'python2');

        for my $field (@FIELDS) {
            for my $prefix (@prefixes) {
                my $visit = sub {
                    my $rel = $_;
                    return if any { $rel =~ /$_/ } @IGNORE;
                    $self->tag(
'python-package-depends-on-package-from-other-python-variant',
                        "$field: $rel"
                    ) if /^$prefix-/;
                };
                $info->relation($field)->visit($visit, VISIT_PRED_NAME);
            }
        }
    }

    for my $file ($info->sorted_index) {
        next unless $file->is_file;
        next unless $file->is_open_ok;
        next unless $file =~ m,(usr/)?bin/[^/]+,;
        my $fd = $file->open();
        my $line = <$fd>;
        $self->tag('script-uses-unversioned-python-in-shebang', $file)
          if $line && $line =~ m,^#!\s*(/usr/bin/env\s*)?(/usr/bin/)?python$,;
        close($fd);
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

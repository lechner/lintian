# phppear -- lintian check script -*- perl -*-

# Copyright (C) 2013 Mathieu Parent <math.parent@gmail.com>
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

package Lintian::phppear;

use strict;
use warnings;
use autodie;

use List::MoreUtils qw(none);
use Moo;

use Lintian::Relation;

with('Lintian::Check');

sub source {
    my ($self) = @_;

    my $pkg = $self->package;
    my $type = $self->type;
    my $info = $self->info;

    # Don't check package if it doesn't contain a .php file
    if (none { $_->basename =~ m/\.php$/i } $info->sorted_index) {
        return;
    }

    my $bdepends = $info->relation('build-depends');
    my $package_type = 'unknown';

    # PEAR or PECL package
    my $package_xml = $info->index('package.xml');
    my $package2_xml = $info->index('package2.xml');
    if (defined($package_xml) || defined($package2_xml)) {
        # Checking source builddep
        if (!$bdepends->implies('pkg-php-tools')) {
            $self->tag('pear-package-without-pkg-php-tools-builddep');
        } else {
            # Checking first binary relations
            my @binaries = $info->binaries;
            my $binary = $binaries[0];
            my $depends = $info->binary_relation($binary, 'depends');
            my $recommends = $info->binary_relation($binary, 'recommends');
            my $breaks = $info->binary_relation($binary, 'breaks');
            if (!$depends->implies('${phppear:Debian-Depends}')) {
                $self->tag('pear-package-but-missing-dependency', 'Depends');
            }
            if (!$recommends->implies('${phppear:Debian-Recommends}')) {
                $self->tag('pear-package-but-missing-dependency','Recommends');
            }
            if (!$breaks->implies('${phppear:Debian-Breaks}')) {
                $self->tag('pear-package-but-missing-dependency', 'Breaks');
            }
            # Checking description
            my $description = $info->binary_field($binary, 'description');
            if ($description !~ /\$\{phppear:summary\}/) {
                $self->tag('pear-package-not-using-substvar',
                    '${phppear:summary}');
            }
            if ($description !~ /\$\{phppear:description\}/) {
                $self->tag('pear-package-not-using-substvar',
                    '${phppear:description}');
            }
            if (defined($package_xml) && $package_xml->is_regular_file) {
                # Wild guess package type as in
                # PEAR_PackageFile_v2::getPackageType()
                my $package_xml_fd = $package_xml->open;
                while (<$package_xml_fd>) {
                    if (
                        m{\A \s* <
                           (php|extsrc|extbin|zendextsrc|zendextbin)
                           release \s* /? > }xsm
                    ) {
                        $package_type = $1;
                        last;
                    }
                    if (/^\s*<bundle\s*\/?>/){
                        $package_type = 'bundle';
                        last;
                    }
                }
                close($package_xml_fd);
                if ($package_type eq 'extsrc') { # PECL package
                    if (!$bdepends->implies('php-dev')) {
                        $self->tag('pecl-package-requires-build-dependency',
                            'php-dev');
                    }
                    if (!$bdepends->implies('dh-php')) {
                        $self->tag('pecl-package-requires-build-dependency',
                            'dh-php');
                    }
                }
            }
        }
    }
    # PEAR channel
    my $channel_xml = $info->index('channel.xml');
    if (defined($channel_xml)) {
        if (!$bdepends->implies('pkg-php-tools')) {
            $self->tag('pear-channel-without-pkg-php-tools-builddep');
        }
    }
    # Composer package
    my $composer_json = $info->index('composer.json');
    if (   !defined($package_xml)
        && !defined($package2_xml)
        && defined($composer_json)) {
        if (!$bdepends->implies('pkg-php-tools')) {
            $self->tag('composer-package-without-pkg-php-tools-builddep');
        }
    }
    # Check rules
    if (
        $bdepends->implies('pkg-php-tools')
        && (   defined($package_xml)
            || defined($package2_xml)
            || defined($channel_xml)
            || defined($composer_json))
    ) {
        my $rules = $info->index_resolved_path('debian/rules');
        if ($rules and $rules->is_open_ok) {
            my $has_buildsystem_phppear = 0;
            my $has_addon_phppear = 0;
            my $has_addon_phpcomposer= 0;
            my $has_addon_php = 0;
            my $rules_fd = $rules->open;
            while (<$rules_fd>) {
                while (s,\\$,, and defined(my $cont = <$rules_fd>)) {
                    $_ .= $cont;
                }
                next if /^\s*\#/;
                if (
m/^\t\s*dh\s.*--buildsystem(?:=|\s+)(?:\S+,)*phppear(?:,\S+)*\s/
                ) {
                    $has_buildsystem_phppear = 1;
                }
                if (m/^\t\s*dh\s.*--with(?:=|\s+)(?:\S+,)*phppear(?:,\S+)*\s/){
                    $has_addon_phppear = 1;
                }
                if (
m/^\t\s*dh\s.*--with(?:=|\s+)(?:\S+,)*phpcomposer(?:,\S+)*\s/
                ) {
                    $has_addon_phpcomposer = 1;
                }
                if (m/^\t\s*dh\s.*--with(?:=|\s+)(?:\S+,)*php(?:,\S+)*\s/) {
                    $has_addon_php = 1;
                }
            }
            close($rules_fd);
            if (   defined($package_xml)
                || defined($package2_xml)
                || defined($channel_xml)) {
                if (!$has_buildsystem_phppear) {
                    $self->tag('missing-pkg-php-tools-buildsystem', 'phppear');
                }
                if (!$has_addon_phppear) {
                    $self->tag('missing-pkg-php-tools-addon', 'phppear');
                }
                if (($package_type eq 'extsrc') and not $has_addon_php) {
                    $self->tag('missing-pkg-php-tools-addon', 'php');
                }
            }
            if (   !defined($package_xml)
                && !defined($package2_xml)
                && defined($composer_json)) {
                if (!$has_addon_phpcomposer) {
                    $self->tag('missing-pkg-php-tools-addon', 'phpcomposer');
                }
            }
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

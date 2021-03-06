# changes-file -- lintian check script -*- perl -*-

# Copyright (C) 1998 Christian Schwarz and Richard Braakman
#
# This program is free software.  It is distributed under the terms of
# the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any
# later version.
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

package Lintian::changes_file;

use strict;
use warnings;
use autodie;

use List::MoreUtils qw(any);
use Moo;

use Lintian::Data;
use Lintian::Maintainer qw(check_maintainer);
use Lintian::Util qw(get_file_checksum);

with('Lintian::Check');

my $KNOWN_DISTS = Lintian::Data->new('changes-file/known-dists');

sub changes {
    my ($self) = @_;

    my $info = $self->info;
    my $group = $self->group;

    # If we don't have a Format key, something went seriously wrong.
    # Tag the file and skip remaining processing.
    if (!$info->field('format')) {
        $self->tag('malformed-changes-file');
        return;
    }

    # Description is mandated by dak, but only makes sense if binary
    # packages are included.  Don't tag pure source uploads.
    if (  !$info->field('description')
        && $info->field('architecture', '') ne 'source') {
        $self->tag('no-description-in-changes-file');
    }

    # check distribution field
    if (defined $info->field('distribution')) {
        my @distributions = split /\s+/o, $info->field('distribution');
        for my $distribution (@distributions) {
            if ($distribution eq 'UNRELEASED') {
                # ignore
            } else {
                my $dist = $distribution;
                if ($dist !~ m/^(?:sid|unstable|experimental)/) {
                    # Strip common "extensions" for distributions
                    # (except sid and experimental, where they would
                    # make no sense)
                    $dist =~ s/- (?:backports(?:-sloppy)?
                                   |lts
                                   |proposed(?:-updates)?
                                   |updates
                                   |security
                                   |volatile)$//xsmo;

                    if ($distribution =~ /backports/) {
                        my $bpo1 = 1;
                        if ($info->field('version') =~ m/~bpo(\d+)\+(\d+)$/) {
                            my $distnumber = $1;
                            my $bpoversion = $2;
                            if (
                                ($dist eq 'squeeze' && $distnumber ne '60')
                                ||(    $distribution eq 'wheezy-backports'
                                    && $distnumber ne '70')
                                ||($distribution eq 'wheezy-backports-sloppy'
                                    && $distnumber ne '7')
                                ||($dist eq 'jessie' && $distnumber ne '8')
                            ) {
                                $self->tag(
'backports-upload-has-incorrect-version-number',
                                    $info->field('version'),$distribution
                                );
                            }
                            $bpo1 = 0 if ($bpoversion > 1);
                        } else {
                            $self->tag(
'backports-upload-has-incorrect-version-number',
                                $info->field('version'));
                        }
                        # for a ~bpoXX+2 or greater version, there
                        # probably will be only a single changelog entry
                        if ($bpo1) {
                            my $changes_versions = 0;
                            foreach my $change_line (
                                split("\n", $info->field('changes'))) {
                      # from Parse/DebianChangelog.pm
                      # the changelog entries in the changes file are in a
                      # different format than in the changelog, so the standard
                      # parsers don't work. We just need to know if there is
                      # info for more than 1 entry, so we just copy part of the
                      # parse code here
                                if ($change_line
                                    =~ m/^\s*(?:\w[-+0-9a-z.]*) \((?:[^\(\) \t]+)\)(?:(?:\s+[-+0-9a-z.]+)+)\;\s*(?:.*)$/i
                                ) {
                                    $changes_versions++;
                                }
                            }
                            # only complain if there is a single entry,
                            # if we didn't find any changelog entry, there is
                            # probably something wrong with the parsing, so we
                            # don't emit a tag
                            if ($changes_versions == 1) {
                                $self->tag('backports-changes-missing');
                            }
                        }
                    }
                } else {
                    $self->tag(
                        'upload-has-backports-version-number',
                        $info->field('version'),
                        $distribution
                    ) if $info->field('version') =~ m/~bpo(\d+)\+(\d+)$/;
                }
                if (!$KNOWN_DISTS->known($dist)) {
                    # bad distribution entry
                    $self->tag('bad-distribution-in-changes-file',
                        $distribution);
                }

                my $changes = $info->field('changes');
                if (defined $changes) {
                    # take the first non-empty line
                    $changes =~ s/^\s+//s;
                    $changes =~ s/\n.*//s;

                    if ($changes
                        =~ m/^\s*(?:\w[-+0-9a-z.]*)\s*\([^\(\) \t]+\)\s*([-+0-9A-Za-z.]+)\s*;/
                    ) {
                        my $changesdist = $1;
                        if ($changesdist eq 'UNRELEASED') {
                            $self->tag('unreleased-changes');
                        } elsif ($changesdist ne $distribution
                            && $changesdist ne $dist) {
                            if (   $changesdist eq 'experimental'
                                && $dist ne 'experimental') {
                                $self->tag(
                                    'distribution-and-experimental-mismatch',
                                    $distribution);
                            } elsif ($KNOWN_DISTS->known($dist)) {
                                $self->tag('distribution-and-changes-mismatch',
                                    $distribution, $changesdist);
                            }
                        }
                    }
                }
            }
        }

        if ($#distributions > 0) {
            $self->tag('multiple-distributions-in-changes-file',
                $info->field('distribution'));
        }

    }

    # Urgency is only recommended by Policy.
    if (!$info->field('urgency')) {
        $self->tag('no-urgency-in-changes-file');
    } else {
        my $urgency = lc $info->field('urgency');
        $urgency =~ s/ .*//o;
        unless ($urgency =~ /^(?:low|medium|high|critical|emergency)$/o) {
            $self->tag('bad-urgency-in-changes-file', $info->field('urgency'));
        }
    }

    # Changed-By is optional in Policy, but if set, must be
    # syntactically correct.  It's also used by dak.
    if ($info->field('changed-by')) {
        check_maintainer($info->field('changed-by'), 'changed-by');
    }

    my $files = $info->files;
    my $path = readlink($info->lab_data_path('changes'));
    my %num_checksums;
    $path =~ s#/[^/]+$##;
    foreach my $file (keys %$files) {
        my $file_info = $files->{$file};

        # check section
        if (   ($file_info->{section} eq 'non-free')
            or ($file_info->{section} eq 'contrib')) {
            $self->tag('bad-section-in-changes-file', $file,
                $file_info->{section});
        }

        foreach my $alg (qw(sha1 sha256)) {
            my $checksum_info = $file_info->{checksums}{$alg};
            if (defined $checksum_info) {
                if ($file_info->{size} != $checksum_info->{filesize}) {
                    $self->tag('file-size-mismatch-in-changes-file', $file,
                           $file_info->{size} . ' != '
                          .$checksum_info->{filesize});
                }
            }
        }

        # check size
        my $filename = "$path/$file";
        my $size = -s $filename;

        if ($size ne $file_info->{size}) {
            $self->tag('file-size-mismatch-in-changes-file',
                $file,$file_info->{size} . " != $size");
        }

        # check checksums
        foreach my $alg (qw(md5 sha1 sha256)) {
            next unless exists $file_info->{checksums}{$alg};

            my $real_checksum = get_file_checksum($alg, $filename);
            $num_checksums{$alg}++;

            if ($real_checksum ne $file_info->{checksums}{$alg}{sum}) {
                $self->tag('checksum-mismatch-in-changes-file', $alg, $file);
            }
        }
    }

    my %debs = map { m/^([^_]+)_/ => 1 } grep { m/\.deb$/ } keys %$files;
    foreach my $pkg_name (keys %debs) {
        if ($pkg_name =~ m/^(.+)-dbgsym$/) {
            $self->tag('package-builds-dbg-and-dbgsym-variants',
                "$1-{dbg,dbgsym}")
              if exists $debs{"$1-dbg"};
        }
    }

    # Check that we have a consistent number of checksums and files
    foreach my $alg (keys %num_checksums) {
        my $seen = $num_checksums{$alg};
        my $expected = keys %{$files};
        $self->tag(
            'checksum-count-mismatch-in-changes-file',
            "$seen $alg checksums != $expected files"
        ) if $seen != $expected;
    }

    return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

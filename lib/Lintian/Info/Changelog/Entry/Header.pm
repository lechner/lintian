#
# Lintian::Info::Changelog::Entry::Header
#
# Copyright 2019 Felix Lechner <felix.lechner@lease-up.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#

=head1 NAME

Lintian::Info::Changelog::Entry::Header - represents one entry in a Debian changelog

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 Methods

=head3 init

Creates a new object, no options.

=head3 new

Alias for init.

=head3 is_empty

Checks if the object is actually initialized with data. Due to limitations
in Parse::DebianChangelog this currently simply checks if one of the
fields Source, Version, Maintainer, Date, or Changes is initialized.

=head2 Accessors

The following fields are available via accessor functions (all
fields are string values unless otherwise noted):

=over 4

=item *

Source

=item *

Version

=item *

Distribution

=item *

Urgency

=item *

Extra_Fields (all fields except for urgency as hash; POD spelling forces the underscore)

=item *

Header (the whole header in verbatim form)

=item *

Changes (the actual content of the bug report, in verbatim form)

=item *

Trailer (the whole trailer in verbatim form)

=item *

Closes (Array of bug numbers)

=item *

Maintainer (name B<and> email address)

=item *

Date

=item *

Timestamp (Date expressed in seconds since the epoch)

=item *

ERROR (last parse error related to this entry in the format described
at Parse::DebianChangelog::get_parse_errors.

=back

=cut

package Lintian::Info::Changelog::Entry::Header;

use strict;
use warnings;

use Moo;

use constant EMPTY => q{};

has Source => (is => 'rw');
has Version => (is => 'rw');
has Distribution => (is => 'rw');
has Urgency => (is => 'rw', default => 'unknown');
has Urgency_LC => (is => 'rw', default => 'unknown');
has Urgency_Comment => (is => 'rw', default => EMPTY);
has ExtraFields => (is => 'rw');
has Literal => (is => 'rw');
has ERROR => (is => 'rw');

=item parse (STRING)

Parses STRING as the content of a debian/changelog file.

=cut

sub parse {
    my ($self, $contents) = @_;

    my $source_pattern = qr/(\w[-+0-9A-Za-z.]*)/;
    my $version_pattern = qr/([^\(\) \t]+)/;
    my $distribution_pattern = qr/((?:\s+[-+0-9A-Za-z.]+)+)/;

    my ($source, $version, $distribution) 
      = ($contents =~ qr/^/
         . $source_pattern
         . qr/\s+/ . qr/\(/ . $version_pattern . qr/\)/ . qr/\s+/
         . $distribution_pattern . qr/\;/ . qr/\s*(?<kv>.*)$/i


}

1;
__END__

=head1 SEE ALSO

Originally based on Parse::DebianChangelog by Frank Lichtenheld, E<lt>frank@lichtenheld.deE<gt>

=head1 AUTHOR

Written by Felix Lechner <felix.lechner@lease-up.com> for Lintian in response to #933134.

=head1 COPYRIGHT AND LICENSE

Please see in the code; FSF's standard short text triggered a POD spelling error
here.

=cut

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

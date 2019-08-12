# Copyright © 2019 Felix Lechner <felix.lechner@lease-up.com>
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

package Lintian::Info::Changelog;

use strict;
use warnings;
use v5.16;

use Carp;
use Date::Parse;
use Dpkg::Changelog::Debian;
use Moo;

use Lintian::Info::Changelog::Entry;

use constant EMPTY => q{};
use constant SPACE => q{ };
use constant ASTERISK => q{*};
use constant UNKNOWN => q{unknown};

=head1 NAME

Lintian::Info::Changelog -- Parse a literal version string into its constituents

=head1 SYNOPSIS

 use Lintian::Info::Changelog;

 my $version = Lintian::Info::Changelog->new;
 $version->set('1.2.3-4', undef);

=head1 DESCRIPTION

A class for parsing literal version strings

=head1 CLASS METHODS

=over 4

=item new ()

Creates a new Lintian::Info::Changelog object.

=cut

=item find_closes

Takes one string as argument and finds "Closes: #123456, #654321" statements
as supported by the Debian Archive software in it. Returns all closed bug
numbers in an array reference.

=cut

sub find_closes {
    my $changes = shift;
    my @closes = ();

    while ($changes
        && ($changes
            =~ /closes:\s*(?:bug)?\#?\s?\d+(?:,\s*(?:bug)?\#?\s?\d+)*/ig)) {
        push(@closes, $& =~ /\#?\s?(\d+)/g);
    }

    @closes = sort { $a <=> $b } @closes;
    return \@closes;
}

=back

=head1 INSTANCE METHODS

=over 4

=item parse (STRING)

Parses STRING as the content of a debian/changelog file.

=cut

sub parse {
    my ($self, $contents) = @_;

    my $changelog = Dpkg::Changelog::Debian->new(
                  range   => { all => 1 },
                  verbose => 0,
                                                );

    open my $fh, "<", \$contents;
    $changelog->parse($fh, 'string');
    close $fh;

    my @errors = @{$changelog->get_parse_errors};

    # discard first element, 'string'
    shift @_ for @errors;

    $self->_set_errors(\@errors);

    my @theirs;

    my @ours;
    for my $their (@theirs) {
        my $our = Lintian::Info::Changelog::Entry->new;

        $our->Source(UNKNOWN);

        $our->Version($their->get_version->as_string)
          if defined $their->get_version;

        $our->Distribution(UNKNOWN);

        $our->Urgency(UNKNOWN);
        $our->Urgency_LC(UNKNOWN);
        $our->Urgency_Comment(EMPTY);

        $entry->Header($literal);

        $entry->Source($source);
        $entry->Version($version);

        $distribution =~ s/^\s+//;
        $entry->Distribution($distribution);

        $entry->Closes(find_closes($entry->Changes));

        $entry->Urgency($1);
        $entry->Urgency_LC(lc($1));
        $entry->Urgency_Comment($2);

        $entry->{ExtraFields}{"XS-$k"} = $v;

        $entry->Trailer($literal);

        my ($name, $email) = ($their->get_maintainer() =~ qr//);
        $our->Maintainer("$name <$email>");


        my $dch_date = $entries[0]->get_timestamp;
        my ($weekday_declared, $date) = split(m/,\s*/, $dch_date, 2);
        $date //= EMPTY;
        my ($tz, $weekday_actual);

        $our->Date($date);
        $our->Timestamp($their->get_timepiece->epoch)
          if defined $their->get_timepiece;

        my @changes = $changelog_entry->get_part('changes');
        $changes = join("\n", @$changes) if ref $changes eq 'ARRAY';

        $our->{'Changes'} .= (" \n" x $blanklines)." $_\n";

        if (!$entry->{Items} || $1 eq ASTERISK) {
            $entry->{Items} ||= [];
            push @{$entry->{Items}}, "$_\n";
        } else {
            $entry->{'Items'}[-1] .= (" \n" x $blanklines)." $_\n";
        }

        push(@ours, $our);
    }
    $self->_set_entries(\@ours);

    return;
}

has errors => (is => 'rwp', default => sub { [] });
has entries => (is => 'rwp', default => sub { [] });

=back

=head1 AUTHOR

Originally written by Felix Lechner <felix.lechner@lease-up.com> for Lintian.

=head1 SEE ALSO

lintian(1)

=cut

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

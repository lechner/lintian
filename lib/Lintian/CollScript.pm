# Copyright (C) 2012 Niels Thykier <niels@thykier.net>
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

package Lintian::CollScript;

use strict;
use warnings;

use parent 'Class::Accessor::Fast';

use Carp qw(croak);
use File::Basename qw(dirname);
use IO::Async::Loop;

use Lintian::Deb822Parser qw(read_dpkg_control_utf8);
use Lintian::Util qw(internal_error);

use constant EMPTY => q{};
use constant SPACE => q{ };

=head1 NAME

Lintian::CollScript - Collection script handle

=head1 SYNOPSIS

 use Lintian::CollScript;

 my $cs = Lintian::CollScript->new ("$ENV{'LINTIAN_ROOT'}/collection/index.desc");
 my $name = $cs->name;
 foreach my $needs ($cs->needs_info) {
    print "$name needs $needs\n";
 }

=head1 DESCRIPTION

Instances of this class represents the data in the collection ".desc"
files.  It allows access to the common meta data of the collection
(such as Needs-Info).

=head1 CLASS METHODS

=over 4

=item new (FILE)

Parse FILE as a collection desc file.

=cut

sub new {
    my ($class, $file) = @_;
    my ($header, undef) = read_dpkg_control_utf8($file);
    my $self;
    foreach my $field (qw(collector-script type)) {
        if (($header->{$field}//'') eq '') {
            croak "Required field \"$field\" is missing (or empty) in $file";
        }
    }

    $self = {
        'name' => $header->{'collector-script'},
        'type' => $header->{'type'},
        'type-table' => {},
        'priority' => $header->{'priority'} // 8192,
        'interface' => $header->{'interface'}//'exec',
        'collector_class' => undef,
    };
    $self->{'script_path'} = dirname($file) . '/' . $self->{'name'};
    for my $t (split /\s*,\s*/o, $self->{'type'}) {
        $self->{'type-table'}{$t} = 1;
    }

    bless $self, $class;

    $self->_parse_needs($header->{'needs-info'});
    $self->_load_collector;

    return $self;
}

sub _parse_needs {
    my ($self, $needs) = @_;
    my (@min, @max, %typespec, %seen);

    foreach my $part (split /\s*,\s*/, $needs//'') {
        if ($part =~ m/^ \s* (\S+) \s*  \[ \s* ( [^]]+ ) \s* \] \s*$/x) {
            my ($dep, $typelist) = ($1, $2);
            my @types = split m/\s++/, $typelist;
            if (@types) {
                push @max, $dep unless exists $seen{$dep};
                foreach my $type (@types) {
                    push @{ $typespec{$type} }, $dep;
                }
            } else {
                croak(
                    join(q{ },
                        'Unknown conditional dependency in coll',
                        "$self->{'name'}: $part\n"));
            }
        } else {
            push @min, $part;
            push @max, $part unless exists $seen{$part};
        }
    }
    $self->{'needs_info'}{'min'} = \@min;
    $self->{'needs_info'}{'type'} = \%typespec;
    $self->{'needs_info'}{'max'} = \@max;
    return;
}

=back

=head1 INSTANCE METHODS

=over 4

=item name

Returns the "name" of the collection script.  This is the value in the
Collector-Script field in the file.

=item type

Returns the value stored in the "Type" field of the file.  For the
purpose of testing if the collection applies to a given package type,
the L</is_type> method can be used instead.

=item script_path

Returns the absolute path to the collection script.

=item interface

The call interface for this collection script.

=over 4

=item exec

The collection is run by invoking the script denoted by script_path
with the proper arguments.

This is the default value.

=item perl-coll

The collection is implemented in Perl in such a way that it can be
loaded into perl and run via the L</collect (PKG, TASK, DIR)> method.

Collections that have the "perl-coll" can also be run as if they had
the "exec" interface (see above).

=back

=cut

Lintian::CollScript->mk_ro_accessors(
    qw(name type script_path interface priority));

=item needs_info ([COND])

Returns a list of all items listed in the Needs-Info field.  Neither
the list nor its contents should be modified.

COND is optional and used to determine what conditions are true.  If
omitted, all "extra" dependencies are returned.  Otherwise, only the
dependencies required by COND are included.  COND is a hashref and
with the following key/values:

=over 4

=item type

The value is a package type that determines which package type is
being unpacked.  This is used to determine if the condition for
"<dep> [<type>]" relations are true or not.

=back

=cut

sub needs_info {
    my ($self, $cond) = @_;
    if ($cond && exists $cond->{'type'}) {
        my $needs = $self->{'needs_info'};
        my @min = @{ $needs->{'min'} };
        my $type = $cond->{'type'};
        push @min, @{ $needs->{'type'}{$type} }
          if exists $needs->{'type'}{$type};
        return @min;
    }
    return @{ $self->{'needs_info'}{'max'} };
}

=item is_type (TYPE)

Returns a truth value if this collection can be applied to a TYPE package.

=cut

sub is_type {
    my ($self, $type) = @_;
    return $self->{'type-table'}{$type};
}

=item collect (PKG, TASK, DIR)

=cut

sub collect {
    my ($self, $pkg_name, $task, $dir) = @_;
    my $iface = $self->interface;

    # always use 'exec' under Devel::Cover, which relies on the END handler
    # otherwise coverage would always be zero (or close to it)

    if ($iface eq 'exec' || exists $ENV{'LINTIAN_COVERAGE'}) {
        if (exists $ENV{'LINTIAN_COVERAGE'}) {
            $ENV{'PERL5OPT'} //= EMPTY;
            $ENV{'PERL5OPT'} .= SPACE . $ENV{'LINTIAN_COVERAGE'};
        }
        my $loop = IO::Async::Loop->new;
        my $future = $loop->new_future;

        my @command = ($self->script_path, $pkg_name, $task, $dir);
        $loop->run_child(
            command => [@command],
            on_finish => sub {
                my ($pid, $exitcode, $stdout, $stderr) = @_;
                my $status = ($exitcode >> 8);

                if ($status) {
                    my $message= "Command @command exited with status $status";
                    $message .= ": $stderr" if length $stderr;
                    $future->fail($message);
                    return;
                }

                $future->done($stdout);
            });

        # will raise an exception in case of failure
        $future->get;

    } elsif ($iface eq 'perl-coll') {
        my $cs_path = $self->script_path;
        require $cs_path;
        my $collector = $self->{'collector_class'};
        $collector->can('collect')->($pkg_name, $task, $dir);

    } else {
        internal_error("Unknown interface: $iface");
    }
    return;
}

sub _load_collector {
    my ($self) = @_;
    return unless $self->interface eq 'perl-coll';
    my $cs_path = $self->script_path;
    my $ppkg = $self->name;
    my $collector;

    $ppkg =~ s,[-.],_,go;
    $ppkg =~ s,/,::,go;

    require $cs_path;

    {
        my $candidate = "Lintian::coll::$ppkg";
        $collector = $candidate
          if $candidate->can('collect');
    }
    internal_error($self->name . ' does not have a collect function')
      unless defined $collector;
    $self->{'collector_class'} = $collector;
    return;
}

=back

=head1 AUTHOR

Originally written by Niels Thykier <niels@thykier.net> for Lintian.

=head1 SEE ALSO

lintian(1), Lintian::Profile(3), Lintian::Tag::Info(3)

=cut

1;
__END__

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

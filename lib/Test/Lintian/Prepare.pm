# Copyright © 2018 Felix Lechner
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
# MA 02110-1301, USA

package Test::Lintian::Prepare;

=head1 NAME

Test::Lintian::Prepare -- routines to prepare the work directories

=head1 SYNOPSIS

  use Test::Lintian::Prepare qw(prepare);

=head1 DESCRIPTION

The routines in this module prepare the work directories in which the
tests are run. To do so, they use the specifications in the test set.

=cut

use strict;
use warnings;
use autodie;
use v5.10;

use Exporter qw(import);

BEGIN {
    our @EXPORT_OK = qw(
      prepare_work_directories
      early_logpath
      logged_prepare
      prepare
    );
}

use Capture::Tiny qw(capture_merged);
use Carp;
use Cwd qw(getcwd);
use File::Copy;
use File::Find::Rule;
use File::Path qw(make_path remove_tree);
use File::Spec::Functions qw(abs2rel rel2abs splitpath splitdir catpath);
use File::Copy;
use File::Find::Rule;
use File::stat;
use List::Util qw(max);
use Path::Tiny;
use Try::Tiny;

use Lintian::Command qw(safe_qx);

use Test::Lintian::ConfigFile qw(read_config write_config);
use Test::Lintian::Helper qw(rfc822date copy_dir_contents);
use Test::Lintian::Templates
  qw(copy_skeleton_template_sets remove_surplus_templates fill_skeleton_templates fill_template);

use constant EMPTY => q{};
use constant NEWLINE => qq{\n};
use constant SPACE => q{ };
use constant COMMA => q{,};
use constant DOT => q{.};
use constant COLON => q{:};
use constant LEFT_SQUARE => q{[};
use constant RIGHT_SQUARE => q{]};

my $EARLY_LOG_SUFFIX = 'log';

=head1 FUNCTIONS

=over 4

=item prepare_work_directories(SPEC_PATHS, TEST_SET, OUT_PATH, REBUILD)

Prepares work directories for all tests located in SPEC_PATHS based on
the relative locations of the test set base directory TEST_SET and the
base for work directories OUT_PATH. The optional parameter REBUILD can
force a complete rebuild rather than reusing existing files.

=cut

sub prepare_work_directories {
    my ($specpaths, $testset, $outpath, $force_rebuild) = @_;

    # needed for suite calculation
    my $depth = scalar splitdir((splitpath($testset))[1]);

    my @workpaths;
    foreach my $testpath (@{$specpaths}) {
        # calculate suite from path
        my $suite = (splitdir((splitpath($testpath))[1]))[$depth];

        # calculate the output path for the test
        my $relative = abs2rel($testpath, $testset);
        my $workpath = rel2abs($relative, $outpath);

        # prepare work directory for $testpath
        logged_prepare($testpath, $workpath, $suite, $testset,$force_rebuild);
        push(@workpaths, $workpath);
    }

    return @workpaths;
}

=item early_logpath(RUN_PATH)

Return the path of the early log for the work directory RUN_PATH.

=cut

sub early_logpath {
    my ($runpath)= @_;

    return "$runpath.$EARLY_LOG_SUFFIX";
}

=item logged_prepare(SPEC_PATH, RUN_PATH, $SUITE, TEST_SET, REBUILD)

Prepares the work directory RUN_PATH for the test specified in
SPEC_PATH. The test is assumed to be part of suite SUITE. The optional
parameter REBUILD can force a rebuild if true.

Captures all output and places it in a file near the work directory.
The log can be used as a starting point by the runner after copying
it to a final location.

=cut

sub logged_prepare {
    my ($specpath, $runpath, $suite, $testset, $force_rebuild)= @_;

    my $log;
    my $error;

    # capture output
    $log = capture_merged {

        try {
            # prepare
            prepare($specpath, $runpath, $suite, $testset, $force_rebuild);
        }
        catch {
            # catch any error
            $error = $_;
        };
    };

    # save log;
    if (defined $runpath) {
        my $logfile = early_logpath($runpath);
        path($logfile)->spew_utf8($log) if $log;
    }

    # print something if there was an error
    if ($error) {
        print $log if $log;
        die $error;
    }

    return;
}

sub read_seasoned_config_file {
    my ($path, $data_epoch, $data)= @_;

    unless (-f $path) {
        say "Could not find config file $path.";
        return ($data, $data_epoch);
    }

    $data = read_config($path, $data);
    $data_epoch= max($data_epoch, stat($path)->mtime);

    say "Loaded config file $path.";

    return ($data, $data_epoch);
}

sub transfer_existing_hash_elements {
    my ($source, $destination)= @_;

    foreach my $key (keys %{$destination}) {
        if (exists $source->{$key}) {
            $destination->{$key} = $source->{$key};
            delete $source->{$key};
        }
    }
    return;
}

=item prepare(SPEC_PATH, $RUN_PATH, $SUITE, TEST_SET, REBUILD)

Populates a work directory $RUN_PATH with data from the test located
in SPEC_PATH, which is assumed to belong to suite SUITE.

The optional parameter REBUILD forces a rebuild if true.

=cut

sub prepare {
    my ($specpath, $runpath, $suite, $testset, $force_rebuild)= @_;

    say '------- Preparation starts here -------';
    say "Work directory is $runpath.";

    # for template fill, earliest date without timewarp warning
    my $data_epoch = max($ENV{HARNESS_EPOCH}//time,$ENV{'POLICY_EPOCH'}//time);

    # read defaults
    my $defaultspath = "$testset/defaults";
    my ($files, $constraints, $options, $fill);
    ($files, $data_epoch)
      = read_seasoned_config_file("$defaultspath/files", $data_epoch);

    ($constraints, $data_epoch)
      = read_seasoned_config_file("$defaultspath/$files->{test_constraints}",
        $data_epoch);
    ($options, $data_epoch)
      = read_seasoned_config_file("$defaultspath/$files->{test_options}",
        $data_epoch);
    ($fill, $data_epoch)
      = read_seasoned_config_file("$defaultspath/$files->{template_fill}",
        $data_epoch);

    $options->{test_for} = EMPTY;
    $options->{test_against} = EMPTY;

    # read test data
    my $testcase;
    ($testcase, $data_epoch)
      = read_seasoned_config_file("$specpath/$files->{test_specification}",
        $data_epoch);

    transfer_existing_hash_elements($testcase, $constraints);
    transfer_existing_hash_elements($testcase, $options);

    foreach my $key (keys %{$testcase}) {
        $fill->{$key} = $testcase->{$key};
    }

    undef $testcase;

    # record path to specification
    $options->{spec_path} = $specpath;

    # record suite
    $options->{suite} = $suite;

    # get test name from encapsulating directory
    $fill->{testname} = path($specpath)->basename;

    # require a version
    die 'Test has no version'
      unless exists $fill->{version};

    $fill->{source}    ||= $fill->{testname};

    # record our effective data age, considering policy
    $fill->{date}      ||= rfc822date($data_epoch);

    warn "Cannot override Architecture: in test $fill->{testname}."
      if length $fill->{architecture};

    $fill->{host_architecture} = $ENV{'DEB_HOST_ARCH'}
      //die 'DEB_HOST_ARCH is not set.';

    $fill->{standards_version} ||= $ENV{'POLICY_VERSION'}
      //die 'Could not get POLICY_VERSION.';

    $fill->{dh_compat_level} //= $ENV{'DEFAULT_DEBHELPER_COMPAT'}
      //die 'Could not get DEFAULT_DEBHELPER_COMPAT.';

    # add upstream version
    $fill->{upstream_version} = $fill->{version};
    $fill->{upstream_version} =~ s/-[^-]+$//;
    $fill->{upstream_version} =~ s/(-|^)(\d+):/$1/;

    # version without epoch
    $fill->{no_epoch} = $fill->{version};
    $fill->{no_epoch} =~ s/^\d+://;

    unless ($fill->{prev_version}) {
        $fill->{prev_version} = '0.0.1';
        $fill->{prev_version} .= '-1'
          if index($fill->{version}, '-') > -1;
    }

    die 'Outdated test specification (./debian/debian exists).'
      if -e "$specpath/debian/debian";

    if (-d $runpath) {

        # check for old build artifacts
        my $buildstamp = "$runpath/build-stamp";
        say 'Found old build artifact.' if -f $buildstamp;

        # check for old debian/debian directory
        my $olddebiandir = "$runpath/debian/debian";
        say 'Found old debian/debian directory.' if -e $olddebiandir;

        # check for rebuild demand
        say 'Forcing rebuild.' if $force_rebuild;

        # delete work directory
        if($force_rebuild || -f $buildstamp || -e $olddebiandir) {
            say "Removing work directory $runpath.";
            remove_tree($runpath);
        }
    }

    # create work directory
    unless (-d $runpath) {
        say "Creating directory $runpath.";
        make_path($runpath);
    }

    # load skeleton
    if (exists $options->{skeleton}) {

        # the skeleton we are working with
        my $skeletonname = $options->{skeleton};
        my $skeletonpath = "$testset/skeletons/$suite/$skeletonname";

        my $skeleton = read_config($skeletonpath);

        foreach my $key (keys %{$skeleton}) {
            $fill->{$key} = $skeleton->{$key};
        }
    }

    $constraints->{permutations} = 'one two';

    foreach my $permutation (split(SPACE, $constraints->{permutations})) {

        my $permutationoptions;
        foreach my $key (keys %{$options}) {
            $permutationoptions->{$key} = $options->{$key};
        }

        my $permutationfill;
        foreach my $key (keys %{$fill}) {
            $permutationfill->{$key} = $fill->{$key};
        }

        my $permutationpath = "$runpath/$permutation";
        make_path($permutationpath);


    # populate working directory with specified template sets
    copy_skeleton_template_sets($fill->{template_sets},$runpath, $testset)
      if exists $fill->{template_sets};

    # delete templates for which we have originals
    remove_surplus_templates($specpath, $runpath);

    # copy test specification to working directory
    my $offset = abs2rel($specpath, $testset);
    say "Copy test specification $offset from $testset to $runpath.";
    copy_dir_contents($specpath, $runpath);

    # get builder name
    my $buildername = $options->{builder};
    if (length $buildername) {
        my $builderpath = "$runpath/$buildername";

        # fill builder if needed
        my $buildertemplate = "$builderpath.in";
        fill_template($buildertemplate, $builderpath, $fill, $data_epoch)
          if -f $buildertemplate;

        if (-f $builderpath) {

            # read builder
            my $builder = read_config($builderpath);
            die 'Could not read builder data.' unless $builder;

            # adjust age threshold
            $data_epoch= max($data_epoch, stat($builderpath)->mtime);

            # transfer builder data to test case, but do not override
            foreach my $key (keys %{$builder}) {
                $fill->{$key} = $builder->{$key}
                  unless exists $fill->{$key};
            }

            # delete builder
            unlink($builderpath);
        }
    }

        # calculate build dependencies
        warn 'Cannot override Build-Depends:'
          if length $permutationfill->{build_depends};
        combine_fields($permutationfill, 'build_depends', COMMA . SPACE,
            'default_build_depends', 'extra_build_depends');

        # calculate build conflicts
        warn 'Cannot override Build-Conflicts:'
          if length $permutationfill->{build_conflicts};
        combine_fields($permutationfill, 'build_conflicts', COMMA . SPACE,
            'default_build_conflicts', 'extra_build_conflicts');

        # fill remaining templates
        fill_remaining_templates($skeleton->{try_generate},
            $permutationfill, $data_epoch, $permutationpath, $testset);

    # delete previous test scripts
    my @oldrunners = File::Find::Rule->file->name('*.t')->in($runpath);
    unlink(@oldrunners);

        # copy test script
        my $source = "$testset/runners/$permutationoptions->{runner}";
        my $destination = "$permutationpath/$RUNNER_FILENAME";
        die "Could not install runner: $!"
          if(system('cp', '-p', $source, $destination));
        $permutationoptions->{runner} = $RUNNER_FILENAME;

    # delete original test case specification
    unlink("$runpath/$files->{test_specification}");

            my $runoptions = path($permutationpath)->child($files->{test_options});
        my $runfill = path($permutationpath)->child($files->{template_fill});
        write_config($permutationoptions, $runoptions->stringify);
        write_config($permutationfill, $runfill->stringify);

        $runoptions->touch($data_epoch);
        $runfill->touch($data_epoch);
    }


    # write the dynamic test case files
    my $runfiles = path($runpath)->child('files');
    my $runconstraints = path($runpath)->child($files->{test_constraints});
    my $runoptions = path($runpath)->child($files->{test_options});
    my $runfill = path($runpath)->child($files->{template_fill});
    write_config($files, $runfiles->stringify);
    write_config($constraints, $runconstraints->stringify);
    write_config($options, $runoptions->stringify);
    write_config($fill, $runfill->stringify);

    # set mtime for dynamic test data
    $runfiles->touch($data_epoch);
    $runconstraints->touch($data_epoch);
    $runoptions->touch($data_epoch);
    $runfill->touch($data_epoch);

    return;
}

sub combine_fields {
    my ($testcase, $destination, $delimiter, @sources) = @_;

    return unless length $destination;

    # we are combining these contents
    my @contents;
    foreach my $source (@sources) {
        push(@contents, $testcase->{$source}//EMPTY)
          if length $source;
        delete $testcase->{$source};
    }

    # combine
    foreach my $content (@contents) {
        $testcase->{$destination} = join($delimiter,
            grep { $_ }($testcase->{$destination}//EMPTY,$content));
    }

    # delete the combined entry if it is empty
    delete($testcase->{$destination})
      unless length $testcase->{$destination};

    return;
}

=back

=cut

1;

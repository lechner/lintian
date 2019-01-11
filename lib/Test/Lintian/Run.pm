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

package Test::Lintian::Run;

=head1 NAME

Test::Lintian::Run -- generic runner for all suites

=head1 SYNOPSIS

  use Test::Lintian::Run qw(runner);

  my $runpath = "test working directory";

  runner($runpath);

=head1 DESCRIPTION

Generic test runner for all Lintian test suites

=cut

use strict;
use warnings;
use autodie;
use v5.10;

use Exporter qw(import);

BEGIN {
    our @EXPORT_OK = qw(
      logged_runner
      runner
      check_result
    );
}

use Capture::Tiny qw(capture_merged);
use Cwd qw(getcwd);
use File::Basename qw(basename);
use File::Path qw(make_path);
use File::Spec::Functions qw(abs2rel rel2abs splitpath catpath);
use File::Compare;
use File::Copy;
use File::stat;
use List::Util qw(max min any);
use Path::Tiny;
use Test::More;
use Try::Tiny;

use Lintian::Command qw(safe_qx);

use Test::Lintian::ConfigFile qw(read_config);
use Test::Lintian::Helper qw(rfc822date);
use Test::Lintian::Hooks
  qw(find_missing_prerequisites run_lintian sed_hook sort_lines calibrate);
use Test::Lintian::Prepare qw(early_logpath);
use Test::StagedFileProducer;

use constant SPACE => q{ };
use constant EMPTY => q{};
use constant YES => q{yes};
use constant NO => q{no};

=head1 FUNCTIONS

=over 4

=item logged_runner(RUN_PATH)

Starts the generic test runner for the test located in RUN_PATH
and logs the output.

=cut

sub logged_runner {
    my ($runpath) = @_;

    my $betterlogpath = "$runpath/log";
    my $log;
    my $error;

    $log = capture_merged {
        try {
            # call runner
            runner($runpath, $betterlogpath)

        }
        catch {
            # catch any error
            $error = $_;
        };
    };

    # delete old runner log
    unlink $betterlogpath if -f $betterlogpath;

    # move the early log for directory preparation to position of runner log
    my $earlylogpath = early_logpath($runpath);
    move($earlylogpath, $betterlogpath) if -f $earlylogpath;

    # append runner log to population log
    path($betterlogpath)->append_utf8($log) if length $log;

    # add error if there was one
    path($betterlogpath)->append_utf8($error) if length $error;

    # print log and die on error
    if ($error) {
        print $log if length $log && $ENV{'DUMP_LOGS'}//NO eq YES;
        die "Runner died for $runpath: $error";
    }

    return;
}

=item runner(RUN_PATH)

This routine provides the basic structure for all runners and runs the
test located in RUN_PATH. Different objects are than instantiated
depending on the suite the test case belongs to. Those classes contain
the code that varies from suite to suite.

=cut

sub runner {
    my ($runpath, @exclude)= @_;

    # set a predictable locale
    $ENV{'LC_ALL'} = 'C';

    # many tests create files via debian/rules
    umask(022);

    say EMPTY;
    say '------- Runner starts here -------';

    # bail out if runpath does not exist
    BAIL_OUT("Cannot find test directory $runpath.") unless -d $runpath;

    # announce location
    say "Running test at $runpath.";

    # read dynamic case data
    my $runfiles = "$runpath/files";
    my $files = read_config($runfiles);
    my $optionspath = "$runpath/$files->{test_options}";
    my $constraintspath = "$runpath/$files->{test_constraints}";
    my $fillpath = "$runpath/$files->{template_fill}";

    # read dynamic case data
    my $options = read_config($optionspath);
    my $constraints = read_config($constraintspath);
    my $fill = read_config($fillpath);

    # get data age
    my $spec_epoch = max(
        stat($optionspath)->mtime,
        stat($constraintspath)->mtime,
        stat($fillpath)->mtime
    );

    # name of encapsulating directory should be that of test
    my $expected_name = path($runpath)->basename;
    die
      "Test in $runpath is called $fill->{testname} instead of $expected_name"
      if ($fill->{testname} ne $expected_name);

    # skip test if marked
    my $skipfile = "$runpath/skip";
    if (-f $skipfile) {
        my $reason = path($skipfile)->slurp_utf8 || 'No reason given';
        say "Skipping test: $reason";
        plan skip_all => "(disabled) $reason";
    }

    # skip if missing prerequisites
    my $missing = find_missing_prerequisites($fill);
    if (length $missing) {
        say "Missing prerequisites: $missing";
        plan skip_all => $missing;
    }

    # check test architectures
    unless (length $ENV{'DEB_HOST_ARCH'}) {
        say 'DEB_HOST_ARCH is not set.';
        BAIL_OUT('DEB_HOST_ARCH is not set.');
    }
    my $platforms = $constraints->{test_architectures};
    if ($platforms ne 'any') {
        my @wildcards = split(SPACE, $platforms);
        my @matches= map {
            qx{dpkg-architecture -a $ENV{'DEB_HOST_ARCH'} -i $_; echo -n \$?}
        } @wildcards;
        unless (any { $_ == 0 } @matches) {
            say 'Architecture mismatch';
            plan skip_all => 'Architecture mismatch';
        }
    }

    my @permutations = split(SPACE, $constraints->{permutations});

    unless (scalar @permutations) {
        say 'No permutations to run.';
        plan skip_all => 'No permutations to run.';
    }

    # skip test if marked
    if (exists $constraints->{skip}) {
        my $reason = $constraints->{skip} || 'No reason given';
        say "Skipping test: $reason";
        plan skip_all => "(disabled) $reason";
    }

    # set the testing plan
    plan tests => scalar @permutations;

    foreach my $permutation (@permutations) {

        my $permutationpath = "$runpath/$permutation";

        my $optionspath = "$permutationpath/$files->{test_options}";
        my $fillpath = "$permutationpath/$files->{template_fill}";

        # read dynamic case data
        my $options = read_config($optionspath);
        my $fill = read_config($fillpath);

        # name of encapsulating directory should be that of test
        my $expected_name = path($runpath)->basename;
        die
"Test in $permutationpath is called $fill->{testname} instead of $expected_name"
          if ($fill->{testname} ne $expected_name);

        # executable ages
        my $runner_epoch = $ENV{'RUNNER_EPOCH'}//time;
        my $harness_epoch = $ENV{'HARNESS_EPOCH'}//time;
        my $lintian_epoch = $ENV{'LINTIAN_EPOCH'}//time;

        # get data age
        my $spec_epoch = max(
            stat($runfiles)->mtime,stat($constraintspath)->mtime,
            stat($optionspath)->mtime,stat($fillpath)->mtime
        );

        # announce input time stamps
        say EMPTY;
        say 'Specification is from : '. rfc822date($spec_epoch);
        say 'Runner modified on    : '. rfc822date($runner_epoch);
        say 'Harness modified on   : '. rfc822date($harness_epoch);
        say 'Lintian modified on   : '. rfc822date($lintian_epoch);

        # calculate rebuild threshold
        my $threshold
          = max($spec_epoch, $runner_epoch, $harness_epoch, $lintian_epoch);
        say 'Rebuild threshold is : '. rfc822date($threshold);

      SKIP: {

            # skip if prerequisites missing
            my $missing = find_missing_prerequisites($fill);
            if (length $missing) {
                say "Missing prerequisites: $missing";
                skip $missing;
            }

            my $producer = Test::StagedFileProducer->new(
                path => $permutationpath);
            $producer->exclude(@exclude);

            # get lintian subject
            die 'Could not get subject of Lintian examination.'
              unless exists $fill->{build_product};
            my $subject = "$permutationpath/$fill->{build_product}";

            # build subject for lintian examination
            $producer->add_stage(
                products => [$subject],
                build =>sub {
                    if(exists $fill->{build_command}) {
                        my $command
                          = "cd $permutationpath; $fill->{build_command}";
                        die "$command failed" if system($command);
                    }

                    die 'Build was unsuccessful.' unless -f $subject;

                    # sometimes it's not the oldest; resolution 1 sec
                    say 'Touching '. abs2rel($subject, $permutationpath) . '.';
                    path($subject)->touch(time + 1);
                });

            # run lintian
            my $actual = "$permutationpath/tags.actual";
            $producer->add_stage(
                products => [$actual],
                build =>sub {
                    my $includepath = "$permutationpath/lintian-include-dir";
                    $ENV{'LINTIAN_COVERAGE'}
                      .= ",-db,./cover_db-$fill->{suite}-$fill->{testname}"
                      if exists $ENV{'LINTIAN_COVERAGE'};
                    run_lintian(
                        $permutationpath, $subject,
                        $options->{profile}, $includepath,
                        $options->{options}, $actual
                    );
                });

            # run a sed-script if it exists
            my $parsed = "$permutationpath/tags.actual.parsed";
            $producer->add_stage(
                products => [$parsed],
                build =>sub {
                    my $script = "$permutationpath/post_test";
                    if(-f $script) {
                        sed_hook($script, $actual, $parsed);
                    } else {
                        die"Could not copy actual tags $actual to $parsed: $!"
                          if(system('cp', '-p', $actual, $parsed));
                    }
                });

            # sort tags
            my $sorted = "$permutationpath/tags.actual.parsed.sorted";
            $producer->add_stage(
                products => [$sorted],
                build =>sub {
                    if($options->{sort} eq 'yes') {
                        sort_lines($parsed, $sorted);
                    } else {
                        die"Could not copy parsed tags $parsed to $sorted: $!"
                          if(system('cp', '-p', $parsed, $sorted));
                    }
                });

            my $expected = "$permutationpath/tags";

            # calibrate tags; may write to $sorted
            my $calibrated = "$permutationpath/tags.expected.calibrated";
            $producer->add_stage(
                products => [$calibrated],
                build =>sub {
                    my $script = "$permutationpath/test_calibration";
                    if(-x $script) {
                        calibrate($script,$sorted, $expected, $calibrated);
                    } else {
                        die
"Could not copy expected tags $parsed to $calibrated: $!"
                          if(system('cp', '-p', $expected, $calibrated));
                    }
                });

            say EMPTY;
            $producer->run(threshold => $threshold, verbose => 1);

            my @errors = check_result($options, $sorted, $calibrated, $expected);
            my $okay = !scalar @errors;

            diag @errors;

            if($options->{todo} eq 'yes') {
              TODO: {
                    local $TODO = 'Test marked as TODO.';
                    ok($okay, 'Lintian tags match for test marked TODO.');
                }
                next;
            }

            diag qx{diff -u $calibrated $sorted} unless $okay;
            ok($okay, "Lintian tags match for $fill->{testname}");
        }
    }

    diag safe_qx('diff', '-u', $calibrated, $sorted) unless $okay;
    ok($okay, "Lintian tags match for $fill->{testname}");

    return;
}

=item check_result(DESC, ACTUAL, EXPECTED, ORIGINAL)

This routine checks if the EXPECTED tags match the calibrated ACTUAL for the
test described by DESC. For some additional checks, also need the ORIGINAL
tags before calibration. Returns a list of errors, if there are any.

=cut

sub check_result {
    my ($options, $actual, $expected, $originaltags) = @_;

    # fail if tags do not match
    return 'Tags do not match' if (compare($actual, $expected) != 0);

    # no further investigation on unusual output formats
    return unless $options->{output_format} eq 'EWI';

    # check all Test-For tags were seen and all Test-Against tags were not
    my %test_for = map { $_ => 1 } split SPACE, $options->{test_for}//EMPTY;
    my %test_against =map { $_ => 1 } split SPACE,
      $options->{test_against}//EMPTY;

    return unless (%test_for || %test_against);

    my @errors;

    # look through actual tags
    my @lines = path($actual)->lines_utf8;
    chomp @lines;
    foreach my $line (@lines) {

        # no tag available
        next if $line =~ /^N: /;

        # some traversal tests create packages that are skipped
        next if $line =~ /tainted/ && $line =~ /skipping/;

        # look for "EWI: package[ type]: tag"
        my ($tag) = $line =~ qr/^.: \S+(?: (?:changes|source|udeb))?: (\S+)/o;
        unless (length $tag) {
            push(@errors, "Invalid line: $line");
            next;
        }

        # check if tag was blacklisted
        if ($test_against{$tag}) {

            # warn just once about a tag
            delete $test_against{$tag};
            push(@errors, "Tag $tag seen but listed in Test-Against");
        }

        # mark as seen
        delete $test_for{$tag};
    }

    # check if test was calibrated
    if (defined $originaltags && compare($originaltags, $expected) != 0) {

        # tags lost in calibration; like binaries-hardening on some arches
        my %lost = %test_for;

        # parse original output
        my @origlines = path($originaltags)->lines_utf8;
        chomp @origlines;
        foreach my $line (@origlines) {

            # not tag in this line
            next if $line =~ /^N: /;

            # some traversal tests create packages that are skipped
            next if $line =~ /tainted/ && $line =~ /skipping/;

            # look for "EWI: package[ type]: tag"
            my ($tag)= $line =~ /^.: \S+(?: (?:changes|source|udeb))?: (\S+)/o;
            unless (length $tag) {
                push(@errors, "Invalid line: $line");
                next;
            }
            delete $lost{$tag};
        }

        # remove tags that were calibrated out
        foreach my $tag (keys %lost) {
            delete $test_for{$tag};
        }
    }

    # check if the test missed any tags
    for my $tag (sort keys %test_for) {
        push(@errors, "Tag $tag listed in Test-For but not found");
    }

    return @errors;
}

=back

=cut

1;


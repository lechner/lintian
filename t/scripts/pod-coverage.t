#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
plan skip_all => 'Not needed for coverage of Lintian'
  if $ENV{'LINTIAN_COVERAGE'};
eval 'use Test::Pod::Coverage';
plan skip_all => 'Test::Pod::Coverage is required for testing POD coverage'
  if $@;

# Association of modules to check with additional regexes of private symbols.
# If one is inclined, one can consider the presence of regexes as a TODO to
# add underscores; personally, I (rra) think they make the code hard to read.
our %MODULES =(
    'Lintian::CheckScript'        => [],
    'Lintian::Collect'            => [],
    'Lintian::Collect::Group'     => [],
    'Lintian::Command::Simple'    => [],
    'Lintian::Data'               => [],
    'Lintian::DepMap'             => [],
    'Lintian::DepMap::Properties' => [],
    'Lintian::Lab'                => [],
    'Lintian::Lab::Entry'         => [],
    'Lintian::Profile'            => [],
    'Lintian::Processable'        => [qr/^new$/],
    'Lintian::ProcessableGroup'   => [],
    'Lintian::ProcessablePool'    => [],
    'Lintian::Relation'           =>
      [qr/^parse_element$/,qr/^implies_(element|array)/],
    'Lintian::Relation::Version'  => [qr/^compare$/],
    'Lintian::Tags'               => [],
    'Lintian::Tag::Info'          => [],
    'Lintian::Tag::Override'      => [],
    'Lintian::Util'               => [],
);
# TODO:
#		Lintian::Collect::Binary
#		Lintian::Collect::Source
#		Lintian::Output
#		Lintian::Output::ColonSeparated
#		Lintian::Output::LetterQualifier
#		Lintian::Output::XML

plan tests => scalar keys(%MODULES);

# Ensure the following modules are documented:
for my $module (sort keys %MODULES) {
    pod_coverage_ok(
        $module,
        { also_private => $MODULES{$module} },
        "$module is covered"
    );
}

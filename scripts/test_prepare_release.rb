# frozen_string_literal: true

# Copyright (c) 2026 Chris Coetzee
# SPDX-License-Identifier: MIT
# The full license text is in LICENSE at the repository root.

# Tests for prepare_release.rb. Run with:
#   ruby scripts/test_prepare_release.rb

require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require_relative 'prepare_release'

# Minitest::Test with the `test "does something" do ... end` DSL.
class PrepareReleaseTest < Minitest::Test
  def self.test(name, &block)
    method_name = "test_#{name.gsub(/\W+/, '_')}"
    raise ArgumentError, "test #{name.inspect} is already defined in #{self}" if method_defined?(method_name)

    define_method(method_name, &block)
  end

  SAMPLE_PUBSPEC = <<~YAML
    name: dji_mic_control
    publish_to: 'none'
    version: 0.1.0+1
  YAML

  SAMPLE_CHANGELOG = <<~MD
    # Changelog

    ## [Unreleased]

    ### Added

    - Something awesome.

    ## [0.1.0] - 2026-11-25

    Initial release.

    [Unreleased]: https://github.com/chriscz/dji-mic-control/compare/v0.1.0...HEAD
    [0.1.0]: https://github.com/chriscz/dji-mic-control/releases/tag/v0.1.0
  MD

  test 'bumps pubspec version and increments build number' do
    updated = PrepareRelease.bump_pubspec(SAMPLE_PUBSPEC, '0.2.0')
    assert_includes updated, 'version: 0.2.0+2'
    assert_equal SAMPLE_PUBSPEC, PrepareRelease.bump_pubspec(SAMPLE_PUBSPEC, '0.1.0')
  end

  test 'rolls Unreleased into new version section and updates compare links' do
    rolled = PrepareRelease.roll_changelog(SAMPLE_CHANGELOG, '0.2.0', date_str: '2026-12-01')
    assert_includes rolled, "## [Unreleased]\n\n## [0.2.0] - 2026-12-01"
    assert_includes rolled, '[Unreleased]: https://github.com/chriscz/dji-mic-control/compare/v0.2.0...HEAD'
    assert_includes rolled, '[0.2.0]: https://github.com/chriscz/dji-mic-control/compare/v0.1.0...v0.2.0'
    # Idempotent if version section already exists.
    assert_equal rolled, PrepareRelease.roll_changelog(rolled, '0.2.0', date_str: '2026-12-01')
  end

  test 'extracts release notes for an existing version' do
    notes = PrepareRelease.extract_notes(SAMPLE_CHANGELOG, '0.1.0')
    assert_equal "Initial release.\n", notes
    assert_nil PrepareRelease.extract_notes(SAMPLE_CHANGELOG, '9.9.9')
  end

  test 'CLI supports --help, --dry-run, --version, --check-version, and --extract-notes' do
    out = StringIO.new
    err = StringIO.new
    assert_equal 0, PrepareRelease.run(['--help'], stdout: out, stderr: err)
    assert_includes out.string, '--version'

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'pubspec.yaml'), SAMPLE_PUBSPEC)
      File.write(File.join(dir, 'CHANGELOG.md'), SAMPLE_CHANGELOG)

      # Check mismatch fails, match passes.
      assert_equal 1, PrepareRelease.run(['--root', dir, '--check-version', '0.2.0'], stdout: StringIO.new, stderr: StringIO.new)
      assert_equal 0, PrepareRelease.run(['--root', dir, '--check-version', 'v0.1.0'], stdout: StringIO.new, stderr: StringIO.new)

      # Dry-run leaves disk untouched.
      assert_equal 0, PrepareRelease.run(['--root', dir, '--version', '0.2.0', '--date', '2026-12-01', '--dry-run'],
                                         stdout: StringIO.new, stderr: StringIO.new)
      assert_includes File.read(File.join(dir, 'pubspec.yaml')), 'version: 0.1.0+1'

      # Real prepare updates both files and extracts new notes.
      assert_equal 0, PrepareRelease.run(['--root', dir, '--version', '0.2.0', '--date', '2026-12-01'],
                                         stdout: StringIO.new, stderr: StringIO.new)
      assert_includes File.read(File.join(dir, 'pubspec.yaml')), 'version: 0.2.0+2'

      notes_file = File.join(dir, 'notes.md')
      assert_equal 0, PrepareRelease.run(['--root', dir, '--extract-notes', '0.2.0', '--out', notes_file],
                                         stdout: StringIO.new, stderr: StringIO.new)
      assert_includes File.read(notes_file), 'Something awesome.'
    end
  end
end

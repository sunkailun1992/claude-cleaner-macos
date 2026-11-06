# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require_relative '../lib/claude_cleaner/cli'

class CLITest < Minitest::Test
  class EmptySystem
    def snapshot
      {actions: [], issues: [], processes: []}
    end
    def execute(_action)
      raise 'no system mutations expected'
    end
  end
  class EmptyAuditor
    def findings
      []
    end
  end

  def setup
    @home = File.realpath(Dir.mktmpdir('cleaner cli '))
    @out = StringIO.new
    @input = StringIO.new
    @cli = ClaudeCleaner::CLI.new(home: @home, app_roots: [], prefixes: [], runtime_roots: [],
                                  system: EmptySystem.new, auditor: EmptyAuditor.new, uid: 501, platform: 'darwin',
                                  out: @out, input: @input, env: {})
    FileUtils.mkdir_p(File.join(@home, '.claude'))
    File.write(File.join(@home, '.claude/history.jsonl'), 'fixture')
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def test_default_preview_does_not_change_files
    assert_equal 0, @cli.run([])
    assert File.exist?(File.join(@home, '.claude/history.jsonl'))
    assert_includes @out.string, 'preview'
  end

  def test_yes_without_apply_is_rejected
    assert_equal 2, @cli.run(['--yes'])
    assert File.exist?(File.join(@home, '.claude/history.jsonl'))
  end

  def test_apply_yes_deletes_then_independently_verifies
    assert_equal 0, @cli.run(['--apply', '--yes', '--json'])
    refute File.exist?(File.join(@home, '.claude/history.jsonl'))
    report = JSON.parse(@out.string)
    assert_equal 'known_scope_clean', report['status']
    assert_empty report['remaining']['paths']
  end

  def test_apply_without_confirmation_is_noop
    assert_equal 2, @cli.run(['--apply'])
    assert File.exist?(File.join(@home, '.claude/history.jsonl'))
  end

  def test_verify_reports_residuals_with_nonzero_exit
    assert_equal 1, @cli.run(['--verify', '--json'])
    assert_equal 'remaining', JSON.parse(@out.string)['status']
  end

  def test_dangerous_custom_directory_prevents_all_deletion
    assert_equal 2, @cli.run(['--apply', '--yes', '--config-dir', @home])
    assert File.exist?(File.join(@home, '.claude/history.jsonl'))
  end

  def test_unsupported_platform_never_mutates
    cli = ClaudeCleaner::CLI.new(home: @home, app_roots: [], prefixes: [], runtime_roots: [],
                                system: EmptySystem.new, auditor: EmptyAuditor.new, uid: 501, platform: 'linux',
                                out: @out, input: @input, env: {})
    assert_equal 2, cli.run(['--apply', '--yes'])
    assert File.exist?(File.join(@home, '.claude/history.jsonl'))
  end

  def test_manual_browser_residuals_do_not_prevent_core_cleanup_but_fail_deep_verification
    auditor = Object.new
    def auditor.findings
      [{path: '/fixture/browser/extension', reason: 'manual uninstall required'}]
    end
    cli = ClaudeCleaner::CLI.new(home: @home, app_roots: [], prefixes: [], runtime_roots: [],
                                system: EmptySystem.new, auditor: auditor, uid: 501, platform: 'darwin',
                                out: @out, input: @input, env: {})
    assert_equal 1, cli.run(['--apply', '--yes', '--json'])
    refute File.exist?(File.join(@home, '.claude/history.jsonl'))
    report = JSON.parse(@out.string)
    assert_equal 'incomplete', report['status']
    assert_equal 1, report['remaining']['manual'].length
  end

  def test_runtime_discovery_failure_prevents_a_clean_verification
    runner = Object.new
    def runner.call(_argv)
      {status: 124, stdout: '', stderr: 'timeout'}
    end
    FileUtils.remove_entry(File.join(@home, '.claude'))
    cli = ClaudeCleaner::CLI.new(home: @home, app_roots: [], prefixes: [],
                                system: EmptySystem.new, auditor: EmptyAuditor.new,
                                runtime_runner: runner, uid: 501, platform: 'darwin',
                                out: @out, input: @input, env: {})
    assert_equal 1, cli.run(['--verify', '--json'])
    report = JSON.parse(@out.string)
    assert report['remaining']['issues'].any? { |issue| issue.include?('DARWIN_USER_CACHE_DIR') }
    assert_equal 'remaining', report['status']
  end
end

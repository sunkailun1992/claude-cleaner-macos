# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require_relative '../lib/claude_cleaner/cli'

class BrowserCLITest < Minitest::Test
  class SystemFixture
    attr_reader :probes
    def initialize(restart_at: nil, issue: nil)
      @restart_at, @issue, @probes = restart_at, issue, 0
    end
    def snapshot
      {actions: [], issues: [], processes: []}
    end
    def execute(_action)
      raise 'no real system actions'
    end
    def browser_processes
      @probes += 1
      running = @restart_at && @probes >= @restart_at
      {processes: running ? [{pid: 123, executable: 'fixture/Google Chrome.app/Contents/MacOS/Google Chrome', kind: 'browser'}] : [],
       issues: @issue ? [@issue] : []}
    end
  end

  def setup
    @home = File.realpath(Dir.mktmpdir('browser cli '))
    @profile = File.join(@home, 'Library/Application Support/Google/Chrome/Default')
    @site = directory('IndexedDB/https_claude.ai_0.indexeddb.leveldb')
    File.write(File.join(@site, 'fixture.log'), 'synthetic Claude fixture')
    @other = directory('IndexedDB/https_example.com_0.indexeddb.leveldb')
    File.write(File.join(@other, 'fixture.log'), 'other website')
    FileUtils.mkdir_p(File.join(@home, '.claude'))
    File.write(File.join(@home, '.claude/history.jsonl'), 'synthetic history')
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def directory(relative)
    path = File.join(@profile, relative)
    FileUtils.mkdir_p(path)
    path
  end

  def run_cli(args, system = SystemFixture.new)
    output = StringIO.new
    auditor = ClaudeCleaner::Auditor.new(home: @home, system_roots: [], runtime_tmp: '')
    cli = ClaudeCleaner::CLI.new(home: @home, app_roots: [], prefixes: [], runtime_roots: [],
                                system: system, auditor: auditor, uid: Process.uid,
                                platform: 'darwin', out: output, input: StringIO.new, env: {})
    code = cli.run(args + ['--json'])
    [code, output.string.start_with?('{') ? JSON.parse(output.string) : { 'parse_error' => output.string }]
  end

  def test_default_apply_preserves_site_data_and_keeps_manual_finding
    system = SystemFixture.new
    code, report = run_cli(['--apply', '--yes'], system)
    assert_equal 1, code
    assert File.directory?(@site)
    assert report.fetch('remaining').fetch('manual').any? { |m| m['path'] == @site }
    assert_equal 0, system.probes
  end

  def test_explicit_preview_lists_leveldb_and_blob_without_touching_other_sites
    blob = directory('IndexedDB/https_claude.ai_0.indexeddb.blob')
    code, report = run_cli(['--include-browser-site-data'])
    assert_equal 0, code
    paths = report.fetch('plan').fetch('paths').map { |t| t['path'] }
    assert_includes paths, @site
    assert_includes paths, blob
    refute_includes paths, @other
    assert File.exist?(File.join(@site, 'fixture.log'))
  end

  def test_apply_deletes_exact_origin_storage_and_preserves_shared_databases
    File.write(File.join(@profile, 'Cookies'), 'shared cookies fixture')
    File.write(File.join(@profile, 'History'), 'shared history fixture')
    code, report = run_cli(['--include-browser-site-data', '--apply', '--yes'])
    assert_equal 0, code
    assert_equal 'known_scope_clean', report['status']
    refute File.exist?(@site)
    assert_equal 'other website', File.read(File.join(@other, 'fixture.log'))
    assert_equal 'shared cookies fixture', File.read(File.join(@profile, 'Cookies'))
    assert_equal 'shared history fixture', File.read(File.join(@profile, 'History'))
    assert_equal 0, run_cli(['--include-browser-site-data', '--verify']).first
  end

  def test_running_browser_blocks_every_delete
    code, report = run_cli(['--include-browser-site-data', '--apply', '--yes'], SystemFixture.new(restart_at: 1))
    assert_equal 1, code
    assert_equal 'blocked', report['status']
    assert File.directory?(@site)
    assert File.exist?(File.join(@home, '.claude/history.jsonl'))
  end

  def test_browser_restart_before_deletion_blocks_every_delete
    code, report = run_cli(['--include-browser-site-data', '--apply', '--yes'], SystemFixture.new(restart_at: 3))
    assert_equal 1, code
    assert_equal 'blocked', report['status']
    assert File.directory?(@site)
    assert File.exist?(File.join(@home, '.claude/history.jsonl'))
  end

  def test_browser_restart_at_target_guard_preserves_the_site
    code, report = run_cli(['--include-browser-site-data', '--apply', '--yes'], SystemFixture.new(restart_at: 4))
    assert_equal 1, code
    assert_equal 'incomplete', report['status']
    assert File.directory?(@site)
    assert report.fetch('results').any? { |result| result['status'] == 'failed' }
  end

  def test_browser_probe_failure_blocks_cleanup
    code, report = run_cli(['--include-browser-site-data', '--apply', '--yes'], SystemFixture.new(issue: 'browser probe failed'))
    assert_equal 1, code
    assert_equal 'blocked', report['status']
    assert File.directory?(@site)
  end

  def test_browser_running_prevents_clean_verify_even_when_no_site_target_remains
    FileUtils.remove_entry(@site)
    FileUtils.remove_entry(File.join(@home, '.claude'))
    code, report = run_cli(['--include-browser-site-data', '--verify'], SystemFixture.new(restart_at: 1))
    assert_equal 1, code
    assert_equal 'remaining', report['status']
  end

  def test_extension_manual_finding_is_not_hidden_by_the_site_option
    extension = directory('Extensions/' + ClaudeCleaner::Auditor::EXTENSION_ID)
    code, report = run_cli(['--include-browser-site-data', '--apply', '--yes'])
    assert_equal 1, code
    refute File.exist?(@site)
    assert report.fetch('remaining').fetch('manual').any? { |finding| finding['path'] == extension }
  end
end

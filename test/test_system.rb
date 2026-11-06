# frozen_string_literal: true
require 'minitest/autorun'
require 'timeout'
require_relative '../lib/claude_cleaner/system'

class SystemTest < Minitest::Test
  class FakeRunner
    attr_reader :calls
    def initialize(replies = {})
      @replies, @calls = replies, []
    end
    def call(argv)
      @calls << argv
      @replies.fetch(argv, { status: 0, stdout: '', stderr: '' })
    end
  end

  def test_keychain_services_are_exact_and_never_read_passwords
    dump = <<~TEXT
      "svce"<blob>="Claude Safe Storage"
      "svce"<blob>="Claude Code-credentials-ab12cd34"
      "svce"<blob>="Claude Code-credentials-not-a-hash"
      "svce"<blob>="Claude Code MCP shared"
      "svce"<blob>="Other Safe Storage"
    TEXT
    runner = FakeRunner.new(['/usr/bin/security', 'dump-keychain'] => { status: 0, stdout: dump, stderr: '' })
    system = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: [])
    plan = system.snapshot
    names = plan[:actions].select { |a| a[:category] == 'keychain' }.map { |a| a[:argv].last }
    assert_equal ['Claude Safe Storage', 'Claude Code-credentials-ab12cd34'], names
    refute runner.calls.flatten.include?('-w')
    refute runner.calls.flatten.include?('-g')
    refute runner.calls.flatten.include?('-d')
  end

  def test_only_installed_official_packages_are_uninstalled_without_zap
    brew, npm = '/fake/brew', '/fake/npm'
    runner = FakeRunner.new(
      [brew, 'list', '--cask', '--versions'] => {status: 0, stdout: "claude 1.0\nother-claude 2.0\nclaude-code 3.0\n", stderr: ''},
      [npm, 'prefix', '--global'] => {status: 0, stdout: '/fixture/prefix', stderr: ''},
      [npm, 'list', '--global', '--prefix', '/fixture/prefix', '--depth=0', '--json'] => {status: 0, stdout: '{"dependencies":{"@anthropic-ai/claude-code":{"version":"1"},"other-claude":{}}}', stderr: ''}
    )
    system = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [brew], npm_paths: [npm])
    actions = system.snapshot[:actions]
    assert actions.any? { |a| a[:argv] == [brew, 'uninstall', '--cask', '--force', 'claude'] }
    assert actions.any? { |a| a[:argv] == [npm, 'uninstall', '--global', '--prefix', '/fixture/prefix', '--ignore-scripts', '--no-audit', '--no-fund', '@anthropic-ai/claude-code'] }
    refute actions.flat_map { |a| a[:argv] }.include?('--zap')
    refute actions.flat_map { |a| a[:argv] }.include?('other-claude')
  end

  def test_locked_keychain_is_a_scan_issue
    runner = FakeRunner.new(['/usr/bin/security', 'dump-keychain'] => {status: 1, stdout: '', stderr: 'locked'})
    plan = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: []).snapshot
    assert plan[:issues].any? { |issue| issue.include?('keychain') }
  end

  def test_running_process_matching_uses_executable_paths_not_mentions
    output = "123 501 /Applications/Claude.app/Contents/MacOS/Claude\n124 501 /usr/bin/ruby\n125 502 /Applications/Claude.app/Contents/MacOS/Claude\n126 501 /fake/home/.local/share/claude/versions/2.0\n"
    runner = FakeRunner.new(['/bin/ps', '-ww', '-axo', 'pid=,uid=,comm='] => {status: 0, stdout: output, stderr: ''})
    plan = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: []).snapshot
    assert_equal [123, 126], plan[:processes].map { |p| p[:pid] }
  end

  def test_failed_action_returns_failure_without_dumping_private_output
    argv = ['/usr/bin/security', 'delete-generic-password', '-s', 'Claude Safe Storage']
    runner = FakeRunner.new(argv => {status: 1, stdout: 'private-data', stderr: 'private-error'})
    system = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: [])
    result = system.execute(category: 'keychain', argv: argv, reason: 'test')
    assert_equal 'failed', result[:status]
    refute_includes result.to_s, 'private-data'
    refute_includes result.to_s, 'private-error'
  end

  def test_command_runner_passes_arguments_without_shell_expansion
    runner = ClaudeCleaner::CommandRunner.new(timeout: 5)
    result = runner.call(['/usr/bin/printf', '%s', '$(touch NEVER_CREATE)'])
    assert_equal 0, result[:status]
    assert_equal '$(touch NEVER_CREATE)', result[:stdout]
  end

  def test_command_timeout_also_bounds_inherited_output_pipes
    runner = ClaudeCleaner::CommandRunner.new(timeout: 0.15)
    # The parent exits normally; its child keeps the output pipe open and
    # ignores TERM. Only a deadline for both process and pipe completion works.
    script = "fork { trap('TERM', 'IGNORE'); sleep 2 }; exit! 0"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Timeout.timeout(4) { runner.call([RbConfig.ruby, '-e', script]) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_equal 124, result[:status]
    assert_operator elapsed, :<, 1.5
  end

  def test_node_cli_is_detected_without_recording_its_arguments
    command = '/usr/local/bin/node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js --secret DO_NOT_LOG'
    runner = FakeRunner.new(
      ['/bin/ps', '-ww', '-axo', 'pid=,uid=,args='] => {status: 0, stdout: "200 501 #{command}\n201 501 /usr/bin/printf claude\n", stderr: ''}
    )
    plan = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: []).snapshot
    assert_equal [200], plan[:processes].map { |p| p[:pid] }
    refute_includes plan[:processes].to_s, 'DO_NOT_LOG'
  end

  def test_running_switcher_blocks_cleanup_even_on_desktop
    output = "220 501 /fixture/home/Desktop/Claude切换器.app/Contents/MacOS/ClaudeSwitcher\n"
    runner = FakeRunner.new(['/bin/ps', '-ww', '-axo', 'pid=,uid=,comm='] => {status: 0, stdout: output, stderr: ''})
    plan = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: []).snapshot
    assert_equal [220], plan[:processes].map { |p| p[:pid] }
  end

  def test_running_native_homebrew_cask_is_detected_at_resolved_path
    output = "230 501 /opt/homebrew/Caskroom/claude-code/2.1.0/claude\n231 501 /usr/local/Caskroom/claude-code@latest/2.1.0/claude\n"
    runner = FakeRunner.new(['/bin/ps', '-ww', '-axo', 'pid=,uid=,comm='] => {status: 0, stdout: output, stderr: ''})
    plan = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: []).snapshot
    assert_equal [230, 231], plan[:processes].map { |p| p[:pid] }
  end

  def test_browser_guard_detects_supported_app_helpers_and_current_user_only
    output = <<~TEXT
      300 501 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      301 501 /Applications/Google Chrome.app/Contents/Frameworks/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper
      302 501 /Applications/Microsoft Edge Beta.app/Contents/MacOS/Microsoft Edge Beta
      303 501 /Applications/Brave Browser.app/Contents/Helpers/helper
      304 501 /Applications/Arc.app/Contents/MacOS/Arc
      305 501 /Applications/Vivaldi.app/Contents/MacOS/Vivaldi
      306 501 /Applications/Opera.app/Contents/MacOS/Opera
      307 501 /Applications/Chromium.app/Contents/MacOS/Chromium
      308 502 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      309 501 /Applications/My Chrome Notes.app/Contents/MacOS/Notes
    TEXT
    runner = FakeRunner.new(['/bin/ps', '-ww', '-axo', 'pid=,uid=,comm='] => {status: 0, stdout: output, stderr: ''})
    result = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: []).browser_processes
    assert_equal (300..307).to_a, result[:processes].map { |p| p[:pid] }
    assert_empty result[:issues]
  end

  def test_browser_process_probe_failure_is_not_an_empty_clean_result
    runner = FakeRunner.new(['/bin/ps', '-ww', '-axo', 'pid=,uid=,comm='] => {status: 1, stdout: '', stderr: 'failed'})
    result = ClaudeCleaner::MacSystem.new(home: '/fake/home', uid: 501, runner: runner, brew_paths: [], npm_paths: []).browser_processes
    refute_empty result[:issues]
  end
end

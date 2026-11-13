# frozen_string_literal: true
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class LauncherTest < Minitest::Test
  LAUNCHER = File.expand_path('../claude-cleaner', __dir__)

  def setup
    skip "the launcher runs Apple's system Ruby and exists only on macOS" unless RUBY_PLATFORM.include?('darwin')
    # RUBYOPT splits on spaces, so the probe lives in a directory without any.
    @dir = Dir.mktmpdir('probe')
    @probe = File.join(@dir, 'probe.rb')
    File.write(@probe, '$stderr.print "external=#{Encoding.default_external};lc_all=#{ENV["LC_ALL"].inspect};"')
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir
  end

  # Only --version runs: it exits before any inventory, deletion or system action.
  def launch(env)
    Open3.capture3({ 'PATH' => '/usr/bin:/bin', 'RUBYOPT' => "-r#{@probe}" }.merge(env),
                   LAUNCHER, '--version', unsetenv_others: true)
  end

  def test_the_launcher_gives_ruby_a_utf8_locale_when_the_shell_has_none
    out, err, status = launch({})
    assert status.success?, err
    assert_includes err, 'external=UTF-8;'
    assert_match(/\A\d+\.\d+\.\d+/, out)
  end

  def test_the_launcher_replaces_a_utf8_locale_that_macos_does_not_have
    _out, err, status = launch('LANG' => 'zh_SG.UTF-8')
    assert status.success?, err
    assert_includes err, 'external=UTF-8;'
  end

  def test_the_launcher_keeps_a_working_utf8_locale_of_the_user
    _out, err, status = launch('LANG' => 'zh_CN.UTF-8')
    assert status.success?, err
    assert_includes err, 'external=UTF-8;lc_all=nil;'
  end
end

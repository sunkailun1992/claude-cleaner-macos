# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/claude_cleaner/auditor'

class AuditorTest < Minitest::Test
  EXTENSION_ID = 'fcoeoabgfenejglbffodgkkbkcdhcgfn'

  def setup
    @temporary = File.realpath(Dir.mktmpdir('claude audit '))
    @home = File.join(@temporary, 'home')
    @system_root = File.join(@temporary, 'Library')
    FileUtils.mkdir_p([@home, @system_root])
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary && File.exist?(@temporary)
  end

  def test_empty_fixture_has_no_findings
    assert_empty auditor.findings
  end

  def test_detects_exact_extension_directories_in_every_profile
    expected = []
    ['Default', 'Profile 2 中文 空格'].each do |profile|
      ['Extensions', 'Local Extension Settings', 'Sync Extension Settings'].each do |storage|
        expected << directory(File.join(chrome, profile, storage, EXTENSION_ID))
      end
      expected << directory(File.join(chrome, profile, 'IndexedDB',
                                      "chrome-extension_#{EXTENSION_ID}_0.indexeddb.leveldb"))
    end
    other = directory(File.join(chrome, 'Default', 'Extensions', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'))
    directory(File.join(chrome, 'Default', 'Extensions', EXTENSION_ID + '-other'))

    assert_equal expected.sort, auditor.findings.map { |item| item[:path] }.sort
    assert File.directory?(other)
    expected.each { |path| assert File.directory?(path) }
  end

  def test_detects_exact_claude_site_indexeddb_directories
    expected = %w[https_claude.ai_0.indexeddb.leveldb
                  https_console.anthropic.com_0.indexeddb.leveldb
                  https_platform.claude.com_0.indexeddb.leveldb].map do |name|
      directory(File.join(chrome, 'Default', 'IndexedDB', name))
    end
    directory(File.join(chrome, 'Default', 'IndexedDB', 'https_claude.ai.example.com_0.indexeddb.leveldb'))
    directory(File.join(chrome, 'Default', 'IndexedDB', 'https_anthropic.com_0.indexeddb.leveldb'))

    findings = auditor.findings

    assert_equal expected.sort, findings.map { |item| item[:path] }.sort
    assert findings.all? { |item| item[:reason].match?(/browser|site/i) }
  end

  def test_checks_other_chromium_browsers
    expected = ['Microsoft Edge', 'BraveSoftware/Brave-Browser', 'Arc/User Data',
                'Vivaldi', 'Chromium', 'Google/ChromeForTesting'].map do |browser|
      directory(File.join(@home, 'Library/Application Support', browser, 'Default',
                          'Extensions', EXTENSION_ID))
    end

    assert_equal expected.sort, auditor.findings.map { |item| item[:path] }.sort
  end

  def test_checks_opera_storage_at_the_browser_root
    path = directory(File.join(@home, 'Library/Application Support/com.operasoftware.Opera',
                               'Extensions', EXTENSION_ID))

    assert_includes auditor.findings.map { |item| item[:path] }, path
  end

  def test_shared_cookie_database_existence_does_not_claim_claude_residue
    root = File.join(chrome, 'Default')
    write(File.join(root, 'Cookies'), 'unrelated cookie fixture')
    write(File.join(root, 'Network/Cookies'), 'another unrelated cookie fixture')
    write(File.join(root, 'History'), 'unrelated history')

    assert_empty auditor.findings
  end

  def test_normal_chromium_singleton_links_are_not_profiles_or_claude_findings
    directory(chrome)
    %w[SingletonCookie SingletonLock SingletonSocket].each do |name|
      File.symlink(File.join(@temporary, 'unrelated-browser-runtime', name), File.join(chrome, name))
    end

    assert_empty auditor.findings
  end

  def test_custom_profile_with_preferences_metadata_is_audited
    profile = File.join(chrome, '自定义 用户资料')
    write(File.join(profile, 'Preferences'), 'do not read preferences')
    path = directory(File.join(profile, 'Extensions', EXTENSION_ID))

    assert_includes auditor.findings.map { |item| item[:path] }, path
  end

  def test_shared_browser_component_storage_is_not_confused_with_a_profile
    directory(File.join(chrome, 'component_crx_cache', 'Extensions', EXTENSION_ID))

    assert_empty auditor.findings
  end

  def test_browser_parent_symlink_is_reported_without_traversal
    outside = directory(File.join(@temporary, 'outside'))
    sentinel = directory(File.join(outside, 'Google/Chrome/Default/Extensions', EXTENSION_ID))
    directory(File.join(@home, 'Library'))
    linked = File.join(@home, 'Library/Application Support')
    File.symlink(outside, linked)
    original_children = Dir.method(:children)
    guarded_children = proc do |path|
      flunk('must not list through a symlink parent') if path.start_with?(linked + '/') || path == linked
      original_children.call(path)
    end

    findings = Dir.stub(:children, guarded_children) { auditor.findings }

    assert_equal [linked], findings.map { |item| item[:path] }
    assert_match(/cannot|unable|symlink/i, findings.first[:reason])
    assert File.directory?(sentinel)
  end

  def test_symlink_profile_is_reported_without_traversal
    outside = directory(File.join(@temporary, 'outside'))
    sentinel = directory(File.join(outside, 'Extensions', EXTENSION_ID))
    directory(chrome)
    link = File.join(chrome, 'Profile 1')
    File.symlink(outside, link)
    original_children = Dir.method(:children)
    guarded_children = proc do |path|
      flunk('must not list a symlink profile') if path == link || path.start_with?(link + '/')
      original_children.call(path)
    end

    findings = Dir.stub(:children, guarded_children) { auditor.findings }

    assert_equal [link], findings.map { |item| item[:path] }
    assert_match(/cannot|unable|symlink/i, findings.first[:reason])
    assert File.directory?(sentinel)
  end

  def test_leaf_extension_symlink_is_a_finding_without_following_it
    directory(File.join(chrome, 'Default/Extensions'))
    outside = write(File.join(@temporary, 'outside-secret'), 'do not read')
    link = File.join(chrome, 'Default/Extensions', EXTENSION_ID)
    File.symlink(outside, link)

    assert_includes auditor.findings.map { |item| item[:path] }, link
    assert File.symlink?(link)
  end

  def test_reports_listing_failures_instead_of_silently_returning_empty
    directory(chrome)
    original_children = Dir.method(:children)
    inaccessible = proc do |path|
      raise Errno::EACCES, path if path == chrome
      original_children.call(path)
    end

    findings = Dir.stub(:children, inaccessible) { auditor.findings }

    assert_includes findings.map { |item| item[:path] }, chrome
    assert findings.any? { |item| item[:reason].match?(/cannot|unable|denied/i) }
  end

  def test_detects_exact_mdm_configuration_and_switcher_daemons
    expected = ['Application Support/ClaudeCode/managed-settings.json',
                'Application Support/ClaudeCode/managed-settings.d',
                'Application Support/ClaudeCode/managed-mcp.json',
                'LaunchDaemons/local.claude-bodyguard.plist',
                'LaunchDaemons/local.tz-watchdog.plist',
                'LaunchDaemons/local.claude-update.plist'].map do |relative|
      if relative.end_with?('.d')
        directory(File.join(@system_root, relative))
      else
        write(File.join(@system_root, relative), 'metadata only')
      end
    end
    unrelated = write(File.join(@system_root, 'LaunchDaemons/com.example.other.plist'), 'keep')

    findings = auditor.findings

    assert_equal expected.sort, findings.map { |item| item[:path] }.sort
    assert findings.all? { |item| item[:reason].match?(/administrator|managed|system/i) }
    assert File.exist?(unrelated)
  end

  def test_detects_system_chrome_native_hosts_at_official_exact_locations
    hosts = %w[com.anthropic.claude_browser_extension.json
               com.anthropic.claude_code_browser_extension.json]
    expected = ['Google/Chrome/NativeMessagingHosts',
                'Google/ChromeForTesting/NativeMessagingHosts',
                'Application Support/Chromium/NativeMessagingHosts'].flat_map do |relative|
      hosts.map { |host| write(File.join(@system_root, relative, host), 'metadata only') }
    end
    write(File.join(@system_root, 'Google/Chrome/NativeMessagingHosts/com.anthropic.other.json'), 'keep')
    write(File.join(@system_root, 'Application Support/Google/Chrome/NativeMessagingHosts', hosts.first), 'wrong path')

    assert_equal expected.sort, auditor.findings.map { |item| item[:path] }.sort
  end

  def test_orphaned_system_switcher_scripts_are_reported_without_a_daemon
    path = directory(File.join(@system_root, 'Application Support/claude-switcher'))
    assert_equal [path], auditor.findings.map { |item| item[:path] }
    assert File.directory?(path)
  end

  def test_reports_blocked_system_parent_without_inspecting_outside
    outside = directory(File.join(@temporary, 'outside'))
    directory(File.join(outside, 'ClaudeCode'))
    write(File.join(outside, 'ClaudeCode/managed-settings.json'), 'do not read')
    linked = File.join(@system_root, 'Application Support')
    File.symlink(outside, linked)

    findings = auditor.findings

    assert_equal [linked], findings.map { |item| item[:path] }
    assert_match(/cannot|unable|symlink/i, findings.first[:reason])
  end

  def test_existing_custom_tmp_is_reported_without_enumerating_contents
    runtime = directory(File.join(@temporary, 'custom tmp 中文'))
    write(File.join(runtime, 'unrelated'), 'keep')
    original_children = Dir.method(:children)
    guarded_children = proc do |path|
      flunk('custom tmp must not be scanned recursively') if path == runtime
      original_children.call(path)
    end

    findings = Dir.stub(:children, guarded_children) { auditor(runtime_tmp: runtime).findings }

    assert_equal [runtime], findings.map { |item| item[:path] }
    assert_match(/custom|temporary|manual/i, findings.first[:reason])
    assert File.exist?(File.join(runtime, 'unrelated'))
  end

  def test_nonexistent_custom_tmp_is_not_reported_as_residue
    assert_empty auditor(runtime_tmp: File.join(@temporary, 'missing')).findings
  end

  def test_default_custom_tmp_comes_from_environment
    runtime = directory(File.join(@temporary, 'environment tmp'))
    original = ENV['CLAUDE_CODE_TMPDIR']
    ENV['CLAUDE_CODE_TMPDIR'] = runtime

    findings = ClaudeCleaner::Auditor.new(home: @home, system_roots: [@system_root]).findings

    assert_equal [runtime], findings.map { |item| item[:path] }
  ensure
    original.nil? ? ENV.delete('CLAUDE_CODE_TMPDIR') : ENV['CLAUDE_CODE_TMPDIR'] = original
  end

  def test_findings_are_fresh_when_called_again
    checker = auditor
    assert_empty checker.findings
    path = directory(File.join(chrome, 'Default', 'Extensions', EXTENSION_ID))

    assert_includes checker.findings.map { |item| item[:path] }, path
  end

  def test_audit_never_reads_contents_or_mutates_files
    extension = directory(File.join(chrome, 'Default', 'Extensions', EXTENSION_ID))
    write(File.join(extension, 'manifest.json'), 'secret browser fixture')
    managed = write(File.join(@system_root, 'Application Support/ClaudeCode/managed-settings.json'), 'secret MDM fixture')
    forbidden = proc { |*_args| flunk('auditor must use metadata only') }

    findings = File.stub(:read, forbidden) do
      File.stub(:binread, forbidden) do
        File.stub(:open, forbidden) do
          File.stub(:write, forbidden) do
            File.stub(:unlink, forbidden) do
              Dir.stub(:rmdir, forbidden) { auditor.findings }
            end
          end
        end
      end
    end

    assert_equal [extension, managed].sort, findings.map { |item| item[:path] }.sort
    assert File.directory?(extension)
    assert File.file?(managed)
  end

  private

  def chrome
    File.join(@home, 'Library/Application Support/Google/Chrome')
  end

  def auditor(runtime_tmp: '')
    ClaudeCleaner::Auditor.new(home: @home, system_roots: [@system_root], runtime_tmp: runtime_tmp)
  end

  def directory(path)
    FileUtils.mkdir_p(path)
    path
  end

  def write(path, contents)
    directory(File.dirname(path))
    File.write(path, contents)
    path
  end
end

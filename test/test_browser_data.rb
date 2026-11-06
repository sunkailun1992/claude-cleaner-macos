# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/claude_cleaner/auditor'
require_relative '../lib/claude_cleaner/browser_data'

class BrowserDataTest < Minitest::Test
  ORIGINS = %w[https_claude.ai_0 https_console.anthropic.com_0 https_platform.claude.com_0].freeze

  def setup
    @temporary = File.realpath(Dir.mktmpdir('claude browser data '))
    @home = File.join(@temporary, 'home')
    FileUtils.mkdir_p(@home)
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary && File.exist?(@temporary)
  end

  def test_only_exact_website_origin_leveldb_and_blob_directories_are_targets
    expected = ORIGINS.flat_map do |origin|
      %w[leveldb blob].map { |kind| directory(site_path("#{origin}.indexeddb.#{kind}")) }
    end
    keep = %w[
      https_claude.ai.example.com_0.indexeddb.leveldb
      https_claude.ai_443.indexeddb.leveldb
      http_claude.ai_0.indexeddb.leveldb
      https_anthropic.com_0.indexeddb.leveldb
      https_console.anthropic.com.evil_0.indexeddb.blob
      https_platform.claude.com_0.indexeddb.blob-backup
      chrome-extension_fcoeoabgfenejglbffodgkkbkcdhcgfn_0.indexeddb.leveldb
    ].map { |name| directory(site_path(name)) }
    %w[Cookies History Local\ Storage Extensions].each do |name|
      keep << directory(File.join(profile, name))
    end

    plan = browser_data

    assert_equal expected.sort, plan.targets.map(&:path)
    assert_equal ['chrome'], plan.families
    assert_empty plan.issues
    keep.each { |path| assert File.directory?(path) }
    expected.each do |path|
      target = plan.targets.find { |entry| entry.path == path }
      stat = File.lstat(path)
      assert_instance_of ClaudeCleaner::Target, target
      assert_equal [stat.dev, stat.ino, stat.ftype], target.identity
      refute_empty target.reason
    end
  end

  def test_empty_or_unrelated_browser_roots_do_not_add_a_family
    directory(browser_root)
    directory(File.join(browser_root, 'ShaderCache'))
    directory(File.join(profile, 'IndexedDB', 'https_other.example_0.indexeddb.leveldb'))

    plan = browser_data

    assert_empty plan.targets
    assert_empty plan.issues
    assert_empty plan.families
  end

  def test_all_known_roots_map_to_their_browser_process_family
    families = {
      'Google/Chrome Beta' => 'chrome', 'Google/Chrome Dev' => 'chrome',
      'Google/Chrome Canary' => 'chrome', 'Google/ChromeForTesting' => 'chrome',
      'Microsoft Edge' => 'edge', 'Microsoft Edge Beta' => 'edge',
      'Microsoft Edge Dev' => 'edge', 'Microsoft Edge Canary' => 'edge',
      'BraveSoftware/Brave-Browser' => 'brave', 'Chromium' => 'chromium',
      'Arc/User Data' => 'arc', 'Vivaldi' => 'vivaldi', 'com.operasoftware.Opera' => 'opera'
    }
    expected = families.keys.map do |browser|
      directory(site_path('https_claude.ai_0.indexeddb.leveldb', browser: browser))
    end
    outside = directory(site_path('https_claude.ai_0.indexeddb.leveldb', browser: 'Other Chromium'))

    plan = browser_data

    assert_equal expected.sort, plan.targets.map(&:path)
    assert_equal families.values.uniq.sort, plan.families.sort
    refute_includes plan.targets.map(&:path), outside
    assert_empty plan.issues
  end

  def test_named_profiles_support_chinese_spaces_guest_and_system_profiles
    expected = ['Profile 2 中文 空格', 'Guest Profile', 'System Profile'].map do |name|
      directory(site_path('https_claude.ai_0.indexeddb.blob', profile_name: name))
    end

    assert_equal expected.sort, browser_data.targets.map(&:path)
  end

  def test_other_profile_name_requires_a_regular_preferences_file_without_opening_it
    custom = profile(profile_name: '工作 账号')
    preferences = File.join(custom, 'Preferences')
    directory(custom)
    File.write(preferences, 'synthetic private content, never open')
    expected = directory(site_path('https_claude.ai_0.indexeddb.leveldb', profile_name: '工作 账号'))
    directory(site_path('https_claude.ai_0.indexeddb.leveldb', profile_name: 'Unrecognized folder'))
    File.stub(:read, proc { |*_args| flunk 'browser contents must not be read' }) do
      File.stub(:binread, proc { |*_args| flunk 'browser contents must not be read' }) do
        File.stub(:open, proc { |*_args| flunk 'browser contents must not be opened' }) do
          plan = browser_data
          assert_equal [expected], plan.targets.map(&:path)
          assert_empty plan.issues
        end
      end
    end
  end

  def test_nonregular_preferences_does_not_authorize_an_unknown_profile
    directory(File.join(profile(profile_name: 'Not a profile'), 'Preferences'))
    directory(site_path('https_claude.ai_0.indexeddb.leveldb', profile_name: 'Not a profile'))
    custom = directory(profile(profile_name: 'Linked preferences'))
    File.symlink(File.join(@temporary, 'absent'), File.join(custom, 'Preferences'))
    directory(site_path('https_claude.ai_0.indexeddb.leveldb', profile_name: 'Linked preferences'))

    assert_empty browser_data.targets
  end

  def test_opera_root_is_a_profile_but_chrome_root_is_not
    expected = directory(File.join(browser_root(browser: 'com.operasoftware.Opera'), 'IndexedDB',
                                   'https_claude.ai_0.indexeddb.blob'))
    directory(File.join(browser_root, 'IndexedDB', 'https_claude.ai_0.indexeddb.blob'))

    plan = browser_data

    assert_equal [expected], plan.targets.map(&:path)
    assert_equal ['opera'], plan.families
  end

  def test_target_leaf_symlinks_are_refused_without_following_the_destination
    outside = directory(File.join(@temporary, 'outside'))
    path = site_path('https_claude.ai_0.indexeddb.leveldb')
    directory(File.dirname(path))
    File.symlink(outside, path)

    plan = browser_data

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?('symlink') && issue.include?(path) }
    assert File.directory?(outside)
  end

  def test_target_leaf_files_are_refused
    path = site_path('https_claude.ai_0.indexeddb.blob')
    directory(File.dirname(path))
    File.write(path, 'keep')

    plan = browser_data

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(path) }
    assert_equal 'keep', File.read(path)
  end

  def test_target_leaf_must_belong_to_the_requested_uid
    path = directory(site_path('https_claude.ai_0.indexeddb.leveldb'))

    plan = plan_with_foreign_owner(path)

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(path) && issue.match?(/owner|UID/i) }
  end

  def test_browser_root_owned_by_another_uid_cannot_authorize_a_current_user_leaf
    directory(site_path('https_claude.ai_0.indexeddb.leveldb'))

    plan = plan_with_foreign_owner(browser_root)

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(browser_root) && issue.match?(/owner|UID/i) }
  end

  def test_profile_owned_by_another_uid_cannot_authorize_a_current_user_leaf
    directory(site_path('https_claude.ai_0.indexeddb.leveldb'))

    plan = plan_with_foreign_owner(profile)

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(profile) && issue.match?(/owner|UID/i) }
  end

  def test_preferences_profile_owned_by_another_uid_cannot_authorize_a_current_user_leaf
    custom_profile = directory(profile(profile_name: '工作 账号'))
    File.write(File.join(custom_profile, 'Preferences'), 'synthetic metadata fixture')
    directory(site_path('https_claude.ai_0.indexeddb.leveldb', profile_name: '工作 账号'))

    plan = plan_with_foreign_owner(custom_profile)

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(custom_profile) && issue.match?(/owner|UID/i) }
  end

  def test_indexeddb_owned_by_another_uid_cannot_authorize_a_current_user_leaf
    directory(site_path('https_claude.ai_0.indexeddb.leveldb'))
    indexeddb = File.join(profile, 'IndexedDB')

    plan = plan_with_foreign_owner(indexeddb)

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(indexeddb) && issue.match?(/owner|UID/i) }
  end

  def test_ordinary_ancestor_owner_does_not_block_a_current_user_browser_scope
    expected = directory(site_path('https_claude.ai_0.indexeddb.leveldb'))

    plan = plan_with_foreign_owner(File.join(@home, 'Library/Application Support'))

    assert_equal [expected], plan.targets.map(&:path)
    assert_empty plan.issues
  end

  def test_indexeddb_symlink_parent_is_refused_without_enumerating_outside
    outside = directory(File.join(@temporary, 'outside'))
    directory(File.join(outside, 'https_claude.ai_0.indexeddb.leveldb'))
    directory(profile)
    link = File.join(profile, 'IndexedDB')
    File.symlink(outside, link)

    plan = browser_data

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(link) && issue.include?('symlink') }
  end

  def test_symlink_named_profile_is_refused_but_normal_singleton_links_are_ignored
    outside = directory(File.join(@temporary, 'outside'))
    directory(browser_root)
    File.symlink(outside, profile)
    File.symlink('machine-123', File.join(browser_root, 'SingletonLock'))
    File.symlink('/tmp/synthetic-socket', File.join(browser_root, 'SingletonSocket'))

    plan = browser_data

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(profile) && issue.include?('symlink') }
    refute plan.issues.any? { |issue| issue.include?('Singleton') }
  end

  def test_parent_above_browser_root_symlink_is_refused
    outside = directory(File.join(@temporary, 'outside'))
    directory(File.join(@home, 'Library/Application Support'))
    link = File.join(@home, 'Library/Application Support/Google')
    File.symlink(outside, link)

    plan = browser_data

    assert_empty plan.targets
    assert_equal ['chrome'], plan.families
    assert plan.issues.any? { |issue| issue.include?(link) && issue.include?('symlink') }
  end

  def test_cannot_enumerate_a_browser_root_is_an_issue_and_requires_its_family_guard
    directory(browser_root)
    original = Dir.method(:children)
    Dir.stub(:children, proc { |path| path == browser_root ? raise(Errno::EACCES, path) : original.call(path) }) do
      plan = browser_data
      assert_empty plan.targets
      assert_equal ['chrome'], plan.families
      assert plan.issues.any? { |issue| issue.include?('EACCES') && issue.include?(browser_root) }
    end
  end

  def test_unreadable_browser_root_reports_the_real_permission_error
    skip 'root bypasses directory permission restrictions' if Process.uid.zero?
    directory(browser_root)
    File.chmod(0, browser_root)
    begin
      plan = browser_data
      assert_empty plan.targets
      assert_equal ['chrome'], plan.families
      assert plan.issues.any? { |issue| issue.include?('EACCES') }
    ensure
      File.chmod(0700, browser_root)
    end
  end

  def test_browser_root_replaced_during_enumeration_is_not_trusted
    directory(site_path('https_claude.ai_0.indexeddb.leveldb'))
    original = Dir.method(:children)
    replaced = false
    Dir.stub(:children, proc { |path|
      names = original.call(path)
      if path == browser_root && !replaced
        replaced = true
        File.rename(path, path + '.old')
        directory(path)
      end
      names
    }) do
      plan = browser_data
      assert_empty plan.targets
      assert_equal ['chrome'], plan.families
      assert plan.issues.any? { |issue| issue.include?('identity changed') }
    end
  end

  def test_target_disappearing_after_inspection_is_an_issue
    path = directory(site_path('https_claude.ai_0.indexeddb.leveldb'))
    original = File.method(:lstat)
    removed = false
    File.stub(:lstat, proc { |entry|
      stat = original.call(entry)
      if entry == path && !removed
        removed = true
        Dir.rmdir(path)
      end
      stat
    }) do
      plan = browser_data
      assert_empty plan.targets
      assert_equal ['chrome'], plan.families
      assert plan.issues.any? { |issue| issue.include?('changed') || issue.include?('disappeared') }
    end
  end

  def test_named_profile_disappearing_after_browser_enumeration_is_an_issue
    directory(profile)
    original = Dir.method(:children)
    Dir.stub(:children, proc { |path|
      names = original.call(path)
      Dir.rmdir(profile) if path == browser_root
      names
    }) do
      plan = browser_data
      assert_empty plan.targets
      assert_equal ['chrome'], plan.families
      assert plan.issues.any? { |issue| issue.include?(profile) && issue.include?('disappeared') }
    end
  end

  def test_target_directory_contents_are_never_enumerated
    expected = directory(site_path('https_claude.ai_0.indexeddb.leveldb'))
    File.write(File.join(expected, 'synthetic-session'), 'never read or list this entry')
    original = Dir.method(:children)
    Dir.stub(:children, proc { |path|
      flunk 'origin directory contents must not be enumerated' if path == expected
      original.call(path)
    }) do
      assert_equal [expected], browser_data.targets.map(&:path)
    end
  end

  def test_targets_and_issues_are_deterministic_without_duplicates
    path = directory(site_path('https_claude.ai_0.indexeddb.blob'))
    first = browser_data
    second = browser_data

    assert_equal [path], first.targets.map(&:path)
    assert_equal first.targets, second.targets
    assert_equal first.issues, second.issues
    assert_equal first.families, second.families
  end

  def test_invalid_home_paths_and_uid_are_rejected
    ['', '/', 'relative', File.join(@home, '..'), @home + "/\0", @home + '/.'].each do |home|
      assert_raises(ArgumentError) { browser_data(home: home) }
    end
    assert_raises(ArgumentError) { browser_data(uid: -1) }
    assert_raises(ArgumentError) { browser_data(uid: '0') }
  end

  def test_auditor_recognizes_all_three_blob_origins_as_remaining_site_storage
    expected = ORIGINS.map { |origin| directory(site_path("#{origin}.indexeddb.blob")) }

    findings = ClaudeCleaner::Auditor.new(home: @home, system_roots: []).findings

    assert_equal expected.sort, findings.map { |finding| finding[:path] }.sort
  end

  private

  def browser_data(home: @home, uid: Process.uid)
    ClaudeCleaner::BrowserData.new(home: home, uid: uid)
  end

  def plan_with_foreign_owner(path)
    original = File.method(:lstat)
    foreign_stat = original.call(path)
    foreign_stat.define_singleton_method(:uid) { Process.uid + 1 }
    File.stub(:lstat, proc { |entry| entry == path ? foreign_stat : original.call(entry) }) do
      browser_data
    end
  end

  def browser_root(browser: 'Google/Chrome')
    File.join(@home, 'Library/Application Support', browser)
  end

  def profile(browser: 'Google/Chrome', profile_name: 'Default')
    File.join(browser_root(browser: browser), profile_name)
  end

  def site_path(name, browser: 'Google/Chrome', profile_name: 'Default')
    File.join(profile(browser: browser, profile_name: profile_name), 'IndexedDB', name)
  end

  def directory(path)
    FileUtils.mkdir_p(path)
    path
  end
end

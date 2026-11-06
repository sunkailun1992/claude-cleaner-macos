# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/claude_cleaner/planner'

class PlannerTest < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir('claude-cleaner-planner-')
    @temporary = File.realpath(@temporary)
    @home = File.join(@temporary, '用户 home')
    FileUtils.mkdir_p(@home)
  end

  def teardown
    FileUtils.remove_entry(@temporary) if File.exist?(@temporary)
  end

  def make(relative, directory: false)
    path = File.join(@home, relative)
    FileUtils.mkdir_p(directory ? path : File.dirname(path))
    File.write(path, 'fixture content must remain untouched') unless directory
    path
  end

  def paths(plan)
    plan.targets.map(&:path)
  end

  def make_app(path, bundle = 'com.anthropic.claudefordesktop')
    FileUtils.mkdir_p(File.join(path, 'Contents'))
    File.write(File.join(path, 'Contents/Info.plist'), <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>#{bundle}</string></dict></plist>
    PLIST
    path
  end

  def test_previews_existing_targets_without_writing_and_captures_lstat_identity
    config = make('.claude/settings.json')
    backup = make('.claude.json.backup.1234')
    unrelated = make('claude-project/source.rb')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_includes paths(plan), File.dirname(config)
    assert_includes paths(plan), backup
    refute_includes paths(plan), unrelated
    target = plan.targets.find { |item| item.path == backup }
    stat = File.lstat(backup)
    assert_equal [stat.dev, stat.ino, 'file'], target.identity
    assert_equal 'fixture content must remain untouched', File.read(config)
    assert_empty plan.issues
  end

  def test_shared_security_and_worktrees_are_preserved_by_default
    security = make('.claude/security/shared.json')
    worktree = make('.claude/worktrees/project/main.rb')
    settings = make('.claude/settings.json')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal [settings], paths(plan)
    assert_includes plan.preserved.map { |item| item[:path] }, File.dirname(security)
    assert_includes plan.preserved.map { |item| item[:path] }, File.dirname(File.dirname(worktree))
  end

  def test_security_can_be_explicitly_included_but_worktrees_stay_protected
    security = make('.claude/security/shared.json')
    make('.claude/worktrees/project/main.rb')
    plan = ClaudeCleaner::Planner.new(home: @home, include_shared_security: true)

    assert_equal [File.dirname(security)], paths(plan)
    assert_equal [File.join(@home, '.claude/worktrees')], plan.preserved.map { |item| item[:path] }
  end

  def test_empty_protected_config_does_not_target_its_parent
    security = make('.claude/security', directory: true)
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_empty plan.targets
    assert_equal security, plan.preserved.first[:path]
  end

  def test_leaf_symlink_is_a_target_without_reading_its_destination
    outside = File.join(@temporary, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'keep'), 'keep')
    link = File.join(@home, '.claude')
    File.symlink(outside, link)
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal [link], paths(plan)
    assert_equal 'link', plan.targets.first.identity.last
    assert File.exist?(File.join(outside, 'keep'))
    assert_empty plan.issues
  end

  def test_parent_symlink_is_refused_and_reported
    outside = File.join(@temporary, 'outside')
    FileUtils.mkdir_p(File.join(outside, 'Application Support/Claude'))
    File.symlink(outside, File.join(@home, 'Library'))
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_empty plan.targets
    assert plan.issues.any? { |issue| issue.include?('symlink') && issue.include?('Library') }
  end

  def test_home_requires_an_absolute_existing_non_root_directory
    ['/', '', 'relative', File.join(@temporary, 'missing')].each do |home|
      assert_raises(ArgumentError) { ClaudeCleaner::Planner.new(home: home) }
    end
    file = File.join(@temporary, 'file')
    File.write(file, '')
    assert_raises(ArgumentError) { ClaudeCleaner::Planner.new(home: file) }
  end

  def test_home_symlink_is_refused
    link = File.join(@temporary, 'home-link')
    File.symlink(@home, link)
    assert_raises(ArgumentError) { ClaudeCleaner::Planner.new(home: link) }
  end

  def test_desktop_paths_are_precise_and_do_not_match_similar_bundles
    relatives = [
      'Library/Application Support/Claude', 'Library/Application Support/Claude-3p',
      'Library/Caches/com.anthropic.claudefordesktop',
      'Library/Caches/com.anthropic.claudefordesktop.ShipIt',
      'Library/HTTPStorages/com.anthropic.claudefordesktop',
      'Library/HTTPStorages/com.anthropic.claudefordesktop.binarycookies',
      'Library/Preferences/com.anthropic.claudefordesktop.plist',
      'Library/Preferences/ByHost/com.anthropic.claudefordesktop.ABC-123.plist',
      'Library/Saved Application State/com.anthropic.claudefordesktop.savedState',
      'Library/WebKit/com.anthropic.claudefordesktop', 'Library/Logs/Claude',
      'Library/Logs/DiagnosticReports/Claude-2026-11-06.ips',
      'Library/Application Support/CrashReporter/Claude_ABCD.plist'
    ]
    expected = relatives.map { |relative| make(relative) }
    near_matches = [
      'Library/Caches/com.anthropic.claudefordesktop.unrelated',
      'Library/Preferences/ByHost/com.anthropic.claudefordesktopOther.ABC.plist',
      'Library/Logs/DiagnosticReports/ClaudeProject-2026.ips',
      'Library/Application Support/CrashReporter/ClaudeProject_ABCD.plist'
    ].map { |relative| make(relative) }
    plan = ClaudeCleaner::Planner.new(home: @home)

    expected.each { |path| assert_includes paths(plan), path }
    near_matches.each { |path| refute_includes paths(plan), path }
  end

  def test_native_paths_and_switcher_are_fixed_names_only
    expected = [
      '.cache/claude', '.cache/claude-cli-nodejs', '.config/claude',
      '.local/bin/claude', '.local/share/claude', '.local/state/claude',
      '.claude-switcher', 'Library/Caches/claude-cli-nodejs'
    ].map { |relative| make(relative) }
    expected += %w[Claude.app Claude-3p.app].map { |name| make_app(File.join(@home, 'Applications', name)) }
    keep = make('.local/share/claude-project/source.rb')
    plan = ClaudeCleaner::Planner.new(home: @home)

    expected.each { |path| assert_includes paths(plan), path }
    refute_includes paths(plan), keep
  end

  def test_injected_application_and_install_prefixes_select_fixed_paths
    applications = File.join(@temporary, 'Applications')
    prefix = File.join(@temporary, 'prefix')
    expected = [File.join(applications, 'Claude.app'), File.join(applications, 'Claude-3p.app'),
                File.join(prefix, 'bin/claude'), File.join(prefix, 'lib/node_modules/@anthropic-ai/claude-code')]
    expected.first(2).each { |path| make_app(path) }
    FileUtils.mkdir_p(expected.last)
    FileUtils.mkdir_p(File.dirname(expected[2]))
    File.symlink('../lib/node_modules/@anthropic-ai/claude-code/cli.js', expected[2])
    FileUtils.mkdir_p(File.join(applications, 'Claude Project.app'))
    plan = ClaudeCleaner::Planner.new(home: @home, app_roots: [applications], prefixes: [prefix])

    assert_equal expected.sort, paths(plan).sort
  end

  def test_ide_extension_scans_do_not_select_other_publishers_or_shared_state
    expected = [
      '.vscode/extensions/anthropic.claude-code-2.0.0',
      '.cursor/extensions/anthropic.claude-code-2.0.0-darwin-arm64',
      'Library/Application Support/Code/User/globalStorage/anthropic.claude-code',
      'Library/Application Support/Cursor/User/globalStorage/anthropic.claude-code'
    ].map { |relative| make(relative) }
    keep = make('.vscode/extensions/other.claude-code-1.0.0')
    shared = make('Library/Application Support/Code/User/globalStorage/state.vscdb')
    plan = ClaudeCleaner::Planner.new(home: @home)

    expected.each { |path| assert_includes paths(plan), path }
    [keep, shared].each { |path| refute_includes paths(plan), path }
  end

  def test_native_hosts_use_exact_known_official_names
    browser = 'Library/Application Support/Google/Chrome/NativeMessagingHosts'
    expected = [make("#{browser}/com.anthropic.claude_code_browser_extension.json"),
                make("#{browser}/com.anthropic.claude_browser_extension.json")]
    keep = make("#{browser}/com.anthropic.claude_custom.json")
    plan = ClaudeCleaner::Planner.new(home: @home)

    expected.each { |path| assert_includes paths(plan), path }
    refute_includes paths(plan), keep
  end

  def test_custom_config_directories_are_inside_home_and_explicitly_claude_named
    config = make('.config/claude-work/settings.json')
    safe_root = File.dirname(config)
    outside = File.join(@temporary, 'claude-outside')
    FileUtils.mkdir_p(outside)
    bad_roots = [@home, File.join(@home, 'Library'), File.join(@home, '.config'), outside,
                 File.join(@home, 'project'), File.join(@home, '.claude/../Library')]
    bad_roots.each do |path|
      assert_raises(ArgumentError) { ClaudeCleaner::Planner.new(home: @home, config_dirs: [path]) }
    end
    plan = ClaudeCleaner::Planner.new(home: @home, config_dirs: [safe_root])

    assert_equal [safe_root], paths(plan)
  end

  def test_projects_are_opt_in_shallow_and_preserve_git_worktrees_and_mcp
    project = make('开发 项目', directory: true)
    settings = make('开发 项目/.claude/settings.json')
    worktree = make('开发 项目/.claude/worktrees/a/main.rb')
    instructions = make('开发 项目/CLAUDE.md')
    local_instructions = make('开发 项目/CLAUDE.local.md')
    mcp = make('开发 项目/.mcp.json')
    nested = make('开发 项目/nested/.claude/settings.json')
    assert_empty ClaudeCleaner::Planner.new(home: @home).targets
    plan = ClaudeCleaner::Planner.new(home: @home, projects: [project])

    assert_equal [settings], paths(plan)
    assert File.exist?(worktree)
    [instructions, local_instructions, mcp, nested].each { |path| refute_includes paths(plan), path }
    opted_in = ClaudeCleaner::Planner.new(home: @home, projects: [project], include_project_instructions: true)
    assert_equal [settings, instructions, local_instructions].sort, paths(opted_in).sort
  end

  def test_cowork_files_require_a_separate_option
    expected = [make('Claude/report.docx'), make('Documents/Claude/report.docx')].map { |path| File.dirname(path) }
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_empty plan.targets
    expected.each { |path| assert_includes plan.preserved.map { |item| item[:path] }, path }
    opted_in = ClaudeCleaner::Planner.new(home: @home, include_cowork_files: true)
    assert_equal expected.sort, paths(opted_in).sort
  end

  def test_runtime_scans_known_names_and_preserves_shared_security_guidance
    runtime = File.join(@temporary, 'runtime')
    names = ["claude-#{Process.uid}", 'claude-code-session-123', 'com.anthropic.claudefordesktop.helper',
             'claude-security-guidance-abc', 'claude-notes.txt', "claude-#{Process.uid + 1}"]
    names.each { |name| FileUtils.mkdir_p(File.join(runtime, name)) }
    plan = ClaudeCleaner::Planner.new(home: @home, runtime_roots: [runtime])

    assert_equal names.first(3).map { |name| File.join(runtime, name) }.sort, paths(plan).sort
    assert_includes plan.preserved.map { |item| item[:path] }, File.join(runtime, 'claude-security-guidance-abc')
  end

  def test_duplicate_roots_produce_one_target_and_repeated_plans_are_identical
    path = make('.claude/settings.json')
    roots = [File.dirname(path), File.dirname(path)]
    first = ClaudeCleaner::Planner.new(home: @home, config_dirs: roots)
    second = ClaudeCleaner::Planner.new(home: @home, config_dirs: roots)

    assert_equal [File.dirname(path)], paths(first)
    assert_equal first.targets, second.targets
    assert_equal first.preserved, second.preserved
  end

  def test_explicit_configuration_cannot_bypass_a_protected_ancestor
    config = make('.claude/security/claude-profile/settings.json')
    worktree = make('.claude/worktrees/claude-project/settings.json')
    plan = ClaudeCleaner::Planner.new(home: @home, config_dirs: [File.dirname(config), File.dirname(worktree)])

    assert_empty plan.targets
    assert_equal [File.join(@home, '.claude/security'), File.join(@home, '.claude/worktrees')],
                 plan.preserved.map { |entry| entry[:path] }
  end

  def test_configuration_suffixes_and_failed_npm_installs_are_enumerated
    expected = %w[.claude.json.lock .claude.json.tmp .claude.json.backup-2026].map { |name| make(name) }
    prefix = File.join(@temporary, 'prefix')
    residual = File.join(prefix, 'lib/node_modules/@anthropic-ai/.claude-code-abc123')
    FileUtils.mkdir_p(residual)
    expected << residual
    make('.claude-json-project')
    plan = ClaudeCleaner::Planner.new(home: @home, prefixes: [prefix])

    assert_equal expected.sort, paths(plan).sort
  end

  def test_unknown_or_missing_application_bundle_identity_is_preserved
    other = make_app(File.join(@home, 'Applications/Claude.app'), 'org.example.notes')
    unknown = make('Applications/Claude-3p.app', directory: true)
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_empty plan.targets
    assert_equal [unknown, other].sort, plan.preserved.map { |entry| entry[:path] }.sort
    assert_equal 2, plan.issues.length
  end

  def test_application_metadata_with_symlink_parent_is_never_followed
    app = make('Applications/Claude.app', directory: true)
    outside = File.join(@temporary, 'metadata')
    make_app(outside)
    File.symlink(File.join(outside, 'Contents'), File.join(app, 'Contents'))
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_empty plan.targets
    assert plan.issues.any? { |issue| issue.include?('symlink') }
    assert_includes plan.preserved.map { |entry| entry[:path] }, app
  end

  def test_security_guidance_runtime_requires_explicit_shared_security_option
    runtime = File.join(@temporary, 'runtime')
    shared = File.join(runtime, 'claude-security-guidance-abc')
    FileUtils.mkdir_p(shared)
    plan = ClaudeCleaner::Planner.new(home: @home, runtime_roots: [runtime], include_shared_security: true)

    assert_equal [shared], paths(plan)
    assert_empty plan.preserved
  end

  def test_vscodium_and_switcher_precise_bundle_paths_are_included
    expected = [
      '.vscode-oss/extensions/anthropic.claude-code-2.0.0',
      'Library/Application Support/VSCodium/User/globalStorage/anthropic.claude-code',
      'Library/Application Support/local.claude-switcher',
      'Library/Caches/local.claude-switcher',
      'Library/HTTPStorages/local.claude-switcher',
      'Library/Preferences/local.claude-switcher.plist'
    ].map { |relative| make(relative) }
    app = make_app(File.join(@home, 'Applications/Claude Switcher.app'), 'local.claude-switcher')
    expected << app
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal expected.sort, paths(plan).sort
  end

  def test_unreadable_configuration_scan_is_an_issue_not_a_cleanup_target
    skip 'root bypasses permission restrictions' if Process.uid.zero?
    config = make('.claude', directory: true)
    File.chmod(0, config)
    begin
      plan = ClaudeCleaner::Planner.new(home: @home)
      assert_empty plan.targets
      assert plan.issues.any? { |issue| issue.include?('Cannot scan') && issue.include?('.claude') }
    ensure
      File.chmod(0700, config)
    end
  end

  def test_jetbrains_only_selects_the_official_versioned_plugin_jar
    plugin = make('Library/Application Support/JetBrains/IntelliJIdea2026.2/plugins/claude-code-jetbrains-plugin-0.1.14-beta.jar')
    make('Library/Application Support/JetBrains/IntelliJIdea2026.2/plugins/claude-project-1.0.jar')
    make('Library/Application Support/JetBrains/IntelliJIdea2026.2/plugins/claude-code-jetbrains-plugin-notversion.jar')
    make('Library/Application Support/JetBrains/PyCharm2026.2/plugins/claude-code-jetbrains-plugin-0.1.14.jar', directory: true)
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal [plugin], paths(plan)
  end

  def test_app_leaf_links_are_preserved_without_following_bundle_metadata
    app = File.join(@home, 'Applications/Claude.app')
    outside = File.join(@temporary, 'outside.app')
    make_app(outside, 'org.example.notes')
    FileUtils.mkdir_p(File.dirname(app))
    File.symlink(outside, app)
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_empty plan.targets
    assert_includes plan.preserved.map { |entry| entry[:path] }, app
    assert plan.issues.any? { |issue| issue.include?('Unverified') }
  end

  def test_switcher_desktop_bundle_uses_the_known_identifier
    app = make_app(File.join(@home, 'Desktop/Claude切换器.app'), 'local.claude-switcher')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal [app], paths(plan)
  end

  def test_invalid_or_oversized_bundle_metadata_is_preserved
    app = make_app(File.join(@home, 'Applications/Claude.app'))
    File.write(File.join(app, 'Contents/Info.plist'), '<plist><dict>')
    plan = ClaudeCleaner::Planner.new(home: @home)
    assert_empty plan.targets
    assert_includes plan.preserved.map { |entry| entry[:path] }, app

    File.write(File.join(app, 'Contents/Info.plist'), 'x' * 1_048_577)
    oversized = ClaudeCleaner::Planner.new(home: @home)
    assert_empty oversized.targets
    assert_includes oversized.preserved.map { |entry| entry[:path] }, app
  end

  def test_runtime_entries_owned_by_another_user_are_never_selected
    runtime = File.join(@temporary, 'runtime')
    foreign = File.join(runtime, 'claude-code-other-session')
    owned = File.join(runtime, "claude-#{Process.uid}")
    FileUtils.mkdir_p(foreign)
    FileUtils.mkdir_p(owned)
    original = File.method(:lstat)
    foreign_stat = original.call(foreign)
    foreign_stat.define_singleton_method(:uid) { Process.uid + 1 }
    File.stub(:lstat, proc { |path| path == foreign ? foreign_stat : original.call(path) }) do
      plan = ClaudeCleaner::Planner.new(home: @home, runtime_roots: [runtime])
      assert_equal [owned], paths(plan)
      assert_includes plan.preserved.map { |entry| entry[:path] }, foreign
    end
  end

  def test_recent_documents_are_limited_to_exact_bundle_list_files
    root = 'Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments'
    expected = [make("#{root}/com.anthropic.claudefordesktop.sfl2"),
                make("#{root}/com.anthropic.claudefordesktop.sfl3")]
    make("#{root}/com.anthropic.claudefordesktopOther.sfl3")
    make("#{root}/other.sfl3")
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal expected.sort, paths(plan).sort
  end

  def test_chrome_for_testing_native_host_uses_known_exact_manifest
    host = make('Library/Application Support/Google/ChromeForTesting/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal [host], paths(plan)
  end

  def test_unknown_configuration_prefixes_are_manual_preserves
    unknown = make('.claude.json-project-notes.md')
    known = make('.claude.json.backup.20261106')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal [known], paths(plan)
    entry = plan.preserved.find { |item| item[:path] == unknown }
    refute_nil entry
    assert_equal 'manual: unrecognized configuration backup name', entry[:reason]
  end

  def test_known_user_launchagent_files_are_planned_without_other_services
    expected = [make('Library/LaunchAgents/local.claude-update.plist'),
                make('Library/LaunchAgents/local.claude-bodyguard.plist')]
    unrelated = make('Library/LaunchAgents/local.claude-project.plist')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal expected.sort, paths(plan).sort
    refute_includes paths(plan), unrelated
  end

  def test_install_prefix_executables_require_a_known_package_symlink
    prefix = File.join(@temporary, 'prefix')
    executable = File.join(prefix, 'bin/claude')
    FileUtils.mkdir_p(File.dirname(executable))
    File.write(executable, 'user source, not an identified installation')
    plan = ClaudeCleaner::Planner.new(home: @home, prefixes: [prefix])

    assert_empty plan.targets
    assert_equal [{path: executable, reason: 'manual: unverified Claude executable'}], plan.preserved
    File.unlink(executable)
    source = File.join(@temporary, 'my-claude-script.rb')
    File.write(source, 'keep')
    File.symlink(source, executable)
    other = ClaudeCleaner::Planner.new(home: @home, prefixes: [prefix])
    assert_empty other.targets
    assert_equal 'manual: unverified Claude executable', other.preserved.first[:reason]
    assert_equal 'keep', File.read(source)
  end

  def test_install_prefix_recognizes_caskroom_symlinks_without_opening_targets
    prefix = File.join(@temporary, 'prefix')
    executable = File.join(prefix, 'bin/claude')
    FileUtils.mkdir_p(File.dirname(executable))
    ['../Caskroom/claude-code/2.1.0/claude', '../Caskroom/claude-code@latest/2.1.0/claude'].each do |destination|
      File.symlink(destination, executable)
      plan = ClaudeCleaner::Planner.new(home: @home, prefixes: [prefix])
      assert_equal [executable], paths(plan)
      assert_equal 'link', plan.targets.first.identity.last
      File.unlink(executable)
    end
  end

  def test_install_prefix_link_changed_during_identification_is_refused
    prefix = File.join(@temporary, 'prefix')
    executable = File.join(prefix, 'bin/claude')
    FileUtils.mkdir_p(File.dirname(executable))
    File.symlink('../lib/node_modules/@anthropic-ai/claude-code/cli.js', executable)
    File.stub(:readlink, proc { |_path|
      File.unlink(executable)
      File.write(executable, 'new unrelated file')
      '../lib/node_modules/@anthropic-ai/claude-code/cli.js'
    }) do
      plan = ClaudeCleaner::Planner.new(home: @home, prefixes: [prefix])
      assert_empty plan.targets
      assert plan.issues.any? { |issue| issue.include?('identity changed') }
    end
  end

  def test_known_switcher_scripts_logs_and_sqlite_backups_are_exact_targets
    expected = [
      '.local/bin/claude-switch.sh', '.local/bin/claude-switch.sh.bak',
      '.local/bin/claude-switch-updater.sh', '.local/bin/local.claude-bodyguard.plist',
      'Library/Logs/claude-switch.log', 'Library/Logs/claude-bodyguard.log',
      'Library/Logs/claude-switcher', '.claude-switcher-backup-20261106-171500-deadbeef.sqlite',
      '.claude-switcher-backup-20261106-171500-deadbeef.sqlite-wal',
      '.claude-switcher-backup-20261106-171500-deadbeef.sqlite-shm'
    ].map { |relative| make(relative) }
    make('.local/bin/claude-switch-source.rb')
    unknown = make('.claude-switcher-backup-project-source.sqlite')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal expected.sort, paths(plan).sort
    assert_includes plan.preserved.map { |entry| entry[:path] }, unknown
  end

  def test_switcher_runtime_bundle_is_current_user_only
    runtime = File.join(@temporary, 'runtime')
    entry = File.join(runtime, 'local.claude-switcher')
    FileUtils.mkdir_p(entry)
    plan = ClaudeCleaner::Planner.new(home: @home, runtime_roots: [runtime])
    assert_equal [entry], paths(plan)

    original = File.method(:lstat)
    foreign_stat = original.call(entry)
    foreign_stat.define_singleton_method(:uid) { Process.uid + 1 }
    File.stub(:lstat, proc { |path| path == entry ? foreign_stat : original.call(path) }) do
      foreign = ClaudeCleaner::Planner.new(home: @home, runtime_roots: [runtime])
      assert_empty foreign.targets
    end
  end

  def test_fixed_config_directory_uses_shared_security_and_worktree_protection
    settings = make('.config/claude/settings.json')
    history = make('.config/claude/history.jsonl')
    security = make('.config/claude/security/shared.json')
    worktree = make('.config/claude/worktrees/project/main.rb')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal [history, settings].sort, paths(plan).sort
    assert_includes plan.preserved.map { |entry| entry[:path] }, File.dirname(security)
    assert_includes plan.preserved.map { |entry| entry[:path] }, File.dirname(File.dirname(worktree))
    opted = ClaudeCleaner::Planner.new(home: @home, include_shared_security: true)
    assert_equal [history, settings, File.dirname(security)].sort, paths(opted).sort
  end

  def test_known_home_directory_backups_are_planned_without_searching_other_projects
    names = [
      '.claude.bak-20261106', '.claude.bak-20261106-173000',
      '.claude.backup-2026-11-06', '.claude.backup-2026-11-06T17-30-00Z',
      '.claude-backup-20261106', '.claude-backup-20261106-173000',
      '.claude.backup.2026-11-06_17-30-00', '.claude.backup.20261106-173000'
    ]
    expected = names.map { |name| File.dirname(make("#{name}/projects/session.jsonl")) }.map { |path| File.dirname(path) }
    unknown = make('.claude.bak-project/source.rb')
    invalid_date = make('.claude.bak-20269999/source.rb')
    nested = make('source/.claude.bak-20261106/source.rb')
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal expected.sort, paths(plan).sort
    [File.dirname(unknown), File.dirname(invalid_date)].each do |path|
      assert_includes plan.preserved.map { |entry| entry[:path] }, path
    end
    refute_includes paths(plan), File.dirname(nested)
    assert File.exist?(nested)
  end

  def test_backup_configurations_keep_security_and_git_worktrees
    backup = '.claude-backup-20261106-173000'
    session = make("#{backup}/sessions/chat.jsonl")
    security = make("#{backup}/security/shared.json")
    worktree = make("#{backup}/worktrees/project/source.rb")
    plan = ClaudeCleaner::Planner.new(home: @home)

    assert_equal [File.dirname(session)], paths(plan)
    assert_includes plan.preserved.map { |entry| entry[:path] }, File.dirname(security)
    assert_includes plan.preserved.map { |entry| entry[:path] }, File.dirname(File.dirname(worktree))
    assert_includes plan.configuration_roots, File.join(@home, backup)
    assert_includes plan.configuration_roots, File.join(@home, '.config/claude')
  end
end

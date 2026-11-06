# frozen_string_literal: true

require 'open3'
require 'rexml/document'
require 'date'

module ClaudeCleaner
  Target = Struct.new(:path, :reason, :identity, keyword_init: true)

  # Enumerates metadata only. The sole content read is bounded app Info.plist metadata.
  # Configuration, session, and browser-host contents are never opened.
  class Planner
    BUNDLES = %w[
      com.anthropic.claudefordesktop
      com.anthropic.claudefordesktop.helper
      com.anthropic.claudefordesktop.helper.GPU
      com.anthropic.claudefordesktop.helper.Renderer
      com.anthropic.claudefordesktop.helper.Plugin
    ].freeze
    NATIVE_HOSTS = %w[
      com.anthropic.claude_browser_extension.json
      com.anthropic.claude_code_browser_extension.json
    ].freeze
    CONFIG_BACKUP_PATTERNS = [
      /\A\.claude\.bak-(\d{8})(?:-(?:[01]\d|2[0-3])[0-5]\d[0-5]\d)?\z/,
      /\A\.claude\.backup-(\d{4}-\d{2}-\d{2})(?:[T_-](?:[01]\d|2[0-3])[-:]?[0-5]\d[-:]?[0-5]\dZ?)?\z/,
      /\A\.claude-backup-(\d{8}|\d{4}-\d{2}-\d{2})(?:-(?:[01]\d|2[0-3])[0-5]\d[0-5]\d)?\z/,
      /\A\.claude\.backup\.(\d{4}-\d{2}-\d{2})_(?:[01]\d|2[0-3])-[0-5]\d-[0-5]\d\z/,
      /\A\.claude\.backup\.(\d{8})-(?:[01]\d|2[0-3])[0-5]\d[0-5]\d\z/
    ].freeze
    BROWSER_DIRS = [
      'Google/Chrome', 'Google/Chrome Beta', 'Google/Chrome Dev', 'Google/Chrome Canary',
      'Google/ChromeForTesting',
      'Microsoft Edge', 'Microsoft Edge Beta', 'Microsoft Edge Dev', 'Microsoft Edge Canary',
      'BraveSoftware/Brave-Browser', 'Chromium', 'Arc/User Data', 'Vivaldi', 'com.operasoftware.Opera'
    ].freeze
    USER_PATHS = [
      '.claude.json', '.claude-switcher', '.cache/claude', '.cache/claude-cli-nodejs',
      '.local/bin/claude', '.local/share/claude', '.local/state/claude',
      '.local/bin/claude-switch.sh', '.local/bin/claude-switch.sh.bak',
      '.local/bin/claude-switch-updater.sh', '.local/bin/local.claude-bodyguard.plist',
      'Library/Caches/claude-cli-nodejs', 'Library/Application Support/local.claude-switcher',
      'Library/Caches/local.claude-switcher', 'Library/HTTPStorages/local.claude-switcher',
      'Library/HTTPStorages/local.claude-switcher.binarycookies',
      'Library/Preferences/local.claude-switcher.plist',
      'Library/Saved Application State/local.claude-switcher.savedState',
      'Library/WebKit/local.claude-switcher', 'Library/Logs/local.claude-switcher',
      'Library/LaunchAgents/local.claude-update.plist',
      'Library/LaunchAgents/local.claude-bodyguard.plist',
      'Library/Logs/claude-switch.log', 'Library/Logs/claude-bodyguard.log', 'Library/Logs/claude-switcher',
      'Library/Application Support/Claude', 'Library/Application Support/Claude-3p',
      'Library/Logs/Claude', 'Library/Logs/Claude-3p'
    ].freeze

    def initialize(home:, app_roots: [], prefixes: [], runtime_roots: [], config_dirs: [], projects: [],
                   include_shared_security: false, include_project_instructions: false,
                   include_cowork_files: false)
      @targets = []
      @preserved = []
      @issues = []
      @configuration_roots = []
      @home = absolute_path(home, 'home')
      validate_home!
      @include_shared_security = include_shared_security
      @include_project_instructions = include_project_instructions
      @include_cowork_files = include_cowork_files
      @app_roots = paths_argument(app_roots, 'application root')
      @prefixes = paths_argument(prefixes, 'installation prefix')
      @runtime_roots = paths_argument(runtime_roots, 'runtime root')
      @config_dirs = paths_argument(config_dirs, 'configuration directory')
      @projects = paths_argument(projects, 'project root')
      @config_dirs.each { |path| validate_config!(path) }
      @projects.each { |path| validate_project!(path) }
      scan
      @targets.sort_by!(&:path)
      @preserved.sort_by! { |item| item[:path] }
      @issues.uniq!
    end

    attr_reader :targets, :preserved, :issues, :configuration_roots

    private

    def absolute_path(path, label)
      unless path.is_a?(String) && path.start_with?('/') && !path.include?("\0")
        raise ArgumentError, "#{label} must be an absolute path"
      end
      if path.split('/').include?('..')
        raise ArgumentError, "#{label} must not contain parent traversal"
      end
      normalized = File.expand_path(path)
      raise ArgumentError, "#{label} must not be /" if normalized == '/'
      normalized
    end

    def paths_argument(paths, label)
      raise ArgumentError, "#{label} list must be an array" unless paths.is_a?(Array)
      paths.map { |path| absolute_path(path, label) }.uniq
    end

    def validate_home!
      stat = safe_stat(@home)
      unless stat && stat.directory? && !stat.symlink?
        raise ArgumentError, 'home must be an existing directory without symlink parents'
      end
    end

    def validate_config!(path)
      named = File.basename(path).match?(/\A\.?claude(?:[-_.][A-Za-z0-9][A-Za-z0-9._-]*)?\z/)
      unless path.start_with?(@home + '/') && named
        raise ArgumentError, 'custom configuration must be a Claude-named directory inside home'
      end
      stat = safe_stat(path)
      if stat && !stat.directory? && !stat.symlink?
        raise ArgumentError, 'custom configuration must be a directory or leaf symlink'
      end
    end

    def validate_project!(path)
      stat = safe_stat(path)
      unless stat && stat.directory? && !stat.symlink?
        raise ArgumentError, 'project root must be an existing directory without symlink parents'
      end
    end

    def scan
      USER_PATHS.each { |relative| add(File.join(@home, relative), 'known Claude user data') }
      scan_config(File.join(@home, '.claude'))
      scan_config(File.join(@home, '.config/claude'))
      @config_dirs.each { |path| scan_config(path) }
      scan_backups
      scan_configuration_backups
      scan_switcher_backups
      scan_desktop
      scan_applications
      scan_prefixes
      scan_ide
      scan_native_hosts
      scan_runtime
      scan_projects
      scan_cowork
      remove_overlapping_targets
    end

    def scan_config(path)
      @configuration_roots << path.dup.freeze unless @configuration_roots.include?(path)
      stat = safe_stat(path)
      return unless stat
      return add(path, 'Claude configuration leaf') unless stat.directory?

      protected = ['worktrees']
      protected << 'security' unless @include_shared_security
      entries = children(path)
      return unless entries
      protected_entries = entries.select { |entry| protected.include?(File.basename(entry)) }
      if protected_entries.empty?
        add(path, 'Claude configuration and sessions')
      else
        protected_entries.each do |entry|
          preserve(entry, File.basename(entry) == 'security' ? 'shared security data' : 'Git worktrees')
        end
        (entries - protected_entries).each { |entry| add(entry, 'Claude configuration and sessions') }
      end
    end

    def scan_backups
      matching(@home) { |name| name.start_with?('.claude.json') }.each do |path|
        name = File.basename(path)
        if name.match?(/\A\.claude\.json(?:\.(?:backup|bak|tmp|orig|lock)(?:[.-][0-9][0-9TtZz._:-]*)?)?\z/)
          add(path, 'Claude configuration or known backup')
        else
          preserve(path, 'manual: unrecognized configuration backup name')
        end
      end
    end

    def scan_switcher_backups
      matching(@home) { |name| name.start_with?('.claude-switcher-backup-') }.each do |path|
        if File.basename(path).match?(/\A\.claude-switcher-backup-[0-9][0-9TtZz._:-]*-[a-fA-F0-9]{4,64}\.sqlite(?:-(?:wal|shm))?\z/)
          add(path, 'known Claude switcher database backup')
        else
          preserve(path, 'manual: unrecognized Claude switcher backup name')
        end
      end
    end

    def scan_configuration_backups
      matching(@home) do |name|
        name.start_with?('.claude.bak', '.claude.backup', '.claude-backup')
      end.each do |path|
        stat = safe_stat(path)
        if stat && stat.directory? && !stat.symlink? && known_configuration_backup?(File.basename(path))
          scan_config(path)
        else
          preserve(path, 'manual: unrecognized Claude configuration backup directory')
        end
      end
    end

    def known_configuration_backup?(name)
      CONFIG_BACKUP_PATTERNS.each do |pattern|
        match = pattern.match(name)
        next unless match
        Date.strptime(match[1].delete('-'), '%Y%m%d')
        return true
      end
      false
    rescue ArgumentError
      false
    end

    def scan_desktop
      library = File.join(@home, 'Library')
      BUNDLES.each do |bundle|
        %w[Caches HTTPStorages Logs WebKit].each do |directory|
          add(File.join(library, directory, bundle), 'Claude Desktop bundle data')
        end
        add(File.join(library, 'Caches', bundle + '.ShipIt'), 'Claude Desktop updater cache')
        add(File.join(library, 'HTTPStorages', bundle + '.binarycookies'), 'Claude Desktop HTTP cookies')
        add(File.join(library, 'Preferences', bundle + '.plist'), 'Claude Desktop preferences')
        add(File.join(library, 'Saved Application State', bundle + '.savedState'), 'Claude Desktop saved state')
      end
      matching(File.join(library, 'Preferences/ByHost')) do |name|
        BUNDLES.any? { |bundle| name.match?(/\A#{Regexp.escape(bundle)}\.[A-Fa-f0-9-]+\.plist\z/) }
      end.each { |path| add(path, 'Claude Desktop host preferences') }
      matching(File.join(library, 'Logs/DiagnosticReports')) do |name|
        name.match?(/\AClaude(?:-3p| Helper(?: \((?:GPU|Renderer|Plugin)\))?)?[-_]\d[^\/]*\.(?:ips|crash|diag)\z/)
      end.each { |path| add(path, 'Claude Desktop diagnostic report') }
      matching(File.join(library, 'Application Support/CrashReporter')) do |name|
        name.match?(/\AClaude(?:-3p| Helper(?: \((?:GPU|Renderer|Plugin)\))?)?_[A-Za-z0-9-]+\.plist\z/)
      end.each { |path| add(path, 'Claude Desktop crash reporter metadata') }
      recent = File.join(library, 'Application Support/com.apple.sharedfilelist',
                         'com.apple.LSSharedFileList.ApplicationRecentDocuments')
      matching(recent) do |name|
        BUNDLES.any? { |bundle| name.match?(/\A#{Regexp.escape(bundle)}\.sfl\d*\z/) }
      end.each { |path| add(path, 'Claude Desktop recent documents list') }
    end

    def scan_applications
      ([File.join(@home, 'Applications')] + @app_roots).uniq.each do |root|
        %w[Claude.app Claude-3p.app].each do |name|
          scan_application(File.join(root, name), ['com.anthropic.claudefordesktop'])
        end
        ['Claude Switcher.app', 'Claude-Switcher.app', 'claude-switcher.app', 'Claude切换器.app'].each do |name|
          scan_application(File.join(root, name), ['local.claude-switcher'])
        end
      end
      ['Claude切换器.app', 'Claude Switcher.app'].each do |name|
        scan_application(File.join(@home, 'Desktop', name), ['local.claude-switcher'])
      end
    end

    def scan_application(path, allowed_bundles)
      stat = safe_stat(path)
      return unless stat
      # App links are preserved: their names alone cannot establish bundle identity.
      bundle = application_bundle(path) if stat.directory? && !stat.symlink?
      if allowed_bundles.include?(bundle)
        add(path, 'verified Claude application bundle')
      else
        preserve(path, 'unverified application bundle identity; inspect manually')
        @issues << "Unverified application bundle identity: #{path}"
      end
    end

    def application_bundle(path)
      info = File.join(path, 'Contents/Info.plist')
      stat = safe_stat(info)
      return nil unless stat && stat.file? && !stat.symlink? && stat.size <= 1_048_576
      flags = File::RDONLY
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
      content = File.open(info, flags) do |file|
        opened = file.stat
        return nil unless [opened.dev, opened.ino] == [stat.dev, stat.ino]
        file.read(1_048_577)
      end
      return nil if content.bytesize > 1_048_576
      if content.start_with?('bplist')
        return nil unless File.executable?('/usr/bin/plutil')
        output, _error, status = Open3.capture3('/usr/bin/plutil', '-extract', 'CFBundleIdentifier',
                                               'raw', '-o', '-', '-', stdin_data: content)
        return status.success? ? output.strip : nil
      end
      return nil if content.match?(/<!ENTITY/i)
      document = REXML::Document.new(content)
      dictionary = document.elements['plist/dict']
      return nil unless dictionary
      dictionary.elements.to_a.each_cons(2) do |key, value|
        return value.text.to_s if key.name == 'key' && key.text == 'CFBundleIdentifier' && value.name == 'string'
      end
      nil
    rescue SystemCallError, IOError, REXML::ParseException => error
      @issues << "Cannot inspect application metadata #{path}: #{error.class}"
      nil
    end

    def scan_prefixes
      @prefixes.each do |root|
        scan_prefix_executable(File.join(root, 'bin/claude'))
        add(File.join(root, 'lib/node_modules/@anthropic-ai/claude-code'), 'Claude Code npm installation')
        matching(File.join(root, 'lib/node_modules/@anthropic-ai')) do |name|
          name.match?(/\A\.claude-code-[A-Za-z0-9_-]+\z/)
        end.each { |path| add(path, 'Claude Code failed npm installation') }
      end
    end

    def scan_prefix_executable(path)
      stat = safe_stat(path)
      return unless stat
      if stat.symlink?
        destination = File.expand_path(File.readlink(path), File.dirname(path))
        known_npm = destination.match?(%r{/(?:lib/)?node_modules/@anthropic-ai/claude-code/(?:cli\.js|bin/claude)\z})
        known_cask = destination.match?(%r{/Caskroom/claude-code(?:@latest)?/[^/]+/claude\z})
        if known_npm || known_cask
          expected = [stat.dev, stat.ino, stat.ftype]
          return add(path, 'verified Claude Code installation symlink', expected_identity: expected)
        end
      end
      preserve(path, 'manual: unverified Claude executable')
    rescue SystemCallError, IOError => error
      @issues << "Cannot identify Claude executable #{path}: #{error.class}"
    end

    def scan_ide
      %w[.vscode .vscode-insiders .vscode-oss .cursor].each do |ide|
        matching(File.join(@home, ide, 'extensions')) do |name|
          name.match?(/\Aanthropic\.claude-code-[0-9][A-Za-z0-9.+_-]*\z/)
        end.each { |path| add(path, 'official Claude Code IDE extension') }
      end
      ['Code', 'Code - Insiders', 'Cursor', 'VSCodium'].each do |ide|
        storage = File.join(@home, 'Library/Application Support', ide, 'User/globalStorage/anthropic.claude-code')
        add(storage, 'official Claude Code IDE extension storage')
      end
      jetbrains = File.join(@home, 'Library/Application Support/JetBrains')
      (children(jetbrains) || []).each do |ide|
        matching(File.join(ide, 'plugins')) do |name|
          name.match?(/\Aclaude-code-jetbrains-plugin-\d+\.\d+\.\d+(?:[-.][A-Za-z0-9]+)*\.jar\z/)
        end.each do |path|
          stat = safe_stat(path)
          add(path, 'official Claude Code JetBrains plugin jar') if stat && stat.file? && !stat.symlink?
        end
      end
    end

    def scan_native_hosts
      BROWSER_DIRS.each do |browser|
        root = File.join(@home, 'Library/Application Support', browser, 'NativeMessagingHosts')
        NATIVE_HOSTS.each { |name| add(File.join(root, name), 'official Claude browser native host manifest') }
      end
    end

    def scan_runtime
      @runtime_roots.each do |root|
        entries = children(root)
        next unless entries
        entries.each do |path|
          name = File.basename(path)
          candidate = name.start_with?('claude-security-guidance-') || name == "claude-#{Process.uid}" ||
                      name.match?(/\Aclaude-code-[A-Za-z0-9._-]+\z/) || BUNDLES.include?(name) ||
                      name == 'com.anthropic.claudefordesktop.ShipIt' || name == 'local.claude-switcher'
          next unless candidate
          stat = safe_stat(path)
          next unless stat
          unless stat.uid == Process.uid
            preserve(path, 'other user runtime data is outside the cleanup scope')
            next
          end
          if name.start_with?('claude-security-guidance-')
            if @include_shared_security
              add(path, 'explicitly selected shared security guidance runtime')
            else
              preserve(path, 'shared security guidance runtime')
            end
          else
            add(path, 'known current-user Claude runtime data')
          end
        end
      end
    end

    def scan_projects
      @projects.each do |root|
        scan_config(File.join(root, '.claude'))
        %w[CLAUDE.md CLAUDE.local.md].each do |name|
          path = File.join(root, name)
          if @include_project_instructions
            add(path, 'explicitly selected project instructions')
          else
            preserve(path, 'project instructions require a separate option')
          end
        end
        preserve(File.join(root, '.mcp.json'), 'shared project MCP configuration')
      end
    end

    def scan_cowork
      ['Claude', 'Documents/Claude'].each do |relative|
        path = File.join(@home, relative)
        if @include_cowork_files
          add(path, 'explicitly selected Cowork user files')
        else
          preserve(path, 'Cowork user files require a separate option')
        end
      end
    end

    def children(path)
      stat = safe_stat(path)
      return [] unless stat
      unless stat.directory? && !stat.symlink?
        @issues << "Refused to scan non-directory or symlink: #{path}"
        return nil
      end
      Dir.children(path).sort.map { |name| File.join(path, name) }
    rescue SystemCallError, IOError => error
      @issues << "Cannot scan #{path}: #{error.class}: #{error.message}"
      nil
    end

    def matching(root)
      entries = children(root)
      return [] unless entries
      entries.select { |path| yield(File.basename(path)) }
    end

    def safe_stat(path)
      return nil unless safe_parents?(path)
      File.lstat(path)
    rescue Errno::ENOENT, Errno::ENOTDIR
      nil
    rescue SystemCallError, IOError => error
      @issues << "Cannot inspect #{path}: #{error.class}: #{error.message}"
      nil
    end

    def safe_parents?(path)
      parent = File.dirname(path)
      ancestors = []
      until parent == '/'
        ancestors << parent
        parent = File.dirname(parent)
      end
      ancestors.reverse_each do |ancestor|
        stat = File.lstat(ancestor)
        if stat.symlink?
          @issues << "Refused symlink parent: #{ancestor} (for #{path})"
          return false
        end
        return false unless stat.directory?
      end
      true
    rescue Errno::ENOENT, Errno::ENOTDIR
      false
    rescue SystemCallError, IOError => error
      @issues << "Cannot inspect parent of #{path}: #{error.class}: #{error.message}"
      false
    end

    def add(path, reason, expected_identity: nil)
      stat = safe_stat(path)
      return unless stat
      if expected_identity && [stat.dev, stat.ino, stat.ftype] != expected_identity
        @issues << "Refused target whose identity changed during planning: #{path}"
        return
      end
      return if @targets.any? { |target| target.path == path }
      identity = [stat.dev, stat.ino, stat.ftype].freeze
      @targets << Target.new(path: path.freeze, reason: reason.freeze, identity: identity).freeze
    end

    def preserve(path, reason)
      return unless safe_stat(path)
      return if @preserved.any? { |entry| entry[:path] == path }
      @preserved << { path: path.freeze, reason: reason.freeze }.freeze
    end

    def remove_overlapping_targets
      # A selected ancestor must never swallow an explicitly protected descendant.
      @targets.reject! do |target|
        @preserved.any? do |entry|
          entry[:path] == target.path || entry[:path].start_with?(target.path + '/') ||
            target.path.start_with?(entry[:path] + '/')
        end
      end
      paths = @targets.map(&:path)
      @targets.reject! do |target|
        paths.any? { |other| other != target.path && target.path.start_with?(other + '/') }
      end
    end
  end
end

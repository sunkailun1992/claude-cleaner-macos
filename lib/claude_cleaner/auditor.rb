# frozen_string_literal: true

module ClaudeCleaner
  # Read-only, bounded inventory of names and lstat metadata. Findings describe
  # manual work or an unverified scope; shared browser databases are never read.
  class Auditor
    EXTENSION_ID = 'fcoeoabgfenejglbffodgkkbkcdhcgfn'
    BROWSER_DIRS = [
      'Google/Chrome', 'Google/Chrome Beta', 'Google/Chrome Dev', 'Google/Chrome Canary',
      'Google/ChromeForTesting', 'Microsoft Edge', 'Microsoft Edge Beta',
      'Microsoft Edge Dev', 'Microsoft Edge Canary', 'BraveSoftware/Brave-Browser',
      'Chromium', 'Arc/User Data', 'Vivaldi', 'com.operasoftware.Opera'
    ].freeze
    EXTENSION_PATHS = [
      "Extensions/#{EXTENSION_ID}", "Local Extension Settings/#{EXTENSION_ID}",
      "Sync Extension Settings/#{EXTENSION_ID}",
      "IndexedDB/chrome-extension_#{EXTENSION_ID}_0.indexeddb.leveldb"
    ].freeze
    SITE_PATHS = %w[
      IndexedDB/https_claude.ai_0.indexeddb.leveldb
      IndexedDB/https_console.anthropic.com_0.indexeddb.leveldb
      IndexedDB/https_platform.claude.com_0.indexeddb.leveldb
    ].freeze
    MANAGED_PATHS = [
      'Application Support/ClaudeCode/managed-settings.json',
      'Application Support/ClaudeCode/managed-settings.d',
      'Application Support/ClaudeCode/managed-mcp.json'
    ].freeze
    THIRD_PARTY_PATHS = ['Application Support/claude-switcher'].freeze
    DAEMON_PATHS = %w[
      LaunchDaemons/local.claude-bodyguard.plist
      LaunchDaemons/local.tz-watchdog.plist
      LaunchDaemons/local.claude-update.plist
    ].freeze
    NATIVE_HOSTS = %w[
      com.anthropic.claude_browser_extension.json
      com.anthropic.claude_code_browser_extension.json
    ].freeze
    # Official macOS host locations differ for system and user installations:
    # https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
    SYSTEM_HOST_DIRS = [
      'Google/Chrome/NativeMessagingHosts',
      'Google/ChromeForTesting/NativeMessagingHosts',
      'Application Support/Chromium/NativeMessagingHosts'
    ].freeze
    PROFILE_NAME = /\A(?:Default|Profile [^\/]+|Guest Profile|System Profile)\z/

    def initialize(home:, system_roots: ['/Library'], runtime_tmp: nil)
      @home = absolute_path(home)
      raise ArgumentError, 'system_roots must be an array' unless system_roots.is_a?(Array)

      @system_roots = system_roots.map { |path| absolute_path(path) }.uniq
      @runtime_tmp = runtime_tmp.nil? ? ENV['CLAUDE_CODE_TMPDIR'] : runtime_tmp
    end

    def findings
      @detected = {}
      inspect_browsers
      inspect_system_paths
      inspect_custom_tmp
      @detected.sort_by { |path, _reason| path }.map do |path, reason|
        { path: path, reason: reason }
      end
    end

    private

    def absolute_path(path)
      unless path.is_a?(String) && path.valid_encoding? && path.start_with?('/') &&
             !path.include?("\0") && path == File.expand_path(path) && path != '/'
        raise ArgumentError, 'audit root must be an absolute normalized path other than /'
      end
      path.dup.freeze
    end

    def record(path, reason)
      @detected[path] ||= reason
    end

    def ancestor_paths(path)
      paths = []
      parent = File.dirname(path)
      loop do
        paths.unshift(parent)
        break if parent == '/'

        parent = File.dirname(parent)
      end
      paths
    end

    def safe_stat(path)
      ancestor_paths(path).each do |parent|
        stat = File.lstat(parent)
        if stat.symlink? || !stat.directory?
          record(parent, 'Cannot verify audit scope: parent is a symlink or not a directory; inspect manually')
          return nil
        end
      end
      File.lstat(path)
    rescue Errno::ENOENT
      nil
    rescue SystemCallError, IOError => error
      record(path, "Cannot verify audit scope: #{error.class}; inspect manually")
      nil
    end

    def directory_children(path)
      stat = safe_stat(path)
      return [] unless stat
      unless stat.directory? && !stat.symlink?
        record(path, 'Cannot verify directory scope: symlink or non-directory; inspect manually')
        return []
      end

      names = Dir.children(path)
      after = safe_stat(path)
      unless after && [stat.dev, stat.ino, stat.ftype] == [after.dev, after.ino, after.ftype]
        record(path, 'Cannot verify directory scope: identity changed during audit; retry with applications stopped')
        return []
      end
      names.map { |name| File.join(path, name) }
    rescue SystemCallError, IOError => error
      record(path, "Cannot list audit directory: #{error.class}; inspect manually")
      []
    end

    def inspect_browsers
      BROWSER_DIRS.each do |browser|
        root = File.join(@home, 'Library/Application Support', browser)
        entries = directory_children(root)
        # Some browsers (notably Opera) use their root as the profile itself.
        inspect_profile(root) unless entries.empty? && !safe_stat(root)
        entries.each do |profile|
          named_profile = File.basename(profile).match?(PROFILE_NAME)
          stat = safe_stat(profile)
          next unless stat
          if stat.symlink?
            if named_profile
              record(profile, 'Cannot verify browser profile: symlink was not followed; inspect manually')
            end
          elsif stat.directory? && (named_profile || safe_stat(File.join(profile, 'Preferences')))
            inspect_profile(profile)
          end
        end
      end
    end

    def inspect_profile(profile)
      EXTENSION_PATHS.each do |relative|
        candidate(profile, relative, 'Claude browser extension data remains; remove the extension in this browser profile')
      end
      SITE_PATHS.each do |relative|
        candidate(profile, relative, 'Claude browser site storage remains; clear the matching site data in this browser profile')
      end
    end

    def candidate(root, relative, reason)
      path = File.join(root, relative)
      record(path, reason) if safe_stat(path)
    end

    def inspect_system_paths
      @system_roots.each do |root|
        THIRD_PARTY_PATHS.each do |relative|
          candidate(root, relative, 'Known third-party system data remains; administrator must review it')
        end
        MANAGED_PATHS.each do |relative|
          candidate(root, relative, 'System managed Claude configuration remains; administrator or MDM owner must review it')
        end
        DAEMON_PATHS.each do |relative|
          candidate(root, relative, 'Known third-party system service file remains; administrator must review it')
        end
        SYSTEM_HOST_DIRS.each do |directory|
          NATIVE_HOSTS.each do |host|
            candidate(root, File.join(directory, host),
                      'System Claude browser native host manifest remains; administrator must review it')
          end
        end
      end
    end

    def inspect_custom_tmp
      return if @runtime_tmp.nil? || @runtime_tmp == ''

      begin
        path = absolute_path(@runtime_tmp)
      rescue ArgumentError
        record(@runtime_tmp.to_s, 'Cannot verify CLAUDE_CODE_TMPDIR: expected an absolute normalized path; inspect manually')
        return
      end
      if safe_stat(path)
        record(path, 'Custom CLAUDE_CODE_TMPDIR exists; inspect temporary data manually; shared contents were not enumerated')
      end
    end
  end
end

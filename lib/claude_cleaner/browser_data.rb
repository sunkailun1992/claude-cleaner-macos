# frozen_string_literal: true

require_relative 'auditor'
require_relative 'planner'

module ClaudeCleaner
  # Plans only the exact website-origin IndexedDB directories selected by the
  # browser-data option. Names and lstat metadata are inspected; no browser
  # database, Preferences file, or target contents are opened.
  class BrowserData
    FAMILY_ROOTS = {
      'chrome' => ['Google/Chrome', 'Google/Chrome Beta', 'Google/Chrome Dev',
                   'Google/Chrome Canary', 'Google/ChromeForTesting'],
      'edge' => ['Microsoft Edge', 'Microsoft Edge Beta', 'Microsoft Edge Dev', 'Microsoft Edge Canary'],
      'brave' => ['BraveSoftware/Brave-Browser'],
      'chromium' => ['Chromium'], 'arc' => ['Arc/User Data'],
      'vivaldi' => ['Vivaldi'], 'opera' => ['com.operasoftware.Opera']
    }.freeze

    attr_reader :targets, :issues, :families

    def initialize(home:, uid: Process.uid)
      unless home.is_a?(String) && home.valid_encoding? && home.start_with?('/') &&
             !home.include?("\0") && home != '/' && home == File.expand_path(home)
        raise ArgumentError, 'home must be an absolute normalized path other than /'
      end
      raise ArgumentError, 'uid must be a nonnegative integer' unless uid.is_a?(Integer) && uid >= 0

      @home = home.dup.freeze
      @uid = uid
      @targets = []
      @issues = []
      @families = []
      home_stat = metadata(@home, nil)
      unless home_stat && home_stat.directory? && !home_stat.symlink?
        raise ArgumentError, 'home must be an existing directory without symlink parents'
      end

      Auditor::BROWSER_DIRS.each do |relative|
        family = FAMILY_ROOTS.find { |_name, roots| roots.include?(relative) }
        next unless family

        inspect_browser(File.join(@home, 'Library/Application Support', relative), family.first)
      end
      @targets.sort_by!(&:path)
      @issues = @issues.uniq.sort
      @families = @families.uniq.sort
    end

    private

    def issue(path, family, reason)
      @issues << "#{reason}: #{path}"
      @families << family if family
    end

    def identity(stat)
      [stat.dev, stat.ino, stat.ftype]
    end

    def same_metadata?(before, after)
      identity(before) == identity(after) && before.uid == after.uid
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

    # Every existing ancestor must be a real directory. Rechecks detect ordinary
    # replacements during inspection; portable Ruby path APIs are not an atomic
    # boundary against a concurrently malicious filesystem writer.
    def metadata(path, family, required: false)
      observed = false
      parents = ancestor_paths(path).map do |parent|
        stat = File.lstat(parent)
        unless stat.directory? && !stat.symlink?
          issue(parent, family, 'Cannot verify browser data; parent is a symlink or not a directory')
          return nil
        end
        [parent, stat]
      end
      stat = File.lstat(path)
      observed = true
      parents.each do |parent, expected|
        unless same_metadata?(expected, File.lstat(parent))
          issue(parent, family, 'Cannot verify browser data; parent identity changed during inspection')
          return nil
        end
      end
      after = File.lstat(path)
      unless same_metadata?(stat, after)
        issue(path, family, 'Cannot verify browser data; identity changed during inspection')
        return nil
      end
      stat
    rescue Errno::ENOENT
      issue(path, family, 'Cannot verify browser data; entry disappeared during inspection') if observed || required
      nil
    rescue SystemCallError, IOError => error
      issue(path, family, "Cannot verify browser data; #{error.class}")
      nil
    end

    def real_directory?(path, stat, family)
      unless stat.directory? && !stat.symlink?
        issue(path, family, 'Cannot verify browser data; symlink or non-directory was refused')
        return false
      end
      return true if stat.uid == @uid

      issue(path, family, 'Cannot verify browser data; owner UID differs from the current user')
      false
    end

    def unchanged?(path, expected, family)
      after = metadata(path, family, required: true)
      return false unless after
      return true if same_metadata?(expected, after)

      issue(path, family, 'Cannot verify browser data; directory identity changed during scan')
      false
    end

    def directory_children(path, stat, family)
      names = Dir.children(path)
      return nil unless unchanged?(path, stat, family)

      names.sort.map { |name| File.join(path, name) }
    rescue SystemCallError, IOError => error
      issue(path, family, "Cannot scan browser data directory; #{error.class}")
      nil
    end

    def inspect_browser(root, family)
      stat = metadata(root, family)
      return unless stat && real_directory?(root, stat, family)

      entries = directory_children(root, stat, family)
      return unless entries

      first_target = @targets.length
      inspect_profile(root, stat, family) if family == 'opera'
      entries.each { |path| inspect_profile_candidate(path, family) }
      @targets.slice!(first_target..-1) unless unchanged?(root, stat, family)
    end

    def inspect_profile_candidate(path, family)
      named_profile = File.basename(path).match?(Auditor::PROFILE_NAME)
      stat = metadata(path, family, required: named_profile)
      return unless stat

      if named_profile
        inspect_profile(path, stat, family)
      elsif stat.directory? && !stat.symlink?
        preferences = metadata(File.join(path, 'Preferences'), family)
        inspect_profile(path, stat, family) if preferences && preferences.file? && !preferences.symlink?
      end
      # Unrelated root entries, including Chromium's normal Singleton* symlinks,
      # are not profiles and do not produce errors merely because they are links.
    end

    def inspect_profile(profile, profile_stat, family)
      return unless real_directory?(profile, profile_stat, family)

      indexeddb = File.join(profile, 'IndexedDB')
      stat = metadata(indexeddb, family)
      return unless stat && real_directory?(indexeddb, stat, family)

      first_target = @targets.length
      Auditor::SITE_PATHS.each { |relative| inspect_target(File.join(profile, relative), family) }
      stable_storage = unchanged?(indexeddb, stat, family)
      stable_profile = unchanged?(profile, profile_stat, family)
      @targets.slice!(first_target..-1) unless stable_storage && stable_profile
    end

    def inspect_target(path, family)
      stat = metadata(path, family)
      return unless stat && real_directory?(path, stat, family)

      @families << family
      @targets << Target.new(path: path.freeze, reason: 'Claude website origin IndexedDB storage'.freeze,
                             identity: identity(stat).freeze).freeze
    end
  end
end

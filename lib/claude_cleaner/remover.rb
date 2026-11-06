# frozen_string_literal: true

module ClaudeCleaner
  # Deletion is confined to explicit roots and never follows a leaf symlink.
  # Every destructive operation rechecks the identities of its ancestors and
  # entry. This detects ordinary application writes and many rename races.
  # Ruby 2.6's portable path APIs cannot make those checks and unlink/rmdir
  # atomic: stop Claude first, and do not run against directories concurrently
  # controlled by a malicious process. This is not a hostile-process sandbox.
  class Remover
    class SafetyError < StandardError; end

    def initialize(allowed_roots:, protected_paths: [])
      unless allowed_roots.is_a?(Array) && !allowed_roots.empty?
        raise ArgumentError, 'allowed_roots must be a nonempty array'
      end

      @allowed_roots = allowed_roots.map do |root|
        validate_path!(root)
        raise ArgumentError, 'the filesystem root cannot be an allowed root' if root == '/'

        root.dup.freeze
      end.uniq.freeze
      @protected_paths = protected_paths.map do |path|
        validate_path!(path)
        path.dup.freeze
      end.freeze
    end

    def remove(target)
      path = target.respond_to?(:path) ? target.path : nil
      validate_path!(path)
      path = path.dup.freeze
      validate_scope!(path)
      expected = target.respond_to?(:identity) ? target.identity : nil
      validate_identity!(expected)
      expected = expected.dup.freeze

      initial = inspect_target(path)
      return { path: path, status: 'absent' } unless initial

      stat, parents = initial
      assert_identity!(path, expected, stat)
      remove_entry(path, expected, parents)
      { path: path, status: 'removed' }
    rescue SafetyError, SystemCallError, IOError, ArgumentError => error
      { path: path, status: 'failed', error: "#{error.class}: #{error.message}" }
    end

    private

    def validate_path!(path)
      unless path.is_a?(String) && path.valid_encoding? &&
             path.start_with?('/') && !path.include?("\0") &&
             path == File.expand_path(path)
        raise ArgumentError, 'path must be an absolute, normalized path without dot components'
      end
    end

    def validate_scope!(path)
      if path == File.expand_path(Dir.home) ||
         @allowed_roots.any? { |root| root == path || root.start_with?(path + '/') } ||
         !@allowed_roots.any? { |root| path.start_with?(root + '/') }
        raise SafetyError, "path is not a strict descendant of an allowed root: #{path}"
      end
    end

    def validate_identity!(expected)
      unless expected.is_a?(Array) && expected.length == 3 &&
             expected[0].is_a?(Integer) && expected[1].is_a?(Integer) &&
             expected[2].is_a?(String)
        raise SafetyError, 'target must include its planned lstat identity'
      end
    end

    def identity(stat)
      [stat.dev, stat.ino, stat.ftype]
    end

    def assert_identity!(path, expected, stat)
      return if identity(stat) == expected

      raise SafetyError, "path identity changed since planning or inspection: #{path}"
    end

    def assert_directory!(path, stat)
      return if stat.directory? && !stat.symlink?

      raise SafetyError, "parent is not a real directory: #{path}"
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

    # ENOENT is an idempotent result only during the initial inspection.
    # A disappearing entry during traversal is a failure, not a complete wipe.
    def inspect_target(path)
      parents = {}
      ancestor_paths(path).each do |parent|
        stat = File.lstat(parent)
        assert_directory!(parent, stat)
        parents[parent] = identity(stat).freeze
      end
      verify_parents!(parents)
      stat = File.lstat(path)
      verify_parents!(parents)
      [stat, parents]
    rescue Errno::ENOENT
      nil
    end

    def verify_parents!(parents)
      parents.each do |path, expected|
        stat = File.lstat(path)
        assert_directory!(path, stat)
        assert_identity!(path, expected, stat)
      end
    end

    def checked_entry(path, expected, parents)
      verify_parents!(parents)
      stat = File.lstat(path)
      assert_identity!(path, expected, stat)
      verify_parents!(parents)
      stat
    end

    def remove_entry(path, expected, parents)
      stat = checked_entry(path, expected, parents)
      assert_protection!(path, stat.directory?)
      if stat.directory?
        if stat.dev != parents.fetch(File.dirname(path))[0]
          raise SafetyError, "refused to cross a filesystem mount: #{path}"
        end
        child_parents = parents.merge(path => expected)
        children = Dir.children(path)
        verify_parents!(child_parents)
        children.each do |name|
          child = File.join(path, name)
          verify_parents!(child_parents)
          child_identity = identity(File.lstat(child))
          remove_entry(child, child_identity, child_parents)
        end
        checked_entry(path, expected, parents)
        assert_protection!(path, true)
        Dir.rmdir(path)
      else
        # lstat makes symlinks leaves, including dangling and cyclic links.
        checked_entry(path, expected, parents)
        File.unlink(path)
      end
    end

    def assert_protection!(path, descendants)
      @protected_paths.each do |protected|
        next unless protected == path || (descendants && protected.start_with?(path + '/'))
        begin
          File.lstat(protected)
          raise SafetyError, "protected data appeared or remains inside target: #{protected}"
        rescue Errno::ENOENT
          # A protected name that does not exist is checked again for each
          # descendant and before rmdir; its later appearance aborts deletion.
        end
      end
    end
  end
end

# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/claude_cleaner/planner'
require_relative '../lib/claude_cleaner/remover'

class ProtectionTest < Minitest::Test
  def test_protected_directory_created_after_plan_is_preserved
    Dir.mktmpdir('cleaner protection') do |dir|
      root = File.realpath(dir)
      config = File.join(root, '.claude')
      FileUtils.mkdir_p(config)
      File.write(File.join(config, 'history.jsonl'), 'fixture')
      target = ClaudeCleaner::Planner.new(home: root).targets.find { |t| t.path == config }
      worktrees = File.join(config, 'worktrees')
      FileUtils.mkdir_p(worktrees)
      valuable = File.join(worktrees, 'valuable.txt')
      File.write(valuable, 'must survive')
      remover = ClaudeCleaner::Remover.new(allowed_roots: [root], protected_paths: [worktrees])
      result = remover.remove(target)
      assert_equal 'failed', result[:status]
      assert_equal 'must survive', File.read(valuable)
    end
  end

  def test_configuration_leaf_symlink_is_unlinked_without_inspecting_its_destination
    Dir.mktmpdir('cleaner leaf') do |dir|
      root = File.realpath(dir)
      outside = File.join(root, 'outside')
      config = File.join(root, '.claude')
      FileUtils.mkdir_p(File.join(outside, 'security'))
      valuable = File.join(outside, 'security', 'valuable.txt')
      File.write(valuable, 'must survive')
      File.symlink(outside, config)
      target = ClaudeCleaner::Planner.new(home: root).targets.find { |t| t.path == config }
      remover = ClaudeCleaner::Remover.new(allowed_roots: [root], protected_paths: [File.join(config, 'security')])
      assert_equal 'removed', remover.remove(target)[:status]
      refute File.symlink?(config)
      assert_equal 'must survive', File.read(valuable)
    end
  end

  def test_recursive_delete_refuses_a_different_filesystem
    Dir.mktmpdir('cleaner mount') do |dir|
      root = File.realpath(dir)
      config = File.join(root, '.claude')
      child = File.join(config, 'mounted-volume')
      FileUtils.mkdir_p(child)
      valuable = File.join(child, 'valuable.txt')
      File.write(valuable, 'must survive')
      target = ClaudeCleaner::Planner.new(home: root).targets.find { |t| t.path == config }
      original = File.method(:lstat)
      lstat = proc do |path|
        stat = original.call(path)
        if path == child
          device = stat.dev + 1
          stat.define_singleton_method(:dev) { device }
        end
        stat
      end
      result = File.stub(:lstat, lstat) { ClaudeCleaner::Remover.new(allowed_roots: [root]).remove(target) }
      assert_equal 'failed', result[:status]
      assert_equal 'must survive', File.read(valuable)
    end
  end
end

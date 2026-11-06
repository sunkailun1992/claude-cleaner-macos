# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/claude_cleaner/remover'

class RemoverTest < Minitest::Test
  PlannedTarget = Struct.new(:path, :reason, :identity, keyword_init: true)

  def setup
    @temporary = Dir.mktmpdir('claude cleaner remover ')
    # macOS /var and /tmp are links; the remover deliberately rejects them.
    @temporary = File.realpath(@temporary)
    @root = File.join(@temporary, 'user home')
    FileUtils.mkdir_p(@root)
    @remover = ClaudeCleaner::Remover.new(allowed_roots: [@root])
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary && File.exist?(@temporary)
  end

  def test_removes_a_planned_file
    path = write('claude.json', '{}')

    result = @remover.remove(plan(path))

    assert_equal 'removed', result[:status]
    assert_equal path, result[:path]
    refute File.exist?(path)
  end

  def test_recursively_removes_a_directory_without_changing_siblings
    path = File.join(@root, '.claude')
    FileUtils.mkdir_p(File.join(path, 'nested'))
    File.write(File.join(path, 'nested', 'session'), 'private fixture')
    sibling = write('keep', 'keep')

    result = @remover.remove(plan(path))

    assert_equal 'removed', result[:status]
    refute File.exist?(path)
    assert_equal 'keep', File.read(sibling)
  end

  def test_removes_paths_with_spaces_and_chinese_characters
    path = write('缓存 目录/Claude 配置.json', 'fixture')

    assert_equal 'removed', @remover.remove(plan(path))[:status]
    refute File.exist?(path)
  end

  def test_repeated_removal_is_absent
    path = write('once', 'fixture')
    target = plan(path)
    assert_equal 'removed', @remover.remove(target)[:status]

    assert_equal({ path: path, status: 'absent' }, @remover.remove(target))
  end

  def test_missing_parent_is_absent
    path = write('parent/file', 'fixture')
    target = plan(path)
    FileUtils.remove_entry(File.dirname(path))

    assert_equal 'absent', @remover.remove(target)[:status]
  end

  def test_only_unlinks_a_leaf_directory_symlink
    outside = File.join(@temporary, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'keep'), 'outside')
    link = File.join(@root, '.claude')
    File.symlink(outside, link)

    assert_equal 'removed', @remover.remove(plan(link))[:status]
    refute File.symlink?(link)
    assert_equal 'outside', File.read(File.join(outside, 'keep'))
  end

  def test_only_unlinks_a_broken_leaf_symlink
    path = File.join(@root, 'broken')
    File.symlink(File.join(@temporary, 'does-not-exist'), path)

    assert_equal 'removed', @remover.remove(plan(path))[:status]
    refute File.symlink?(path)
  end

  def test_recursive_removal_does_not_follow_internal_symlinks
    outside = File.join(@temporary, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'keep'), 'outside')
    path = File.join(@root, '.claude')
    FileUtils.mkdir_p(path)
    File.symlink(outside, File.join(path, 'linked-directory'))
    File.symlink(File.join(outside, 'keep'), File.join(path, 'linked-file'))
    File.symlink(path, File.join(path, 'cycle'))

    assert_equal 'removed', @remover.remove(plan(path))[:status]
    refute File.exist?(path)
    assert_equal 'outside', File.read(File.join(outside, 'keep'))
  end

  def test_rejects_a_symlink_parent_even_when_target_identity_matches
    actual = File.join(@root, 'actual')
    FileUtils.mkdir_p(actual)
    leaf = File.join(actual, 'config')
    File.write(leaf, 'keep')
    File.symlink(actual, File.join(@root, 'link'))
    target = plan(File.join(@root, 'link', 'config'))

    assert_failed(@remover.remove(target))
    assert_equal 'keep', File.read(leaf)
  end

  def test_rejects_an_allowed_root_that_is_a_symlink
    actual = File.join(@temporary, 'actual')
    FileUtils.mkdir_p(actual)
    File.write(File.join(actual, 'config'), 'keep')
    link = File.join(@temporary, 'root-link')
    File.symlink(actual, link)
    remover = ClaudeCleaner::Remover.new(allowed_roots: [link])

    assert_failed(remover.remove(plan(File.join(link, 'config'))))
    assert_equal 'keep', File.read(File.join(actual, 'config'))
  end

  def test_rejects_target_replaced_after_planning
    path = write('replace-me', 'old')
    target = plan(path)
    File.rename(path, File.join(@root, 'old-file'))
    File.write(path, 'new')

    assert_failed(@remover.remove(target))
    assert_equal 'new', File.read(path)
  end

  def test_rejects_target_replaced_with_symlink_after_planning
    path = write('replace-me', 'old')
    target = plan(path)
    outside = File.join(@temporary, 'outside-file')
    File.write(outside, 'outside')
    File.rename(path, File.join(@root, 'old-file'))
    File.symlink(outside, path)

    assert_failed(@remover.remove(target))
    assert File.symlink?(path)
    assert_equal 'outside', File.read(outside)
  end

  def test_rejects_removing_an_allowed_root
    assert_failed(@remover.remove(plan(@root)))
    assert File.directory?(@root)
  end

  def test_rejects_the_real_user_home_before_any_filesystem_access
    home = File.expand_path(Dir.home)
    remover = ClaudeCleaner::Remover.new(allowed_roots: [File.dirname(home)])
    target = PlannedTarget.new(path: home, identity: [0, 0, 'directory'])
    forbidden = proc { |_path| flunk('must reject user home before inspecting or removing it') }

    result = File.stub(:lstat, forbidden) { remover.remove(target) }

    assert_failed(result)
  end

  def test_rejects_an_ancestor_of_another_allowed_root
    path = write('group/protected-root/keep', 'keep')
    protected_root = File.dirname(path)
    directory = File.dirname(protected_root)
    remover = ClaudeCleaner::Remover.new(allowed_roots: [@root, protected_root])

    assert_failed(remover.remove(plan(directory)))
    assert_equal 'keep', File.read(path)
  end

  def test_rejects_files_outside_allowed_roots
    path = File.join(@temporary, 'outside')
    File.write(path, 'keep')

    assert_failed(@remover.remove(plan(path)))
    assert_equal 'keep', File.read(path)
  end

  def test_does_not_confuse_a_shared_prefix_for_a_descendant
    outside = File.join(@temporary, 'user home-other')
    FileUtils.mkdir_p(outside)
    path = File.join(outside, 'config')
    File.write(path, 'keep')

    assert_failed(@remover.remove(plan(path)))
    assert_equal 'keep', File.read(path)
  end

  def test_rejects_untrusted_path_spellings_before_deletion
    file = write('keep', 'keep')
    target = plan(file)
    ['/', 'home', '..', '', '.', nil, 'relative/file',
     File.join(@root, 'parent', '..', 'keep'),
     File.join(@root, '.', 'keep'), file + '/', "#{file}\0suffix"].each do |path|
      invalid = PlannedTarget.new(path: path, identity: target.identity)
      assert_failed(@remover.remove(invalid), path.inspect)
    end
    assert_equal 'keep', File.read(file)
  end

  def test_rejects_missing_or_malformed_plan_identity
    file = write('keep', 'keep')
    [nil, [], ['device', 'inode', 'file'], [1, 2], [1, 2, 'file', 4]].each do |identity|
      assert_failed(@remover.remove(PlannedTarget.new(path: file, identity: identity)))
    end
    assert_equal 'keep', File.read(file)
  end

  def test_supports_multiple_explicit_roots
    other = File.join(@temporary, 'Applications')
    FileUtils.mkdir_p(other)
    path = File.join(other, 'Claude.app')
    File.write(path, 'fixture')
    remover = ClaudeCleaner::Remover.new(allowed_roots: [@root, other])

    assert_equal 'removed', remover.remove(plan(path))[:status]
    refute File.exist?(path)
  end

  def test_rejects_a_filesystem_root_as_an_authorization_root
    assert_raises(ArgumentError) { ClaudeCleaner::Remover.new(allowed_roots: ['/']) }
  end

  def test_rejects_relative_authorization_roots
    assert_raises(ArgumentError) { ClaudeCleaner::Remover.new(allowed_roots: ['relative']) }
  end

  def test_reports_permission_errors_and_keeps_the_file
    path = write('locked', 'keep')
    target = plan(path)
    denied = proc { |candidate| raise Errno::EACCES, candidate }

    result = File.stub(:unlink, denied) { @remover.remove(target) }

    assert_failed(result)
    assert_match(/EACCES|Permission denied/, result[:error])
    assert_equal 'keep', File.read(path)
  end

  def test_reports_directory_removal_errors
    path = File.join(@root, 'locked-directory')
    FileUtils.mkdir_p(path)
    target = plan(path)
    denied = proc { |candidate| raise Errno::EPERM, candidate }

    result = Dir.stub(:rmdir, denied) { @remover.remove(target) }

    assert_failed(result)
    assert File.directory?(path)
  end

  def test_reports_directory_listing_errors
    path = File.join(@root, 'unreadable-directory')
    FileUtils.mkdir_p(path)
    target = plan(path)
    denied = proc { |candidate| raise Errno::EACCES, candidate }

    result = Dir.stub(:children, denied) { @remover.remove(target) }

    assert_failed(result)
    assert File.directory?(path)
  end

  def test_stops_if_target_becomes_a_link_during_recursion
    path = write('directory/keep', 'planned')
    directory = File.dirname(path)
    target = plan(directory)
    outside = File.join(@temporary, 'outside-directory')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'keep'), 'outside')
    original_children = Dir.method(:children)
    replace_after_listing = proc do |candidate|
      children = original_children.call(candidate)
      if candidate == directory
        File.rename(directory, directory + '-old')
        File.symlink(outside, directory)
      end
      children
    end

    result = Dir.stub(:children, replace_after_listing) { @remover.remove(target) }

    assert_failed(result)
    assert_equal 'outside', File.read(File.join(outside, 'keep'))
    assert_equal 'planned', File.read(File.join(directory + '-old', 'keep'))
  end

  def test_stops_if_parent_identity_changes_during_recursion
    path = write('parent/directory/keep', 'planned')
    directory = File.dirname(path)
    parent = File.dirname(directory)
    target = plan(directory)
    original_children = Dir.method(:children)
    replace_after_listing = proc do |candidate|
      children = original_children.call(candidate)
      if candidate == directory
        File.rename(parent, parent + '-old')
        FileUtils.mkdir_p(parent)
        File.rename(File.join(parent + '-old', 'directory'), directory)
      end
      children
    end

    result = Dir.stub(:children, replace_after_listing) { @remover.remove(target) }

    assert_failed(result)
    assert_equal 'planned', File.read(path)
  end

  private

  def write(relative, contents)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  def plan(path)
    stat = File.lstat(path)
    PlannedTarget.new(path: path, reason: 'test fixture',
                      identity: [stat.dev, stat.ino, stat.ftype])
  end

  def assert_failed(result, message = nil)
    assert_equal 'failed', result[:status], message
    assert_kind_of String, result[:error], message
    refute_empty result[:error], message
  end
end

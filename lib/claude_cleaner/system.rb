# frozen_string_literal: true
require 'json'
require 'open3'

module ClaudeCleaner
  # Commands never run through a shell. Only this runner's process group is
  # stopped on timeout; no application processes are killed by the cleaner.
  class CommandRunner
    def initialize(timeout: 60)
      @timeout = timeout
    end

    def call(argv)
      env = { 'LC_ALL' => 'C', 'HOMEBREW_NO_AUTO_UPDATE' => '1',
              'HOMEBREW_NO_INSTALL_CLEANUP' => '1', 'NODE_OPTIONS' => nil,
              'NODE_PATH' => nil, 'RUBYOPT' => nil, 'BASH_ENV' => nil,
              'DYLD_INSERT_LIBRARIES' => nil, 'DYLD_LIBRARY_PATH' => nil }
      # npm uses env node; prefer the selected installation's bin directory.
      env['PATH'] = [File.dirname(argv.first), '/usr/bin', '/bin', '/usr/sbin',
                     '/sbin', '/opt/homebrew/bin', '/usr/local/bin'].uniq.join(':')
      Open3.popen3(env, *argv, pgroup: true) do |stdin, stdout, stderr, waiter|
        stdin.close
        output_limit = 16 * 1024 * 1024
        readers = [stdout, stderr].map { |io| Thread.new { io.read(output_limit + 1).to_s } }
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
        complete = waiter.join([deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max)
        complete &&= readers.all? { |thread| thread.join([deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max) }
        unless complete
          begin
            Process.kill('TERM', -waiter.pid)
            waiter.join(0.2)
            # The parent may have exited while descendants still own pipes.
            Process.kill('KILL', -waiter.pid)
          rescue Errno::ESRCH
            # The process group is already gone.
          end
          waiter.join(1)
          readers.each { |thread| thread.join(0.2) || thread.kill }
          return { status: 124, stdout: '', stderr: 'command timed out' }
        end
        if readers.any? { |thread| thread.value.bytesize > output_limit }
          return { status: 125, stdout: '', stderr: 'command output exceeded limit' }
        end
        { status: waiter.value.exitstatus || 128, stdout: readers[0].value,
          stderr: readers[1].value }
      end
    rescue SystemCallError, IOError => e
      { status: 127, stdout: '', stderr: e.class.name }
    end
  end

  class MacSystem
    CASKS = %w[claude claude-code claude-code@latest].freeze
    KEYCHAIN_SERVICES = ['Claude Safe Storage', 'Claude-3p Safe Storage',
                         'Claude Code', 'Claude Code-credentials'].freeze
    USER_LABELS = %w[local.claude-update local.claude-bodyguard].freeze
    SYSTEM_LABELS = %w[local.claude-bodyguard local.tz-watchdog local.claude-update].freeze
    BROWSER_APPS = [
      'Google Chrome', 'Google Chrome Beta', 'Google Chrome Dev', 'Google Chrome Canary',
      'Google Chrome for Testing', 'Google ChromeForTesting', 'Microsoft Edge',
      'Microsoft Edge Beta', 'Microsoft Edge Dev', 'Microsoft Edge Canary',
      'Brave Browser', 'Brave Browser Beta', 'Brave Browser Nightly', 'Chromium',
      'Arc', 'Vivaldi', 'Vivaldi Snapshot', 'Opera', 'Opera Beta', 'Opera Developer', 'Opera GX'
    ].freeze
    BROWSER_EXECUTABLE = %r{/(?:#{BROWSER_APPS.map { |name| Regexp.escape(name) }.join('|')})\.app/Contents/}.freeze

    def initialize(home:, uid:, runner: CommandRunner.new, brew_paths: nil, npm_paths: nil)
      @home, @uid, @runner = home, uid, runner
      @brew_paths = brew_paths || executable_paths(%w[/opt/homebrew/bin/brew /usr/local/bin/brew])
      @npm_paths = npm_paths || executable_paths([
        '/opt/homebrew/bin/npm', '/usr/local/bin/npm',
        File.join(home, '.volta/bin/npm')
      ] + Dir.glob(File.join(home, '.nvm/versions/node/*/bin/npm')) +
        Dir.glob(File.join(home, '.local/share/fnm/node-versions/*/installation/bin/npm')) +
        Dir.glob(File.join(home, '.asdf/installs/nodejs/*/bin/npm')))
    end

    def snapshot
      @actions, @issues, @processes, @prefixes = [], [], [], []
      inspect_processes
      inspect_packages
      inspect_keychain
      inspect_services
      { actions: @actions, issues: @issues, processes: @processes, prefixes: @prefixes.uniq }
    end

    def execute(action)
      result = @runner.call(action.fetch(:argv))
      success = result[:status] == 0 || (action[:category] == 'keychain' && result[:status] == 44)
      { category: action[:category], reason: action[:reason],
        status: success ? 'removed' : 'failed', exit_status: result[:status] }
    end

    def browser_processes
      result = @runner.call(['/bin/ps', '-ww', '-axo', 'pid=,uid=,comm='])
      unless result[:status] == 0
        return { processes: [], issues: ['browser process inventory failed; site data was not verified'] }
      end
      processes = result[:stdout].each_line.each_with_object([]) do |line, found|
        pid, uid, executable = line.strip.split(/\s+/, 3)
        next unless uid.to_i == @uid && executable && executable.match?(BROWSER_EXECUTABLE)
        found << { pid: pid.to_i, executable: executable, kind: 'browser' }
      end
      { processes: processes, issues: [] }
    end

    private

    def executable_paths(paths)
      seen = {}
      paths.select do |path|
        next false unless File.file?(path) && File.executable?(path)
        real = File.realpath(path)
        next false if seen[real]
        seen[real] = true
      end
    end

    def action(category, argv, reason)
      @actions << { category: category, argv: argv, reason: reason }
    end

    def inspect_processes
      result = @runner.call(['/bin/ps', '-ww', '-axo', 'pid=,uid=,comm='])
      if result[:status] != 0
        @issues << 'process inventory failed; close Claude and retry'
        return
      end
      result[:stdout].each_line do |line|
        pid, uid, executable = line.strip.split(/\s+/, 3)
        next unless uid.to_i == @uid && executable
        desktop = executable.match?(%r{/(?:Claude|Claude-3p)\.app/Contents/})
        switcher = executable.match?(%r{/(?:Claude切换器|Claude Switcher|Claude-Switcher|claude-switcher)\.app/Contents/})
        code = executable.start_with?(File.join(@home, '.local/share/claude/')) ||
               executable.match?(%r{/(?:@anthropic-ai/claude-code/|claude-code/versions/)}) ||
               executable.match?(%r{/Caskroom/claude-code(?:@latest)?/[^/]+/claude\z}) ||
               executable == File.join(@home, '.local/bin/claude') ||
               executable.match?(%r{/bin/claude\z})
        @processes << { pid: pid.to_i, executable: executable } if desktop || code || switcher
      end
      # ps comm is just node for npm installations. Inspect argv in memory,
      # keeping only the matched PID and a constant description in reports.
      args = @runner.call(['/bin/ps', '-ww', '-axo', 'pid=,uid=,args='])
      if args[:status] != 0
        @issues << 'Claude Code argv process inventory failed'
        return
      end
      args[:stdout].each_line do |line|
        pid, uid, command = line.strip.split(/\s+/, 3)
        next unless uid.to_i == @uid && command
        node = command.match?(%r{\A(?:\S*/)?(?:node|bun)(?:\s+--[A-Za-z0-9_=./-]+)*\s+.*?/@anthropic-ai/claude-code/(?:cli\.js|bin/claude)(?:\s|\z)})
        next unless node
        @processes << { pid: pid.to_i, executable: 'Claude Code (npm/node)' } unless @processes.any? { |p| p[:pid] == pid.to_i }
      end
    end

    def inspect_packages
      @brew_paths.each do |brew|
        result = @runner.call([brew, 'list', '--cask', '--versions'])
        if result[:status] != 0
          @issues << "Homebrew inventory failed: #{brew}"
          next
        end
        result[:stdout].each_line do |line|
          name = line.split.first
          next unless CASKS.include?(name)
          action('package', [brew, 'uninstall', '--cask', '--force', name], "Homebrew #{name}")
        end
      end
      @npm_paths.each do |npm|
        prefix_result = @runner.call([npm, 'prefix', '--global'])
        prefix = prefix_result[:stdout].strip
        unless prefix_result[:status] == 0 && prefix.start_with?('/') && prefix != '/' &&
               !prefix.include?("\n") && !prefix.include?("\0") && prefix == File.expand_path(prefix)
          @issues << "npm prefix inventory failed: #{npm}"
          next
        end
        result = @runner.call([npm, 'list', '--global', '--prefix', prefix, '--depth=0', '--json'])
        begin
          data = JSON.parse(result[:stdout])
          raise JSON::ParserError, 'inventory failed' if result[:status] != 0
          if data.fetch('dependencies', {}).key?('@anthropic-ai/claude-code')
            @prefixes << prefix
            action('package', [npm, 'uninstall', '--global', '--prefix', prefix, '--ignore-scripts', '--no-audit', '--no-fund',
                               '@anthropic-ai/claude-code'], "npm @anthropic-ai/claude-code (#{prefix})")
          end
        rescue JSON::ParserError, TypeError, NoMethodError
          @issues << "npm inventory failed: #{npm}"
        end
      end
    end

    def inspect_keychain
      # No -d/-g/-w: read service metadata, never password/token values. Keep all
      # metadata in process memory only; reports contain matching service names.
      result = @runner.call(['/usr/bin/security', 'dump-keychain'])
      if result[:status] != 0
        @issues << 'keychain inventory failed; unlock your login keychain and retry'
        return
      end
      result[:stdout].scan(/"svce"\s*<blob>\s*=\s*"([^"\r\n]+)"/).flatten.each do |service|
        next unless KEYCHAIN_SERVICES.include?(service) ||
                    service.match?(/\AClaude Code-credentials-[a-fA-F0-9]{8,64}\z/)
        action('keychain', ['/usr/bin/security', 'delete-generic-password', '-s', service], service)
      end
    end

    def inspect_services
      USER_LABELS.each do |label|
        domain = "gui/#{@uid}/#{label}"
        result = @runner.call(['/bin/launchctl', 'print', domain])
        if result[:status] == 0 && !result[:stdout].empty?
          action('service', ['/bin/launchctl', 'bootout', domain], domain)
        elsif ![0, 113].include?(result[:status])
          @issues << "launchd inventory failed: #{domain}"
        end
      end
      SYSTEM_LABELS.each do |label|
        domain = "system/#{label}"
        result = @runner.call(['/bin/launchctl', 'print', domain])
        if result[:status] == 0 && !result[:stdout].empty?
          @issues << "administrator cleanup required for third-party service #{domain}; see docs/coverage.md"
        elsif ![0, 113].include?(result[:status])
          @issues << "system launchd inventory failed: #{domain}"
        end
      end
    end
  end
end

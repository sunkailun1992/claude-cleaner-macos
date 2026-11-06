# frozen_string_literal: true
require 'json'
require 'optparse'
require 'time'
require_relative 'planner'
require_relative 'remover'
require_relative 'system'
require_relative 'auditor'
require_relative 'browser_data'

module ClaudeCleaner
  VERSION = '0.1.1'

  class CLI
    def initialize(home: File.realpath(Dir.home), app_roots: nil, prefixes: nil,
                   runtime_roots: nil, runtime_runner: nil, system: nil, auditor: nil, uid: Process.uid,
                   platform: RUBY_PLATFORM, out: $stdout, input: $stdin, env: ENV)
      @home, @uid, @platform, @out, @input, @env = home, uid, platform, out, input, env
      @app_roots = app_roots || ['/Applications', File.join(home, 'Applications')]
      @prefixes = prefixes || ['/opt/homebrew', '/usr/local']
      @runtime_issues = []
      @runtime_runner = runtime_runner || CommandRunner.new(timeout: 5)
      @runtime_roots = runtime_roots || discover_runtime_roots
      @system = system || MacSystem.new(home: home, uid: uid)
      @auditor = auditor || Auditor.new(home: home, runtime_tmp: env.fetch('CLAUDE_CODE_TMPDIR', ''))
    end

    def run(argv)
      options = { projects: [], config_dirs: [] }
      parser = option_parser(options)
      parser.parse!(argv)
      raise OptionParser::InvalidArgument, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      return write_help(parser) if options[:help]
      return write_version if options[:version]
      raise OptionParser::InvalidArgument, 'macOS only' unless @platform.include?('darwin')
      raise OptionParser::InvalidArgument, 'run as the current user, never with sudo' if @uid.zero?
      raise OptionParser::InvalidArgument, '--yes requires --apply' if options[:yes] && !options[:apply]
      raise OptionParser::InvalidArgument, '--apply and --verify are exclusive' if options[:apply] && options[:verify]
      custom = @env['CLAUDE_CONFIG_DIR']
      options[:config_dirs] << custom if custom && !custom.empty?
      plan = inventory(options)
      report = base_report(options, plan)
      if options[:verify]
        report[:status] = clean?(plan) ? 'known_scope_clean' : 'remaining'
        report[:remaining] = public_plan(plan)
        return finish(report, options, clean?(plan) ? 0 : 1)
      end
      unless options[:apply]
        report[:status] = 'preview'
        return finish(report, options, plan[:issues].empty? ? 0 : 1)
      end
      unless options[:yes]
        raise OptionParser::InvalidArgument, 'interactive confirmation cannot use --json; add --yes' if options[:json]
        display(report)
        @out.puts '永久删除以上 Claude 数据；不会创建账号或会话备份。输入 DELETE CLAUDE 确认：'
        unless @input.gets.to_s.strip == 'DELETE CLAUDE'
          @out.puts '已取消，未执行清理。'
          return 2
        end
      end
      unless plan[:issues].empty? && plan[:processes].empty?
        report[:status] = 'blocked'
        return finish(report, options, 1)
      end
      # Re-inventory after the user reads the preview. A changed plan needs a
      # fresh confirmation, rather than silently expanding the deletion scope.
      fresh = inventory(options)
      unless signature(plan) == signature(fresh)
        report[:status] = 'changed_since_preview'
        report[:remaining] = public_plan(fresh)
        return finish(report, options, 1)
      end
      results = plan[:actions].map { |a| @system.execute(a) }
      if results.any? { |r| r[:status] == 'failed' }
        report[:status], report[:results] = 'incomplete', results
        report[:remaining] = public_plan(inventory(options))
        return finish(report, options, 1)
      end
      if options[:include_browser_site_data]
        guard = @system.browser_processes
        unless guard[:processes].empty? && guard[:issues].empty?
          report[:status] = results.empty? ? 'blocked' : 'incomplete'
          report[:results], report[:remaining] = results, public_plan(inventory(options))
          return finish(report, options, 1)
        end
      end
      roots = [@home] + @app_roots + plan[:prefixes] + @runtime_roots + options[:projects]
      roots = roots.uniq.reject { |root| roots.any? { |other| root != other && root.start_with?(other + '/') } }
      configs = plan[:configuration_roots]
      protected = configs.map { |config| File.join(config, 'worktrees') }
      protected.concat(configs.map { |config| File.join(config, 'security') }) unless options[:include_shared_security]
      remover = Remover.new(allowed_roots: roots.select { |root| File.directory?(root) && !File.symlink?(root) },
                            protected_paths: protected.uniq)
      browser_paths = plan[:browser_targets].map(&:path)
      plan[:targets].each do |target|
        if browser_paths.include?(target.path)
          guard = @system.browser_processes
          unless guard[:processes].empty? && guard[:issues].empty?
            results << {path: target.path, status: 'failed', error: 'Browser process started or process inventory failed before deletion'}
            break
          end
        end
        results << remover.remove(target)
      end
      remaining = inventory(options)
      report[:results], report[:remaining] = results, public_plan(remaining)
      success = clean?(remaining) && results.none? { |r| r[:status] == 'failed' }
      report[:status] = success ? 'known_scope_clean' : 'incomplete'
      finish(report, options, success ? 0 : 1)
    rescue OptionParser::ParseError, ArgumentError => e
      @out.puts "错误：#{e.message}"
      2
    rescue SystemCallError, IOError => e
      @out.puts "无法完成盘点：#{e.class}（未宣称清理成功）"
      1
    end

    private

    def option_parser(options)
      OptionParser.new do |p|
        p.banner = 'Usage: ./claude-cleaner [--apply [--yes] | --verify] [options]'
        p.separator '默认仅 preview。永久删除需要 --apply；不上传数据，不提权。'
        p.on('--apply', '执行清理，默认要求交互确认') { options[:apply] = true }
        p.on('--yes', '与 --apply 同用，显式跳过交互确认') { options[:yes] = true }
        p.on('--verify', '只检查已知残留；有残留退出 1') { options[:verify] = true }
        p.on('--json', 'JSON 报告到标准输出（可能包含本机路径，请勿直接公开）') { options[:json] = true }
        p.on('--project PATH', '只纳入指定项目的 .claude，保留 worktrees；可重复') { |v| options[:projects] << File.expand_path(v) }
        p.on('--config-dir PATH', '额外 Claude 专属配置目录；可重复') { |v| options[:config_dirs] << v }
        p.on('--include-project-instructions', '同时删除所指定项目的 CLAUDE.md / CLAUDE.local.md') { options[:include_project_instructions] = true }
        p.on('--include-cowork-files', '同时删除 ~/Claude 和 ~/Documents/Claude 中的用户产物') { options[:include_cowork_files] = true }
        p.on('--include-shared-security', '同时清共享 security 状态，可能影响 Codex，谨慎选择') { options[:include_shared_security] = true }
        p.on('--include-browser-site-data', '纳入已知 Claude 网站专属 IndexedDB 目录；须退出支持的 Chromium 浏览器') { options[:include_browser_site_data] = true }
        p.on('-h', '--help', '显示帮助') { options[:help] = true }
        p.on('--version', '显示版本') { options[:version] = true }
      end
    end

    def inventory(options)
      system = @system.snapshot
      prefixes = (@prefixes + system.fetch(:prefixes, [])).uniq
      planner = Planner.new(home: @home, app_roots: @app_roots, prefixes: prefixes,
                            runtime_roots: @runtime_roots, config_dirs: options[:config_dirs].uniq,
                            projects: options[:projects],
                            include_shared_security: !!options[:include_shared_security],
                            include_project_instructions: !!options[:include_project_instructions],
                            include_cowork_files: !!options[:include_cowork_files])
      targets = planner.targets
      browser = options[:include_browser_site_data] ? BrowserData.new(home: @home, uid: @uid) : nil
      browser_targets = browser ? browser.targets : []
      selected_browser_paths = browser_targets.map(&:path)
      browser_guard = options[:include_browser_site_data] ? @system.browser_processes : {processes: [], issues: []}
      manual = @auditor.findings.reject { |finding| selected_browser_paths.include?(finding[:path]) } + planner.preserved.select do |item|
        item[:reason].match?(/manual|Cowork|Git worktrees|unverified/i)
      end
      { targets: targets + browser_targets, preserved: planner.preserved,
        issues: planner.issues + system[:issues] + @runtime_issues + (browser ? browser.issues : []) + browser_guard[:issues],
        actions: system[:actions], processes: system[:processes] + browser_guard[:processes], manual: manual, prefixes: prefixes,
        configuration_roots: planner.configuration_roots, browser_targets: browser_targets }
    end

    def discover_runtime_roots
      return [] unless @platform.include?('darwin')
      dirs = %w[DARWIN_USER_CACHE_DIR DARWIN_USER_TEMP_DIR].map do |key|
        result = @runtime_runner.call(['/usr/bin/getconf', key])
        unless result[:status] == 0
          @runtime_issues << "#{key} discovery failed (exit #{result[:status]}); runtime data was not verified"
          next
        end
        path = result[:stdout].strip
        begin
          real = File.realpath(path)
          unless File.directory?(real) && real.start_with?('/private/var/folders/') && File.stat(real).uid == @uid
            @runtime_issues << "#{key} discovery returned an unverified runtime root"
            next
          end
          [real, File.dirname(real)]
        rescue SystemCallError, ArgumentError
          @runtime_issues << "#{key} discovery returned an inaccessible runtime root"
          nil
        end
      end.compact.flatten
      # Official Claude scratchpad defaults to /tmp/claude-UID.
      if File.directory?('/tmp')
        dirs << File.realpath('/tmp')
      else
        @runtime_issues << 'system temporary root is inaccessible; scratchpad data was not verified'
      end
      dirs.uniq
    end

    def clean?(plan)
      plan[:targets].empty? && plan[:actions].empty? && plan[:issues].empty? && plan[:processes].empty? && plan[:manual].empty?
    end

    def signature(plan)
      [plan[:targets].map { |t| [t.path, t.identity] }, plan[:actions], plan[:issues], plan[:processes], plan[:manual],
       plan[:prefixes], plan[:configuration_roots]]
    end

    def public_plan(plan)
      { paths: plan[:targets].map { |t| { path: t.path, reason: t.reason } },
        actions: plan[:actions], preserved: plan[:preserved], issues: plan[:issues], processes: plan[:processes] }
        .merge(manual: plan[:manual])
    end

    def base_report(options, plan)
      { version: VERSION, generated_at: Time.now.utc.iso8601,
        mode: options[:apply] ? 'apply' : (options[:verify] ? 'verify' : 'preview'),
        scope: { include_browser_site_data: !!options[:include_browser_site_data] },
        plan: public_plan(plan),
        limits: ['选中的站点专属 IndexedDB 可在浏览器退出后清理；其余浏览器站点数据/扩展须在 UI 核对', '不清云端、其他用户、系统历史日志或独立备份/快照',
                 '项目文件仅在显式指定范围处理；共享 MCP/AGENTS.md 不删',
                 'Cookie、Local Storage、浏览器注册与自定义 IDE 配置仍须人工核验；本工具不读共享浏览器数据库',
                 'known_scope_clean 仅代表本版本已知清单通过复查，不代表全盘或所有浏览器数据已清除'] }
    end

    def finish(report, options, code)
      options[:json] ? @out.puts(JSON.pretty_generate(report)) : display(report)
      code
    end

    def display(report)
      @out.puts "Claude Cleaner #{VERSION} — #{report[:status]} (#{report[:mode]})"
      plan = report[:remaining] || report[:plan]
      plan[:paths].each { |t| @out.puts "  路径 #{t[:path]} — #{t[:reason]}" }
      plan[:actions].each { |a| @out.puts "  操作 #{a[:reason]}" }
      plan[:preserved].each { |p| @out.puts "  保留 #{p[:path]} — #{p[:reason]}" }
      plan[:issues].each { |issue| @out.puts "  待处理 #{issue}" }
      plan[:manual].each { |item| @out.puts "  需人工 #{item[:path]} — #{item[:reason]}" }
      plan[:processes].each do |process|
        label = process[:kind] == 'browser' ? '浏览器及 Helper' : 'Claude'
        @out.puts "  请先退出 #{label} 进程 PID=#{process[:pid]}"
      end
      @out.puts "已知待清路径 #{plan[:paths].length}，系统操作 #{plan[:actions].length}，盘点问题 #{plan[:issues].length}，人工项 #{plan[:manual].length}。"
      @out.puts '本工具会永久删除配置、登录、会话、记忆、技能和插件；无自动备份。' if report[:mode] == 'preview'
      report[:limits].each { |limit| @out.puts "  边界：#{limit}" }
    end

    def write_help(parser)
      @out.puts parser
      0
    end

    def write_version
      @out.puts VERSION
      0
    end
  end
end

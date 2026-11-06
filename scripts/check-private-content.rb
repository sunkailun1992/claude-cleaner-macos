#!/usr/bin/env ruby
# frozen_string_literal: true
require 'open3'
output, status = Open3.capture2('git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z')
abort 'Cannot enumerate repository files' unless status.success?
patterns = {
  'private absolute path' => %r{/(?:Users|Volumes)/[^/\s]+/},
  'private key' => /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  'credential' => /(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-api\d+-[A-Za-z0-9_-]{20,})/,
  'environment file' => /\A\.env(?:\..+)?\z/
}
failures = []
output.split("\0").uniq.each do |path|
  next unless File.file?(path)
  if File.basename(path).match?(patterns['environment file'])
    failures << "#{path}: environment file"
    next
  end
  text = File.binread(path)
  next if text.include?("\0")
  text.force_encoding(Encoding::UTF_8)
  unless text.valid_encoding?
    failures << "#{path}: invalid UTF-8"
    next
  end
  patterns.reject { |name, _| name == 'environment file' }.each do |name, pattern|
    failures << "#{path}: #{name}" if text.match?(pattern)
  end
end
abort failures.join("\n") unless failures.empty?
puts 'Public-content checks passed.'

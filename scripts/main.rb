#!/usr/bin/ruby
# frozen_string_literal: true
require_relative '../lib/claude_cleaner/cli'
exit ClaudeCleaner::CLI.new.run(ARGV)

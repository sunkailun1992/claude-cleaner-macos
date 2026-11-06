#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_DIR"
if [[ "$(uname -s)" == Darwin ]]; then
  RUBY_BIN=/usr/bin/ruby
else
  RUBY_BIN="$(command -v ruby)"
fi
while IFS= read -r file; do
  "$RUBY_BIN" -c "$file" >/dev/null
done < <(find lib scripts test -name '*.rb' -type f | sort)
bash -n claude-cleaner 'Clean Claude.command' scripts/check.sh
"$RUBY_BIN" -Ilib -e 'Dir["test/test_*.rb"].sort.each { |f| require File.expand_path(f) }'
"$RUBY_BIN" scripts/check-private-content.rb
git diff --check

#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$PROJECT_DIR"
if [[ "$(uname -s)" == Darwin ]]; then
  RUBY_BIN=/usr/bin/ruby
  UTF8_LOCALE=en_US.UTF-8
else
  RUBY_BIN="$(command -v ruby)"
  UTF8_LOCALE=C.UTF-8
fi
# 系统 Ruby 2.6 在非 UTF-8 locale 下为含非 ASCII 字符的路径生成异常回溯时会无限递归并崩溃（SIGILL）；检查统一用 UTF-8 locale 运行。
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) ;;
  *) export LC_ALL="$UTF8_LOCALE" ;;
esac
while IFS= read -r file; do
  "$RUBY_BIN" -c "$file" >/dev/null
done < <(find lib scripts test -name '*.rb' -type f | sort)
bash -n claude-cleaner 'Clean Claude.command' scripts/check.sh
"$RUBY_BIN" -Ilib -e 'Dir["test/test_*.rb"].sort.each { |f| require File.expand_path(f) }'
"$RUBY_BIN" scripts/check-private-content.rb
git diff --check

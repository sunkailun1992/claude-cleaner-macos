#!/bin/bash
set -uo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
"$PROJECT_DIR/claude-cleaner" --apply
result=$?
printf '\n执行结束，退出码 %s。按回车关闭窗口。\n' "$result"
read -r _
exit "$result"

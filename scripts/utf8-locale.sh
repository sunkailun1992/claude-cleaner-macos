# 由 claude-cleaner 与 scripts/check.sh 引入（source），不单独执行。
# Ruby 按进程 locale 给命令行参数、环境变量和文件名定编码。shell 没有 locale（launchd、代理、env -i），
# 或给了系统没有的 locale（例如 macOS 上的 zh_SG.UTF-8）时，实际字符集是 US-ASCII：含非 ASCII 字符的路径
# 变成二进制串，与 UTF-8 文本拼接时报错，系统 Ruby 2.6 生成异常回溯时还会无限递归并崩溃（SIGILL）。
# 所以只看实际生效的字符集：不是 UTF-8 就改用 UTF-8 locale；用户已有可用的 UTF-8 locale 时不动。
if [[ "$(locale charmap 2>/dev/null)" != UTF-8 ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    export LC_ALL=en_US.UTF-8
  else
    export LC_ALL=C.UTF-8
  fi
fi

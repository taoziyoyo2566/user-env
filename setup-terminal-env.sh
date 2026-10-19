#!/usr/bin/env bash
# user-env/setup-terminal-env.sh
# 为当前用户统一配置终端环境，支持 Debian 系 Linux 和 macOS；只改家目录，不需要 root。
#   tmux         生成 ~/.tmux.conf（catppuccin 主题、会话持久化、左下角 tmux 标识），安装插件和 bash 补全
#   prompt       在 ~/.bashrc / ~/.zshrc 加一段：在 tmux 里时，提示符前显示「tmux:会话名」
#   claude-team  安装 ~/.local/bin/claude-team：用 Team 账号启动 Claude Code，带 TEAM 标识
#
# 用法：
#   bash setup-terminal-env.sh                       安装或更新全部模块；可重复运行，改动前先备份
#   bash setup-terminal-env.sh --only tmux,prompt    只处理列出的模块
#   bash setup-terminal-env.sh --skip claude-team    跳过列出的模块
#   bash setup-terminal-env.sh --nerd-font           tmux 保留 Nerd Font 图标（终端字体是 Nerd Font 时用）
#   bash setup-terminal-env.sh --check               只检查不改动：依赖、各模块是否已装、是否与 user-env 一致
#   bash setup-terminal-env.sh --uninstall           撤销 prompt、claude-team 和 tmux 补全（可配合 --only/--skip）；
#                                         ~/.claude-team 里的登录信息保留；~/.tmux.conf 不自动撤销，
#                                         需要时用 ~/.tmux.conf.bak.<时间> 恢复
#
# 配置内容都在 files/ 里，本脚本只负责把它们放到位；以后改用 Ansible 时可以直接复用 files/。
# 部署步骤和日常使用速查（tmux 快捷键、claude-team）见同目录的 README.md。

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FILES=$HERE/files
TS=$(date +%Y%m%d%H%M%S)
OS=$(uname -s)
ALL_MODULES="tmux prompt claude-team"

ONLY=""
SKIP=""
NERD_FONT=0
UNINSTALL=0
CHECK=0

die()  { echo "错误：$*" >&2; exit 1; }
warn() { echo "警告：$*" >&2; }

check_modules() {
  local m
  for m in $(echo "$1" | tr ',' ' '); do
    case " $ALL_MODULES " in
      *" $m "*) ;;
      *) die "未知模块：$m（可用：$ALL_MODULES）" ;;
    esac
  done
}

while [ $# -gt 0 ]; do
  case $1 in
    --only)      [ $# -ge 2 ] || die "--only 后面要跟模块列表"; ONLY=$2; shift 2 ;;
    --only=*)    ONLY=${1#*=}; shift ;;
    --skip)      [ $# -ge 2 ] || die "--skip 后面要跟模块列表"; SKIP=$2; shift 2 ;;
    --skip=*)    SKIP=${1#*=}; shift ;;
    --nerd-font) NERD_FONT=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --check)     CHECK=1; shift ;;
    -h|--help)   sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "未知参数：$1（--help 查看用法）" ;;
  esac
done
ONLY=$(echo "$ONLY" | tr -d ' ')
SKIP=$(echo "$SKIP" | tr -d ' ')
[ -z "$ONLY" ] || check_modules "$ONLY"
[ -z "$SKIP" ] || check_modules "$SKIP"
if [ "$CHECK" -eq 1 ] && [ "$UNINSTALL" -eq 1 ]; then die "--check 不能和 --uninstall 一起用"; fi

# 临时文件都放这里（里面会有 rc 文件的内容，所以放家目录、仅本人可读），退出时一起删掉
WORK=$(mktemp -d "$HOME/.user-env.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

wanted() {
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in *",$1,"*) ;; *) return 1 ;; esac
  fi
  case ",$SKIP," in *",$1,"*) return 1 ;; esac
  return 0
}

# ── 通用：写文件、维护 rc 文件里的标记块 ─────────────────────────────

# 内容有变化才写：先备份旧文件，再原地写入（目标是软链接时写到它指向的文件，不破坏链接）。
install_content() {  # $1 新内容  $2 目标  $3 新建时的权限
  local src=$1 dst=$2 mode=$3
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "  未变化：$dst"
    return 0
  fi
  if [ -e "$dst" ]; then
    # 同一次运行里同一个文件可能被改多次（比如 ~/.bashrc），只保留第一次之前的原始内容
    if [ ! -e "$dst.bak.$TS" ]; then
      cp -p "$dst" "$dst.bak.$TS"
      echo "  已备份：$dst.bak.$TS"
    fi
    cat "$src" > "$dst"
  else
    cat "$src" > "$dst"
    chmod "$mode" "$dst"
  fi
  echo "  已写入：$dst"
}

# 标记格式：# >>> 名称 >>> … # <<< 名称 <<<
# 与 Ansible blockinfile 的 marker="# {mark} 名称 {mark}"、marker_begin=">>>"、marker_end="<<<" 相同，
# 以后换成 Ansible 管理时会直接接管同一段。
check_block() {  # $1 文件  $2 开始标记  $3 结束标记；输出 0 或 1（是否已有这一段）
  local rc=$1 begin=$2 end=$3 nb ne lb le
  nb=$(grep -cxF "$begin" "$rc" || true)
  ne=$(grep -cxF "$end" "$rc" || true)
  if [ "$nb" -eq 0 ] && [ "$ne" -eq 0 ]; then
    echo 0
    return 0
  fi
  if [ "$nb" -ne 1 ] || [ "$ne" -ne 1 ]; then
    die "$rc 里的标记不成对或重复（\"$begin\" $nb 个，\"$end\" $ne 个），请手动检查后再运行。"
  fi
  lb=$(grep -nxF "$begin" "$rc" | cut -d: -f1)
  le=$(grep -nxF "$end" "$rc" | cut -d: -f1)
  [ "$lb" -lt "$le" ] || die "$rc 里的结束标记出现在开始标记之前，请手动检查后再运行。"
  echo 1
}

set_block() {  # $1 文件  $2 名称  $3 内容文件
  local rc=$1 name=$2 body=$3 begin end has tmp
  begin="# >>> $name >>>"
  end="# <<< $name <<<"
  has=0
  if [ -e "$rc" ]; then has=$(check_block "$rc" "$begin" "$end"); fi
  tmp=$WORK/block
  : > "$tmp"
  if [ "$has" -eq 1 ]; then
    awk -v b="$begin" -v e="$end" -v body="$body" '
      $0 == b { print; while ((getline line < body) > 0) print line; close(body); skip = 1; next }
      $0 == e { skip = 0 }
      !skip   { print }
    ' "$rc" > "$tmp"
  else
    if [ -e "$rc" ]; then cat "$rc" > "$tmp"; fi
    if [ -s "$tmp" ]; then
      # 原文件最后一行没有换行时先补上，否则开始标记会接到那一行后面；再空一行隔开
      if [ -n "$(tail -c1 "$tmp")" ]; then echo >> "$tmp"; fi
      echo >> "$tmp"
    fi
    { echo "$begin"; cat "$body"; echo "$end"; } >> "$tmp"
  fi
  install_content "$tmp" "$rc" 644
}

remove_block() {  # $1 文件  $2 名称；连同紧挨在开始标记前的一个空行一起删
  local rc=$1 name=$2 begin end has tmp
  [ -f "$rc" ] || return 0
  begin="# >>> $name >>>"
  end="# <<< $name <<<"
  has=$(check_block "$rc" "$begin" "$end")
  [ "$has" -eq 1 ] || return 0
  tmp=$WORK/block
  awk -v b="$begin" -v e="$end" '
    skip       { if ($0 == e) skip = 0; next }
    $0 == b    { held = 0; skip = 1; next }
    held       { print ""; held = 0 }
    $0 == ""   { held = 1; next }
               { print }
    END        { if (held) print "" }
  ' "$rc" > "$tmp"
  install_content "$tmp" "$rc" 644
  rm -f "$tmp"
}

login_shell() { local s=${SHELL:-}; echo "${s##*/}"; }

# 要管理的 rc 文件：已存在的 ~/.bashrc、~/.zshrc，或者登录 shell 对应的那个。每行输出「shell 文件」。
rc_files() {
  local login
  login=$(login_shell)
  if [ -f "$HOME/.bashrc" ] || [ "$login" = bash ]; then echo "bash $HOME/.bashrc"; fi
  if [ -f "$HOME/.zshrc" ] || [ "$login" = zsh ]; then echo "zsh $HOME/.zshrc"; fi
}

# ── 模块：tmux ───────────────────────────────────────────────────────

# tmux 版本是否 >= 3.2（catppuccin v2 的要求）
tmux_version_ok() {
  local major minor
  read -r major minor < <(tmux -V | sed -E 's/[^0-9]*([0-9]+)\.([0-9]+).*/\1 \2/')
  [ "${major:-0}" -gt 3 ] || { [ "${major:-0}" -eq 3 ] && [ "${minor:-0}" -ge 2 ]; }
}

# 生成 ~/.tmux.conf 的内容：$1 为 1 时保留 Nerd Font 图标
render_tmux_conf() {
  [ "$(grep -cxF '# @@USER_ENV_ICONS@@' "$FILES/tmux.conf" || true)" -eq 1 ] \
    || die "$FILES/tmux.conf 里应当正好有一行 # @@USER_ENV_ICONS@@"
  awk -v nerd="$1" -v icons="$FILES/tmux-plain-icons.conf" '
    $0 == "# @@USER_ENV_ICONS@@" {
      if (nerd == 1) print "# 终端字体是 Nerd Font（安装时用了 --nerd-font）：保留 catppuccin 默认图标"
      else { while ((getline line < icons) > 0) print line; close(icons) }
      next
    }
    { print }
  ' "$FILES/tmux.conf"
}

# files/tmux.conf 里声明的插件目录名（'catppuccin/tmux#v2.3.2' 的目录是 tmux）
tmux_plugin_dirs() {
  sed -n "s/^set -g @plugin '\([^']*\)'.*/\1/p" "$FILES/tmux.conf" | sed 's/#.*//; s|.*/||'
}

# files/tmux.conf 里固定了版本的插件，每行输出「目录名 版本」（'catppuccin/tmux#v2.3.2' 输出 tmux v2.3.2）
tmux_pinned_plugins() {
  sed -n "s/^set -g @plugin '\([^'#]*\)#\([^']*\)'.*/\1 \2/p" "$FILES/tmux.conf" | sed 's|^[^ ]*/||'
}

# 已装的插件是否正是固定的版本：$1 目录名  $2 tag 或分支
tmux_pinned_ok() {
  local d=$HOME/.tmux/plugins/$1 head
  head=$(git -C "$d" rev-parse -q --verify HEAD 2>/dev/null) || return 1
  [ "$(git -C "$d" rev-parse -q --verify "refs/tags/$2^{commit}" 2>/dev/null)" = "$head" ] \
    || [ "$(git -C "$d" symbolic-ref -q --short HEAD 2>/dev/null)" = "$2" ]
}

tmux_install() {
  local tmp dir name ref moved="" running=0
  echo "== tmux"
  [ -d "$HOME/.tmux/plugins/tpm" ] || git clone -q https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"

  tmp=$WORK/tmux.conf
  render_tmux_conf "$NERD_FONT" > "$tmp"
  install_content "$tmp" "$HOME/.tmux.conf" 644
  rm -f "$tmp"

  tmux_completion_install

  # 存档目录选择与 tmux-resurrect 一致；存档含明文屏幕内容，只允许本人读
  dir=$HOME/.tmux/resurrect
  [ -d "$dir" ] || dir=${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect
  mkdir -p "$dir"
  chmod 700 "$dir"

  if tmux list-sessions >/dev/null 2>&1; then running=1; fi
  # 已在运行的 tmux 没加载过 TPM 时 TPM 找不到插件目录；设为同一个值无害
  if [ "$running" -eq 1 ]; then
    tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$HOME/.tmux/plugins/" 2>/dev/null || true
  fi
  # TPM 只装缺的插件，prefix+U 也换不了固定的版本：files/tmux.conf 改了版本时先把旧的挪开，
  # 让 TPM 按新版本重新装；装不上就放回去，tmux 照旧能用
  while read -r name ref; do
    { [ -n "$name" ] && [ -d "$HOME/.tmux/plugins/$name" ]; } || continue
    tmux_pinned_ok "$name" "$ref" && continue
    mv "$HOME/.tmux/plugins/$name" "$WORK/plugin-$name"
    moved="$moved $name"
    echo "  插件 $name 换成固定的 $ref"
  done < <(tmux_pinned_plugins)
  # TPM 回退用的 https://git::@github.com/... 会让 git 把凭据交给 credential helper（macOS 上是钥匙串，可能弹窗卡住）；
  # 公开仓库不需要凭据，用空值重置 helper 列表（git >= 2.31，更老的 git 忽略这几个变量，行为不变）
  if ! GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0='' \
       "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null; then
    for name in $moved; do
      rm -rf "${HOME:?}/.tmux/plugins/$name"
      mv "$WORK/plugin-$name" "$HOME/.tmux/plugins/$name"
      echo "  已放回原来的插件 $name"
    done
    die "tmux 插件安装失败（需要能访问 github.com），~/.tmux.conf 已写好，网络恢复后重新运行即可"
  fi
  echo "  插件已就绪"
  if [ "$running" -eq 1 ]; then
    tmux source-file "$HOME/.tmux.conf"
    echo "  已重新加载正在运行的 tmux（已有会话不受影响）"
  else
    echo "  下次启动 tmux 时生效"
  fi
}

tmux_uninstall() {
  echo "== tmux"
  if [ -f "$TMUX_COMPLETION" ] && grep -qF "$TMUX_COMPLETION_MARK" "$TMUX_COMPLETION"; then
    rm -f "$TMUX_COMPLETION"
    echo "  已删除：$TMUX_COMPLETION"
  fi
  echo "  不自动撤销 ~/.tmux.conf；需要时用 ~/.tmux.conf.bak.<时间> 恢复"
}

# tmux 的 bash 补全放进 bash-completion 的用户目录，用到 tmux 时自动加载，不用改 ~/.bashrc。
# zsh 自带 tmux 补全，不需要这个文件。
TMUX_COMPLETION=${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}
TMUX_COMPLETION=${TMUX_COMPLETION%%:*}/completions/tmux
TMUX_COMPLETION_MARK=user-env-tmux-completion-v1

tmux_completion_install() {
  if [ -e "$TMUX_COMPLETION" ] && ! grep -qF "$TMUX_COMPLETION_MARK" "$TMUX_COMPLETION"; then
    warn "$TMUX_COMPLETION 已存在且不是本脚本安装的，未覆盖（tmux 会话名补全以它为准）"
    return 0
  fi
  mkdir -p "${TMUX_COMPLETION%/*}"
  install_content "$FILES/tmux-completion.bash" "$TMUX_COMPLETION" 644
}

# ── 模块：prompt ─────────────────────────────────────────────────────

prompt_install() {
  local shell rc found=0
  echo "== 提示符"
  while read -r shell rc; do
    [ -n "$shell" ] || continue
    found=1
    set_block "$rc" tmux-prompt "$FILES/prompt.$shell"
  done < <(rc_files)
  [ "$found" -eq 1 ] || warn "没有 ~/.bashrc 或 ~/.zshrc，登录 shell 也不是 bash/zsh，跳过提示符"
  if [ "$OS" = Darwin ] && [ "$(login_shell)" = bash ] && [ -f "$HOME/.bash_profile" ] \
     && ! grep -q 'bashrc' "$HOME/.bash_profile"; then
    warn "macOS 的终端读的是 ~/.bash_profile，请在里面加一行：[ -f ~/.bashrc ] && . ~/.bashrc"
  fi
  echo "  已开着的终端执行一次 source ~/.bashrc（zsh 是 ~/.zshrc）后生效，新终端自动生效"
}

prompt_uninstall() {
  local rc
  echo "== 提示符"
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    remove_block "$rc" tmux-prompt
  done
}

# ── 模块：claude-team ────────────────────────────────────────────────

CT_BIN_DIR=$HOME/.local/bin
CT_WRAPPER=$CT_BIN_DIR/claude-team
CT_DIR=$HOME/.claude-team
CT_SETTINGS=$CT_DIR/settings.json
CT_WRAPPER_MARK=claude-team-wrapper-v1
CT_STATUS_MARK=claude-team-statusline-v1

ct_status_cmd() { jq -r '.statusLine.command // empty' "$CT_SETTINGS" 2>/dev/null; }

# 用 jq 改写 Team 的 settings.json，保留其他设置；先写临时文件再替换，Claude 不会读到半个文件。
ct_update_settings() {  # $1 jq 过滤器，其余参数传给 jq
  local filter=$1 tmp
  shift
  tmp=$(mktemp "$CT_DIR/.settings.json.XXXXXX")
  if [ -f "$CT_SETTINGS" ]; then
    jq "$@" "$filter" "$CT_SETTINGS" > "$tmp" || { rm -f "$tmp"; die "无法改写 $CT_SETTINGS"; }
  else
    jq -n "$@" "$filter" > "$tmp" || { rm -f "$tmp"; die "无法创建 $CT_SETTINGS"; }
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$CT_SETTINGS"
}

claude_team_install() {
  local rc found existing tmp shell
  echo "== claude-team"

  # 旧版脚本写进 shell 配置的同名函数会盖过新命令
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$rc" ] && grep -qF "# >>> claude-profiles >>>" "$rc"; then
      die "$rc 里还有旧版脚本写入的 claude-team / clp / clt 函数，会盖过新命令。请先删除从 \"# >>> claude-profiles >>>\" 到 \"# <<< claude-profiles <<<\" 的那一段，再重新运行。"
    fi
  done
  # 不覆盖不是本脚本装的 claude-team
  if [ -e "$CT_WRAPPER" ] && ! grep -qF "$CT_WRAPPER_MARK" "$CT_WRAPPER"; then
    die "$CT_WRAPPER 已存在且不是本脚本安装的，为避免覆盖已停止。"
  fi
  found=$(command -v claude-team 2>/dev/null || true)
  if [ -n "$found" ] && [ "$found" != "$CT_WRAPPER" ]; then
    die "PATH 里已有另一个 claude-team（$found），为避免混淆已停止。"
  fi
  if [ -f "$CT_SETTINGS" ]; then
    jq -e 'type == "object"' "$CT_SETTINGS" >/dev/null 2>&1 \
      || die "$CT_SETTINGS 不是有效的 JSON 对象，未做任何改动。"
  fi

  mkdir -p "$CT_BIN_DIR"
  [ -d "$CT_DIR" ] || mkdir -m 700 "$CT_DIR"
  chmod 700 "$CT_DIR"

  # 用 mv 整体替换：正在运行的旧版本继续读它自己的那份，不会读到混合内容
  if [ -f "$CT_WRAPPER" ] && cmp -s "$FILES/claude-team" "$CT_WRAPPER"; then
    echo "  未变化：$CT_WRAPPER"
  else
    tmp=$(mktemp "$CT_BIN_DIR/.claude-team.XXXXXX")
    cat "$FILES/claude-team" > "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$CT_WRAPPER"
    echo "  已写入：$CT_WRAPPER"
  fi

  existing=""
  if [ -f "$CT_SETTINGS" ]; then existing=$(ct_status_cmd); fi
  case $existing in
    "" | *"$CT_STATUS_MARK"*)
      # shellcheck disable=SC2016  # $cmd 是 jq 变量，由 --arg 传入
      ct_update_settings '.statusLine = {type: "command", command: $cmd, padding: 0}' \
        --arg cmd "$(cat "$FILES/claude-team-statusline.sh")"
      echo "  已在 $CT_SETTINGS 设置 TEAM 状态栏"
      ;;
    *)
      echo "  注意：$CT_SETTINGS 已有自定义状态栏，未改动，Claude 状态栏里不会出现 TEAM"
      ;;
  esac

  case ":$PATH:" in
    *":$CT_BIN_DIR:"*) ;;
    *)
      echo "  $CT_BIN_DIR 不在 PATH 里，加到 shell 配置："
      while read -r shell rc; do
        [ -n "$shell" ] || continue
        set_block "$rc" user-env-path "$FILES/local-bin-path.sh"
      done < <(rc_files)
      ;;
  esac
  echo "  第一次运行 claude-team：选主题，登录时选 Team 组织，进去后用 /status 确认"
}

claude_team_uninstall() {
  echo "== claude-team"
  if [ -e "$CT_WRAPPER" ]; then
    grep -qF "$CT_WRAPPER_MARK" "$CT_WRAPPER" || die "$CT_WRAPPER 不是本脚本安装的，未删除。"
    rm -f "$CT_WRAPPER"
    echo "  已删除：$CT_WRAPPER"
  fi
  if [ -f "$CT_SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    case $(ct_status_cmd) in
      *"$CT_STATUS_MARK"*)
        ct_update_settings 'del(.statusLine)'
        echo "  已从 $CT_SETTINGS 移除 TEAM 状态栏"
        ;;
    esac
  fi
  echo "  登录信息和会话记录仍在 $CT_DIR，不再需要时可手动删除"
}

# ── 安装前检查依赖：缺的一次列全，什么都不改就退出 ─────────────────────

pkg_hint() {  # $1 包名（空格分隔）
  if [ "$OS" = Darwin ]; then echo "brew install $1"; else echo "sudo apt install $1"; fi
}

bash_completion_available() {
  local f
  for f in /usr/share/bash-completion/bash_completion /etc/bash_completion \
           /opt/homebrew/etc/profile.d/bash_completion.sh /usr/local/etc/profile.d/bash_completion.sh; do
    if [ -r "$f" ]; then return 0; fi
  done
  return 1
}

preflight() {
  local missing=""
  if wanted tmux; then
    command -v git >/dev/null 2>&1 || missing="$missing git"
    command -v tmux >/dev/null 2>&1 || missing="$missing tmux"
  fi
  if wanted claude-team; then
    command -v jq >/dev/null 2>&1 || missing="$missing jq"
  fi
  [ -z "$missing" ] || die "缺少依赖：${missing# }。先安装：$(pkg_hint "${missing# }")"
  if wanted tmux; then
    tmux_version_ok || die "tmux 需要 >= 3.2，当前是 $(tmux -V)"
    if [ "$(login_shell)" = bash ] && ! bash_completion_available; then
      if [ "$OS" = Darwin ]; then
        warn "没有找到 bash-completion，tmux 会话名补全不会生效。安装：brew install bash-completion@2，并按 brew 的提示在 ~/.bash_profile 里加载"
      else
        warn "没有找到 bash-completion，tmux 会话名补全不会生效。安装：sudo apt install bash-completion"
      fi
    fi
  fi
  if wanted claude-team && ! command -v claude >/dev/null 2>&1; then
    warn "没有找到 claude 命令：claude-team 照常安装，但要先装好 Claude Code 才能用"
  fi
}

# ── --check：只读检查 ────────────────────────────────────────────────

CHECK_FAIL=0
pass() { echo "  [OK] $*"; }
fail() { echo "  [!!] $*"; CHECK_FAIL=1; }
note() { echo "  [--] $*"; }

block_body() {  # $1 文件  $2 名称：输出标记之间的内容
  awk -v b="# >>> $2 >>>" -v e="# <<< $2 <<<" '$0 == e { f = 0 } f { print } $0 == b { f = 1 }' "$1"
}

tmux_check() {
  local d name ref missing="" out
  echo "== tmux"
  if ! command -v tmux >/dev/null 2>&1; then
    fail "没有安装 tmux（$(pkg_hint tmux)）"
    return 0
  fi
  if tmux_version_ok; then pass "$(tmux -V)"; else fail "$(tmux -V) 太旧，需要 >= 3.2"; fi
  command -v git >/dev/null 2>&1 || fail "没有安装 git（$(pkg_hint git)），装插件要用"

  render_tmux_conf 0 > "$WORK/tmux.plain"
  render_tmux_conf 1 > "$WORK/tmux.nerd"
  if [ ! -f "$HOME/.tmux.conf" ]; then
    fail "$HOME/.tmux.conf 不存在（运行 setup-terminal-env.sh）"
  elif cmp -s "$WORK/tmux.plain" "$HOME/.tmux.conf"; then
    pass "$HOME/.tmux.conf 与 user-env 一致"
  elif cmp -s "$WORK/tmux.nerd" "$HOME/.tmux.conf"; then
    pass "$HOME/.tmux.conf 与 user-env 一致（保留 Nerd Font 图标）"
  else
    fail "$HOME/.tmux.conf 与 user-env 不一致（手动改过，或 user-env 有更新；运行 setup-terminal-env.sh 会先备份再覆盖）"
  fi

  for d in $(tmux_plugin_dirs); do
    [ -d "$HOME/.tmux/plugins/$d" ] || missing="$missing $d"
  done
  if [ -z "$missing" ]; then pass "插件都已安装"; else fail "缺少插件：${missing# }（运行 setup-terminal-env.sh）"; fi
  while read -r name ref; do
    { [ -n "$name" ] && [ -d "$HOME/.tmux/plugins/$name" ]; } || continue
    if tmux_pinned_ok "$name" "$ref"; then
      pass "插件 $name 是固定的 $ref"
    else
      fail "插件 $name 不是 files/tmux.conf 固定的 $ref（运行 setup-terminal-env.sh 更新）"
    fi
  done < <(tmux_pinned_plugins)

  if [ ! -f "$TMUX_COMPLETION" ]; then
    fail "tmux 补全未安装：$TMUX_COMPLETION（运行 setup-terminal-env.sh）"
  elif ! grep -qF "$TMUX_COMPLETION_MARK" "$TMUX_COMPLETION"; then
    note "$TMUX_COMPLETION 不是本脚本安装的，保持原样"
  elif cmp -s "$FILES/tmux-completion.bash" "$TMUX_COMPLETION"; then
    pass "tmux 补全与 user-env 一致"
  else
    fail "tmux 补全与 user-env 不一致（运行 setup-terminal-env.sh 更新）"
  fi
  if [ "$(login_shell)" = bash ]; then
    # 用一个登录式交互 bash 实际加载一次，确认 bash-completion 能找到它
    # 加载不到时 complete -p 返回非零，这正是要报告的情况，不能让 set -e 把检查中途终止
    out=$(bash -lic '_comp_load tmux 2>/dev/null || __load_completion tmux 2>/dev/null; complete -p tmux' \
          </dev/null 2>/dev/null | tail -n 1) || true
    case $out in
      *_user_env_tmux*) pass "bash 能加载 tmux 补全（tmux a -t <Tab> 列出会话）" ;;
      *) fail "bash 加载不到 tmux 补全：确认 bash-completion 已安装并在 ~/.bashrc 或 ~/.bash_profile 里加载" ;;
    esac
  else
    note "登录 shell 是 $(login_shell)，用它自带的 tmux 补全"
  fi
}

prompt_check() {
  local shell rc has found=0
  echo "== 提示符"
  while read -r shell rc; do
    [ -n "$shell" ] || continue
    found=1
    has=0
    if [ -f "$rc" ]; then has=$(check_block "$rc" "# >>> tmux-prompt >>>" "# <<< tmux-prompt <<<"); fi
    if [ "$has" -eq 0 ]; then
      fail "$rc 里没有 tmux-prompt（运行 setup-terminal-env.sh）"
    elif block_body "$rc" tmux-prompt | cmp -s - "$FILES/prompt.$shell"; then
      pass "$rc 里的 tmux-prompt 与 user-env 一致"
    else
      fail "$rc 里的 tmux-prompt 与 user-env 不一致（运行 setup-terminal-env.sh 更新）"
    fi
  done < <(rc_files)
  [ "$found" -eq 1 ] || fail "没有 ~/.bashrc 或 ~/.zshrc，登录 shell 也不是 bash/zsh"
}

claude_team_check() {
  local have_jq=0 cmd
  echo "== claude-team"
  if command -v jq >/dev/null 2>&1; then have_jq=1; else fail "缺少 jq（$(pkg_hint jq)）"; fi
  if command -v claude >/dev/null 2>&1; then pass "claude 已安装"; else fail "没有找到 claude 命令（先装 Claude Code）"; fi
  if [ ! -f "$CT_WRAPPER" ]; then
    fail "$CT_WRAPPER 未安装（运行 setup-terminal-env.sh）"
  elif cmp -s "$FILES/claude-team" "$CT_WRAPPER"; then
    pass "$CT_WRAPPER 与 user-env 一致"
  else
    fail "$CT_WRAPPER 与 user-env 不一致（运行 setup-terminal-env.sh 更新）"
  fi
  case ":$PATH:" in
    *":$CT_BIN_DIR:"*) pass "$CT_BIN_DIR 在 PATH 里" ;;
    *) fail "$CT_BIN_DIR 不在当前 PATH 里（新开一个终端再查；仍不在就运行 setup-terminal-env.sh）" ;;
  esac
  if [ ! -d "$CT_DIR" ]; then
    fail "$CT_DIR 不存在（运行 setup-terminal-env.sh）"
  elif [ -n "$(find "$CT_DIR" -maxdepth 0 -perm 700)" ]; then
    pass "$CT_DIR 权限 700"
  else
    fail "$CT_DIR 权限不是 700（chmod 700 $CT_DIR）"
  fi
  if [ "$have_jq" -eq 1 ]; then
    cmd=""
    if [ -f "$CT_SETTINGS" ]; then cmd=$(ct_status_cmd); fi
    case $cmd in
      *"$CT_STATUS_MARK"*) pass "TEAM 状态栏已设置" ;;
      "") fail "TEAM 状态栏未设置（运行 setup-terminal-env.sh）" ;;
      *) note "$CT_SETTINGS 用的是自定义状态栏，里面不会显示 TEAM" ;;
    esac
    if jq -e '.oauthAccount.accountUuid // empty' "$CT_DIR/.claude.json" >/dev/null 2>&1; then
      pass "已登录（在 claude-team 里用 /status 确认是 Team 组织）"
    else
      note "还没登录：运行 claude-team，登录时选 Team 组织"
    fi
  fi
}

# ── 执行 ─────────────────────────────────────────────────────────────

if [ "$CHECK" -eq 1 ]; then
  if wanted tmux; then tmux_check; fi
  if wanted prompt; then prompt_check; fi
  if wanted claude-team; then claude_team_check; fi
  if [ "$CHECK_FAIL" -eq 0 ]; then
    echo "检查完成：没有需要处理的项。"
    exit 0
  fi
  echo "检查完成：有 [!!] 项需要处理。"
  exit 1
fi

if [ "$UNINSTALL" -eq 1 ]; then
  if wanted prompt; then prompt_uninstall; fi
  if wanted claude-team; then claude_team_uninstall; fi
  if wanted tmux; then tmux_uninstall; fi
else
  preflight
  if wanted tmux; then tmux_install; fi
  if wanted prompt; then prompt_install; fi
  if wanted claude-team; then claude_team_install; fi
fi
echo "完成。"
if [ "$UNINSTALL" -eq 0 ]; then
  echo "检查安装结果：bash $HERE/setup-terminal-env.sh --check；日常使用速查见 $HERE/README.md"
fi

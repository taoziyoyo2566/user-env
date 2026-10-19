#!/usr/bin/env bash
# user-env 的 Linux 测试：每个用例用独立的 HOME 和 tmux socket 目录，不碰本机真实配置和正在运行的 tmux。
# 前提：本机已运行过一次 setup-terminal-env.sh --only tmux（测试复用 ~/.tmux/plugins，不联网下载插件），
#       并装有 tmux、git、jq、python3、bash-completion。
# 用法：bash tests/test-linux.sh        全部通过时退出码为 0
#
# 断言写成字符串交给 ok() 里的 eval 执行：变量在字符串里使用（SC2034），单引号里的 $ 是要原样
# 写进测试用文件的内容（SC2016），ls 只用来数备份文件个数（SC2012）。
# shellcheck disable=SC2016,SC2034,SC2012
set -u
U=$(cd "$(dirname "$0")/.." && pwd)
PLUGINS=$HOME/.tmux/plugins
[ -d "$PLUGINS/tpm" ] || { echo "先在本机运行一次：bash $U/setup-terminal-env.sh --only tmux"; exit 2; }
for c in tmux git jq python3; do command -v "$c" >/dev/null || { echo "缺少 $c"; exit 2; }; done
T=$(mktemp -d "${TMPDIR:-/tmp}/user-env-test.XXXXXX")
SOCKROOT=$(mktemp -d /tmp/ue.XXXXXX)   # tmux socket 路径有长度上限，所以 socket 目录放在 /tmp 下的短路径里
FAILS=0
cleanup() {
  local d
  for d in "$SOCKROOT"/s.*; do
    [ -d "$d" ] && env -i PATH=/usr/bin:/bin TMUX_TMPDIR="$d" tmux kill-server 2>/dev/null
  done
  rm -rf "$SOCKROOT" "$T"
}
trap cleanup EXIT
mkhome() {  # $1 用例名；输出 HOME
  local h="$T/h-$1"
  rm -rf "$h"; mkdir -p "$h/.tmux" "$h/fakebin"
  ln -s "$(mktemp -d "$SOCKROOT/s.XXXX")" "$h/tt"
  cp -a "$PLUGINS" "$h/.tmux/plugins"
  printf '#!/bin/sh\necho "FAKE claude CFG=${CLAUDE_CONFIG_DIR:-<unset>}"\n' > "$h/fakebin/claude"; chmod +x "$h/fakebin/claude"
  printf '%s\n' "# demo bashrc" "PS1='\\u@\\h:\\w\\\$ '" "export DEMO=1" > "$h/.bashrc"
  echo "$h"
}
run() {  # $1 HOME，其余是 setup-terminal-env.sh 的参数；环境变量 XPATH 追加到 PATH 前面，XSHELL 指定登录 shell
  local h=$1; shift
  env -i HOME="$h" PATH="${XPATH:+$XPATH:}$h/fakebin:/usr/bin:/bin" SHELL="${XSHELL:-/bin/bash}" \
    TMUX_TMPDIR="$(readlink "$h/tt")" LANG=en_US.UTF-8 TERM=xterm-256color bash "$U/setup-terminal-env.sh" "$@"
}
tm() { local h=$1; shift; env -i HOME="$h" PATH=/usr/bin:/bin TMUX_TMPDIR="$(readlink "$h/tt")" LANG=en_US.UTF-8 tmux "$@"; }
pua() { python3 -I -c 'import sys; s=open(sys.argv[1],encoding="utf-8").read(); print(sum(1 for c in s if 0xE000<=ord(c)<=0xF8FF or ord(c)>=0xF0000))' "$1"; }
bak() { ls "$1".bak.* 2>/dev/null | wc -l; }
ok() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; FAILS=$((FAILS + 1)); fi; }

echo "## U1 fresh install (no tmux running, ~/.local/bin not in PATH)"
H=$(mkhome u1); run "$H" > "$T/u1.out" 2>&1; rc=$?; sed 's/^/    | /' "$T/u1.out" | sed "s|$H|~|g"
ok "exit 0" "[ $rc -eq 0 ]"
ok "tmux.conf has plain icons, 0 Nerd Font glyphs" "grep -qxF 'set -g @catppuccin_application_icon \"\"' '$H/.tmux.conf' && [ \$(pua '$H/.tmux.conf') -eq 0 ]"
ok "placeholder replaced" "! grep -qF '@@USER_ENV_ICONS@@' '$H/.tmux.conf'"
ok "bashrc has tmux-prompt + PATH blocks, parses" "grep -qxF '# >>> tmux-prompt >>>' '$H/.bashrc' && grep -qxF '# >>> user-env-path >>>' '$H/.bashrc' && bash -n '$H/.bashrc'"
ok "wrapper 755 + team dir 700 + settings 600" "[ \$(stat -c %a '$H/.local/bin/claude-team') = 755 ] && [ \$(stat -c %a '$H/.claude-team') = 700 ] && [ \$(stat -c %a '$H/.claude-team/settings.json') = 600 ]"
ok "single .bashrc backup holds the ORIGINAL content" "[ \$(bak '$H/.bashrc') -eq 1 ] && printf '%s\\n' '# demo bashrc' \"PS1='\\\\u@\\\\h:\\\\w\\\\\\$ '\" 'export DEMO=1' | cmp -s - \$(ls '$H'/.bashrc.bak.*)"
ok "tmux completion installed (644, marked)" "[ \$(stat -c %a '$H/.local/share/bash-completion/completions/tmux') = 644 ] && grep -q user-env-tmux-completion-v1 '$H/.local/share/bash-completion/completions/tmux'"
ok "resurrect dir 700" "[ \$(stat -c %a '$H/.tmux/resurrect' 2>/dev/null || stat -c %a '$H/.local/share/tmux/resurrect') = 700 ]"
ok "no tmux server left in sandbox" "! tm '$H' list-sessions >/dev/null 2>&1"
tm "$H" kill-server 2>/dev/null

echo "## U2 rerun is a no-op"
s1=$(cd "$H" && sha256sum .tmux.conf .bashrc .local/bin/claude-team .claude-team/settings.json); run "$H" > "$T/u2.out" 2>&1; rc=$?
s2=$(cd "$H" && sha256sum .tmux.conf .bashrc .local/bin/claude-team .claude-team/settings.json)
ok "exit 0, files identical, all '未变化'" "[ $rc -eq 0 ] && [ \"\$s1\" = \"\$s2\" ] && [ \$(grep -c '未变化' '$T/u2.out') -ge 4 ]"
ok "no new backups" "[ \$(bak '$H/.tmux.conf') -eq 0 ] && [ \$(bak '$H/.bashrc') -eq 1 ]"
tm "$H" kill-server 2>/dev/null

echo "## U3 --nerd-font, then back"
run "$H" --only tmux --nerd-font > /dev/null 2>&1; ok "nerd variant: no overrides, comment present" "! grep -qF 'catppuccin_application_icon' '$H/.tmux.conf' && grep -qF -- '--nerd-font' '$H/.tmux.conf'"
sleep 1   # 备份名精确到秒：同一秒内再运行一次会沿用已有的备份名、不再另做备份，这里要的是第二份备份
run "$H" --only tmux > /dev/null 2>&1; ok "plain again, 2 backups now" "grep -qF 'catppuccin_application_icon' '$H/.tmux.conf' && [ \$(bak '$H/.tmux.conf') -eq 2 ]"
tm "$H" kill-server 2>/dev/null

echo "## U4 running tmux server gets reloaded"
H=$(mkhome u4); tm "$H" -f /dev/null new-session -d -s demo 'sleep 60'; run "$H" --only tmux > "$T/u4.out" 2>&1
ok "installer reported reload" "grep -qF '已重新加载' '$T/u4.out'"
ok "server now has the tmux pill and plain icons" "tm '$H' show -gv status-left | grep -qF 'tmux: #S' && [ -z \"\$(tm '$H' show -gv @catppuccin_application_icon)\" ] && tm '$H' show -gv @catppuccin_status_application | grep -q '█'"
ok "session survived" "tm '$H' has-session -t demo"
tm "$H" kill-server

echo "## U5 rc block edge cases"
H=$(mkhome u5); printf '%s\n' 'export A=1' '' '# >>> tmux-prompt >>>' 'echo OLD' '# <<< tmux-prompt <<<' 'export Z=9' > "$H/.bashrc"
run "$H" --only prompt >/dev/null 2>&1; ok "old block body replaced in place, surroundings kept" "! grep -q 'echo OLD' '$H/.bashrc' && grep -qF 'tmux display' '$H/.bashrc' && head -1 '$H/.bashrc' | grep -qx 'export A=1' && tail -1 '$H/.bashrc' | grep -qx 'export Z=9'"
H=$(mkhome u5b); printf 'export A=1\nexport LAST=keep' > "$H/.bashrc"; run "$H" --only prompt >/dev/null 2>&1
ok "no trailing newline: last line intact, file parses" "grep -qx 'export LAST=keep' '$H/.bashrc' && bash -n '$H/.bashrc'"
H=$(mkhome u5c); printf '%s\n' 'export A=1' '# >>> tmux-prompt >>>' 'echo half' 'export AFTER=1' > "$H/.bashrc"; c0=$(sha256sum < "$H/.bashrc")
run "$H" --only prompt > "$T/u5c.out" 2>&1; rc=$?; ok "begin without end: refuse, file untouched" "[ $rc -ne 0 ] && [ \"\$(sha256sum < '$H/.bashrc')\" = \"$c0\" ] && grep -q '不成对' '$T/u5c.out'"
H=$(mkhome u5d); printf '%s\n' '# <<< tmux-prompt <<<' 'x=1' '# >>> tmux-prompt >>>' 'y=2' > "$H/.bashrc"; c0=$(sha256sum < "$H/.bashrc")
run "$H" --only prompt > "$T/u5d.out" 2>&1; rc=$?; ok "end before begin: refuse, file untouched" "[ $rc -ne 0 ] && [ \"\$(sha256sum < '$H/.bashrc')\" = \"$c0\" ]"
H=$(mkhome u5e); mkdir -p "$H/dotfiles"; mv "$H/.bashrc" "$H/dotfiles/bashrc"; ln -s dotfiles/bashrc "$H/.bashrc"; run "$H" --only prompt >/dev/null 2>&1
ok "symlinked .bashrc stays a symlink, target updated" "[ -L '$H/.bashrc' ] && grep -qF 'tmux-prompt' '$H/dotfiles/bashrc'"

echo "## U6 zsh user without ~/.zshrc"
H=$(mkhome u6); XSHELL=/bin/zsh run "$H" --only prompt >/dev/null 2>&1
ok ".zshrc created with zsh block; .bashrc (exists) also handled" "grep -qF 'add-zsh-hook precmd' '$H/.zshrc' && grep -qF 'tmux display -p' '$H/.bashrc' && [ \$(bak '$H/.zshrc') -eq 0 ] && [ \$(stat -c %a '$H/.zshrc') = 644 ]"

echo "## U7 --uninstall"
H=$T/h-u1; orig="$T/u7.orig"; printf '%s\n' "# demo bashrc" "PS1='\\u@\\h:\\w\\\$ '" "export DEMO=1" > "$orig"
run "$H" --uninstall > "$T/u7.out" 2>&1; rc=$?
ok "exit 0; wrapper gone; statusLine gone; team dir kept" "[ $rc -eq 0 ] && [ ! -e '$H/.local/bin/claude-team' ] && [ \"\$(jq -r '.statusLine // \"none\"' '$H/.claude-team/settings.json')\" = none ] && [ -d '$H/.claude-team' ]"
ok "bashrc = original + PATH block only (prompt block and its blank line removed)" "awk '/^# >>> user-env-path >>>/{exit} {print}' '$H/.bashrc' | sed '\$d' | cmp -s - '$orig' && ! grep -qF 'tmux-prompt' '$H/.bashrc'"
ok "uninstall removed tmux completion" "[ ! -e '$H/.local/share/bash-completion/completions/tmux' ]"
ok "tmux.conf untouched, message shown" "grep -qF '不自动撤销' '$T/u7.out' && [ -f '$H/.tmux.conf' ]"

echo "## U8 argument handling"
H=$(mkhome u8); run "$H" --only bogus > "$T/u8.out" 2>&1; ok "unknown module rejected" "[ \$? -ne 0 ] && grep -q '未知模块' '$T/u8.out'"
run "$H" --frob > "$T/u8b.out" 2>&1; ok "unknown option rejected" "grep -q '未知参数' '$T/u8b.out'"
run "$H" --only=prompt >/dev/null 2>&1; ok "--only=prompt touched only prompt" "[ ! -e '$H/.tmux.conf' ] && [ ! -e '$H/.local/bin/claude-team' ] && grep -qF 'tmux-prompt' '$H/.bashrc'"
run "$H" --skip tmux,prompt >/dev/null 2>&1; ok "--skip tmux,prompt installed only claude-team" "[ ! -e '$H/.tmux.conf' ] && [ -x '$H/.local/bin/claude-team' ]"
run "$H" --help | head -2 | grep -q 'user-env/setup-terminal-env.sh'; ok "--help prints header" "[ \$? -eq 0 ]"

echo "## U9 claude-team conflicts"
H=$(mkhome u9); printf '# >>> claude-profiles >>>\nclt() { :; }\n# <<< claude-profiles <<<\n' >> "$H/.bashrc"; run "$H" --only claude-team > "$T/u9.out" 2>&1
ok "old A-style block refused" "[ ! -e '$H/.local/bin/claude-team' ] && grep -q '旧版脚本' '$T/u9.out'"
H=$(mkhome u9b); mkdir -p "$H/.local/bin"; printf '#!/bin/sh\necho foreign\n' > "$H/.local/bin/claude-team"; run "$H" --only claude-team > "$T/u9b.out" 2>&1
ok "foreign claude-team refused and kept" "grep -q 'foreign' '$H/.local/bin/claude-team' && grep -q '不是本脚本安装的' '$T/u9b.out'"

echo "## U10 wrapper installed by user-env works (fake claude)"
H=$T/h-u8; out=$(env -i HOME="$H" PATH="$H/.local/bin:$H/fakebin:/usr/bin:/bin" claude-team </dev/null 2>&1)
ok "claude-team -> CLAUDE_CONFIG_DIR=~/.claude-team" "[ \"\$out\" = \"FAKE claude CFG=$H/.claude-team\" ]"


echo "## U11 refinements"
H=$(mkhome u11); rm "$H/.bashrc"; XSHELL=/bin/bash run "$H" --only " prompt" >/dev/null 2>&1
ok "--only with a space still selects prompt; new rc has no leading blank line" "head -1 '$H/.bashrc' | grep -qx '# >>> tmux-prompt >>>'"
run "$H" --only prompt,tmux >/dev/null 2>&1; H5=$(mkhome u11b); printf '%s\n' 'x=1' '# >>> tmux-prompt >>>' > "$H5/.bashrc"; run "$H5" --only prompt >/dev/null 2>&1
ok "no ~/.user-env.* temp dirs left after normal and failed runs" "[ \$(ls -d '$H'/.user-env.* '$H5'/.user-env.* 2>/dev/null | wc -l) -eq 0 ]"
H6=$(mkhome u11c); printf '#!/bin/sh\necho download fail >&2\nexit 1\n' > "$H6/.tmux/plugins/tpm/bin/install_plugins"; run "$H6" --only tmux > "$T/u11c.out" 2>&1; rc=$?
ok "plugin install failure: clear message, non-zero exit, config already written" "[ $rc -ne 0 ] && grep -q '插件安装失败' '$T/u11c.out' && [ -f '$H6/.tmux.conf' ]"

echo "## U12 foreign tmux completion is kept"
H=$(mkhome u12); mkdir -p "$H/.local/share/bash-completion/completions"; echo "# someone else's" > "$H/.local/share/bash-completion/completions/tmux"
run "$H" --only tmux > "$T/u12.out" 2>&1; rc=$?
ok "not overwritten, warned, install still ok" "[ $rc -eq 0 ] && grep -qx \"# someone else's\" '$H/.local/share/bash-completion/completions/tmux' && grep -q '未覆盖' '$T/u12.out'"
run "$H" --uninstall --only tmux >/dev/null 2>&1; ok "uninstall leaves the foreign file alone" "grep -qx \"# someone else's\" '$H/.local/share/bash-completion/completions/tmux'"

echo "## U13 --check"
H=$(mkhome u13)
printf '%s\n' 'if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi' > "$H/.profile"
printf '%s\n' 'if [ -f /usr/share/bash-completion/bash_completion ]; then . /usr/share/bash-completion/bash_completion; fi' >> "$H/.bashrc"
XPATH="$H/.local/bin" run "$H" >/dev/null 2>&1
XPATH="$H/.local/bin" run "$H" --check > "$T/u13.out" 2>&1; rc=$?
ok "after a full install: exit 0, no [!!], completion loads, not logged in is only a note" "[ $rc -eq 0 ] && ! grep -qF '[!!]' '$T/u13.out' && grep -qF 'bash 能加载 tmux 补全' '$T/u13.out' && grep -qF '[--] 还没登录' '$T/u13.out'"
echo "# local edit" >> "$H/.tmux.conf"
XPATH="$H/.local/bin" run "$H" --check --only tmux > "$T/u13b.out" 2>&1; rc=$?
ok "edited ~/.tmux.conf: exit 1, reported as not matching" "[ $rc -eq 1 ] && grep -qF '与 user-env 不一致' '$T/u13b.out'"
XPATH="$H/.local/bin" run "$H" --check --only claude-team --skip claude-team > "$T/u13c.out" 2>&1
ok "--check with nothing selected still exits 0" "[ \$? -eq 0 ]"
run "$H" --check --uninstall > "$T/u13d.out" 2>&1; ok "--check with --uninstall is rejected" "[ \$? -ne 0 ] && grep -q '不能和' '$T/u13d.out'"
h2=$(mkhome u13e); run "$h2" --check > "$T/u13e.out" 2>&1; rc=$?
ok "fresh machine: --check lists what is missing and changes nothing" "[ $rc -eq 1 ] && [ ! -e '$h2/.tmux.conf' ] && [ ! -e '$h2/.local' ] && grep -qF 'tmux.conf 不存在' '$T/u13e.out'"
ok "fresh machine: --check goes through every module (does not stop early)" "grep -qF 'bash 加载不到 tmux 补全' '$T/u13e.out' && grep -qF '== 提示符' '$T/u13e.out' && grep -qF '== claude-team' '$T/u13e.out' && grep -qF '检查完成' '$T/u13e.out'"

echo "## U14 preflight stops before any change when a dependency is missing"
H=$(mkhome u14); nojq="$T/nojq"; mkdir -p "$nojq"
for f in /usr/bin/*; do [ "${f##*/}" = jq ] || ln -s "$f" "$nojq/"; done
c0=$(sha256sum < "$H/.bashrc")
out=$(env -i HOME="$H" PATH="$H/fakebin:$nojq" SHELL=/bin/bash TMUX_TMPDIR="$(readlink "$H/tt")" LANG=en_US.UTF-8 bash "$U/setup-terminal-env.sh" 2>&1); rc=$?
ok "missing jq: exit 1, names jq + install command, nothing written" "[ $rc -ne 0 ] && echo \"\$out\" | grep -q 'jq' && echo \"\$out\" | grep -qF 'apt install' && [ ! -e '$H/.tmux.conf' ] && [ \"\$(sha256sum < '$H/.bashrc')\" = \"$c0\" ]"
out=$(env -i HOME="$H" PATH="$H/fakebin:$nojq" SHELL=/bin/bash TMUX_TMPDIR="$(readlink "$H/tt")" LANG=en_US.UTF-8 bash "$U/setup-terminal-env.sh" --skip claude-team 2>&1); rc=$?
ok "same machine with --skip claude-team: jq not needed, install succeeds" "[ $rc -eq 0 ] && [ -f '$H/.tmux.conf' ]"

echo
if [ "$FAILS" -eq 0 ]; then echo "全部通过"; else echo "失败 $FAILS 项"; exit 1; fi

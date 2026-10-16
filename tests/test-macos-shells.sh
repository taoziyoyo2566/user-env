#!/usr/bin/env bash
# 在容器里模拟 macOS 的 shell 版本：bash 3.2（macOS 自带）和 zsh 5.9（macOS 默认 shell）。
# 不能代替在真正的 Mac 上跑一次（容器里是 Linux 的命令行工具，不是 macOS 的 BSD 工具）。
# 前提：docker 可用；本机已运行过一次 setup-terminal-env.sh --only tmux（复用 ~/.tmux/plugins，容器里不联网下载插件）。
# 会拉取 bash:3.2 和 zshusers/zsh:5.9 两个镜像，跑完删掉本次新拉的；bash 3.2 容器里用 apk 装 tmux/git/jq（需要联网）。
# 用法：bash tests/test-macos-shells.sh        全部通过时退出码为 0
set -u
U=$(cd "$(dirname "$0")/.." && pwd)
PLUGINS=$HOME/.tmux/plugins
[ -d "$PLUGINS/tpm" ] || { echo "先在本机运行一次：bash $U/setup-terminal-env.sh --only tmux"; exit 2; }
command -v docker >/dev/null || { echo "缺少 docker"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/user-env-ctest.XXXXXX")
PULLED=""
cleanup() {
  local img
  for img in $PULLED; do docker rmi -f "$img" >/dev/null 2>&1; done
  rm -rf "$T"
}
trap cleanup EXIT
for img in bash:3.2 zshusers/zsh:5.9; do
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    docker pull -q "$img" >/dev/null || { echo "拉取 $img 失败"; exit 2; }
    PULLED="$PULLED $img"
  fi
done
cp -r "$PLUGINS" "$T/plugins"

# ── bash 3.2：完整安装、重复运行、--check、卸载 ──
cat > "$T/bash32.sh" <<'EOF'
set -u
apk add --no-cache tmux git jq >/dev/null 2>&1 || { echo "FAIL apk add"; exit 1; }
H=/root/h; mkdir -p $H/.tmux $H/fakebin /tmp/t
cp -r /plugins $H/.tmux/plugins    # 不用 cp -a：保留宿主机属主会让容器里的 git 拒绝操作这些仓库
printf '#!/bin/sh\necho "FAKE claude CFG=${CLAUDE_CONFIG_DIR:-<unset>}"\n' > $H/fakebin/claude; chmod +x $H/fakebin/claude
printf '%s\n' '# demo' 'export DEMO=1' > $H/.bashrc
R() { env -i HOME=$H PATH=$H/fakebin:/usr/local/bin:/usr/bin:/bin SHELL=/usr/local/bin/bash TMUX_TMPDIR=/tmp/t LANG=C.UTF-8 /usr/local/bin/bash /ue/setup-terminal-env.sh "$@"; }
ok() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fi; }
echo "  bash $BASH_VERSION"
ok "bash 3.2 parses setup-terminal-env.sh and the tmux completion" "bash -n /ue/setup-terminal-env.sh && bash -n /ue/files/tmux-completion.bash"
R > /tmp/o1 2>&1; ok "full install" "[ \$? -eq 0 ]" || cat /tmp/o1
ok "files in place" "grep -qF 'tmux display -p' $H/.bashrc && [ -x $H/.local/bin/claude-team ] && grep -qxF 'set -g @catppuccin_application_icon \"\"' $H/.tmux.conf && [ -f $H/.local/share/bash-completion/completions/tmux ]"
R > /tmp/o2 2>&1; ok "rerun is a no-op" "[ \$? -eq 0 ] && [ \$(grep -c '未变化' /tmp/o2) -ge 4 ]"
R --check > /tmp/o3 2>&1; ok "--check runs under bash 3.2 (no shell errors)" "grep -q '检查完成' /tmp/o3 && ! grep -qiE 'syntax error|unbound variable|command not found' /tmp/o3"
out=$(env -i HOME=$H PATH=$H/.local/bin:$H/fakebin:/usr/bin:/bin claude-team </dev/null); ok "wrapper runs under busybox sh" "[ \"\$out\" = \"FAKE claude CFG=$H/.claude-team\" ]"
R --uninstall > /tmp/o4 2>&1; ok "uninstall" "[ \$? -eq 0 ] && [ ! -e $H/.local/bin/claude-team ] && ! grep -qF tmux-prompt $H/.bashrc"
env -i PATH=/usr/bin:/bin TMUX_TMPDIR=/tmp/t tmux kill-server 2>/dev/null; true
EOF

# ── zsh 5.9：提示符函数、重复加载、安装脚本给 zsh 用户建 ~/.zshrc、交互式提示符 ──
cat > "$T/zsh.sh" <<'EOF'
mkdir -p /fake /root/h; printf '#!/bin/sh\necho "${FAKE_SESSION:-demo}"\n' > /fake/tmux; chmod +x /fake/tmux
ok() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fi; }
ok "zsh -n prompt.zsh" "zsh -n /ue/files/prompt.zsh"
r=$(TMUX=/tmp/x,1,0 TMUX_PANE=%1 zsh -f -c '
  PATH=/fake:$PATH; PROMPT="%n@%m %~ %# "
  source /ue/files/prompt.zsh
  _user_env_tmux_prompt; p1=$PROMPT; _user_env_tmux_prompt
  [[ $PROMPT == $p1 ]] || { print stack; exit; }
  PROMPT="%n@%m %~ %# "; _user_env_tmux_prompt; [[ $PROMPT == $p1 ]] || { print reset; exit; }
  source /ue/files/prompt.zsh; _user_env_tmux_prompt; [[ $PROMPT == $p1 ]] || { print resource; exit; }
  n=$(print -l $precmd_functions | grep -c "^_user_env_tmux_prompt\$"); [[ $n == 1 ]] || { print hook$n; exit; }
  FAKE_SESSION="de%mo" _user_env_tmux_prompt; print -P -- "$PROMPT" | grep -q "tmux:de%mo " || { print percent; exit; }
  print good')
ok "prompt: no stacking, theme reset, re-source, single hook, % escaped" "[ \"\$r\" = good ]"
r=$(zsh -f -c 'PROMPT="plain> "; source /ue/files/prompt.zsh; (( ${+functions[_user_env_tmux_prompt]} == 0 )) && [[ $PROMPT == "plain> " ]] && print good')
ok "outside tmux: nothing installed" "[ \"\$r\" = good ]"
env -i HOME=/root/h PATH=/usr/bin:/bin SHELL=/bin/zsh bash /ue/setup-terminal-env.sh --only prompt >/tmp/o 2>&1
ok "installer creates ~/.zshrc for a zsh user (no .bashrc)" "grep -qF 'add-zsh-hook precmd' /root/h/.zshrc && [ ! -e /root/h/.bashrc ]"
first=$(printf 'exit\n' | env -i HOME=/root/h PATH=/fake:/usr/bin:/bin TERM=xterm-256color TMUX=/tmp/x,1,0 TMUX_PANE=%1 FAKE_SESSION=saberu \
  script -qec 'zsh -i' /dev/null 2>&1 | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' | grep -c 'tmux:saberu ')
ok "interactive zsh shows tmux:saberu in the prompt" "[ \"\$first\" -ge 1 ]"
EOF

echo "## bash 3.2"
docker run --rm -v "$U":/ue:ro -v "$T/plugins":/plugins:ro -v "$T/bash32.sh":/t.sh:ro bash:3.2 bash /t.sh 2>&1 | tee "$T/bash32.out"
echo "## zsh 5.9"
docker run --rm --network none -v "$U":/ue:ro -v "$T/zsh.sh":/t.sh:ro zshusers/zsh:5.9 bash /t.sh 2>&1 | tee "$T/zsh.out"
echo
fails=$(cat "$T/bash32.out" "$T/zsh.out" | grep -c 'FAIL')
passes=$(cat "$T/bash32.out" "$T/zsh.out" | grep -c 'PASS')
if [ "$fails" -eq 0 ] && [ "$passes" -gt 0 ]; then echo "全部通过（$passes 项）"; else echo "失败 $fails 项"; exit 1; fi

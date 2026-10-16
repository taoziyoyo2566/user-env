# user-env

为当前用户统一配置终端环境：tmux（主题、会话持久化、醒目的 tmux 标识、会话名补全）、
提示符里的 tmux 标识、claude-team（Team 账号的 Claude Code）。

支持 Debian 系 Linux 和 macOS；只改家目录，不需要 root；可以重复运行，改动前先备份。

## 部署到一台新机器

### 1. 装依赖

```bash
# Debian / Ubuntu
sudo apt install git tmux jq bash-completion

# macOS（Homebrew）
brew install git tmux jq
brew install bash-completion@2     # 只有登录 shell 是 bash 时才需要，按 brew 的提示在 ~/.bash_profile 里加载
```

- tmux 需要 3.2 及以上。较老的发行版（如 Debian 11、Ubuntu 20.04）自带的版本不够，安装脚本会提示。
- 要用 claude-team 的机器还需要先装好 Claude Code；不用的机器安装时加 `--skip claude-team`，也就不需要 jq。
- 依赖缺了什么，安装脚本会在改动任何文件之前一次列出来，并给出安装命令。

### 2. 把 user-env 拷到目标机器

在已有 user-env 的机器上执行（`HOST` 换成目标机器的 SSH 名称）：

```bash
rsync -a ~/workspace/projects/user-env/ HOST:~/user-env/
# 没有 rsync 时：scp -r ~/workspace/projects/user-env HOST:~/
```

### 3. 在目标机器上安装并检查

```bash
ssh HOST
bash ~/user-env/setup-terminal-env.sh            # 不用 claude-team 的机器：加 --skip claude-team
bash ~/user-env/setup-terminal-env.sh --check    # 只读检查：全是 [OK] 就对了；[--] 只是提示，[!!] 需要处理
```

- 终端字体是 Nerd Font、想保留 tmux 状态栏图标时，安装加 `--nerd-font`。
- 已经开着的终端执行一次 `exec bash`（zsh 用 `exec zsh`）后生效；新终端自动生效。
- tmux 正在运行时，安装脚本会自动重新加载配置，已有会话不受影响。
- 第一次运行 `claude-team` 时登录 Team 组织，进去后用 `/status` 确认。

## 日常使用（速查）

### tmux

前缀键是 `Ctrl+a`：先按 `Ctrl+a`，松开，再按后面的键。

| 想做的事 | 怎么做 |
|---|---|
| 新建会话 | `tmux new -s 名字` |
| 列出会话 | `tmux ls` |
| 连回会话（在 tmux 外） | `tmux a -t 名字`，名字可以按 Tab 补全 |
| 在 tmux 里换到别的会话 | `Ctrl+a s`，用方向键选 |
| 暂时离开（会话继续在后台跑） | `Ctrl+a d` |
| 新窗口（沿用当前目录） | `Ctrl+a c` |
| 切换窗口 | `Ctrl+a 1`…`9`；窗口列表 `Ctrl+a w` |
| 左右分屏 / 上下分屏 | `Ctrl+a \|` / `Ctrl+a -` |
| 放大或还原当前窗格 | `Ctrl+a z` |
| 关闭当前窗格 | `Ctrl+a x`（会先确认） |
| 往上翻看输出 | 鼠标滚轮；或 `Ctrl+a [` 后用方向键/PageUp，按 `q` 退出 |
| 重新加载配置 | `Ctrl+a R` |
| 手动保存 / 恢复全部会话 | `Ctrl+a Ctrl+s` / `Ctrl+a Ctrl+r`（平时每 15 分钟自动保存，tmux 启动时自动恢复） |
| 查看全部快捷键 | `Ctrl+a ?`（按 `q` 退出） |

鼠标已开启：点击切换窗格，拖动边框调整大小。

怎么知道自己在不在 tmux 里：左下角有绿底 `tmux: 会话名`，提示符最前面也有绿底 `tmux:会话名`。
已经在 tmux 里时不要再运行 `tmux a`（tmux 会拒绝嵌套），换会话用 `Ctrl+a s`。

### claude-team

| 想做的事 | 怎么做 |
|---|---|
| 用 Team 账号开 Claude | `claude-team`（参数和 `claude` 一样，比如 `claude-team -c` 继续上一次会话） |
| 用个人账号开 Claude | `claude` |
| 确认当前是哪个账号 | 会话里输入 `/status`；Team 会话底部状态栏最前面有紫色 TEAM |
| 第一次使用 | 运行 `claude-team`，选主题，登录时选 Team 组织 |
| 查看 Claude 的命令行参数 | `claude-team --help`（和 `claude --help` 相同） |

## 更新

在源机器上改 `files/` 里的内容，拷到目标机器，再运行一次 `setup-terminal-env.sh`：
有变化的文件先备份为 `<文件>.bak.<时间>` 再覆盖，没变化的不动。

`setup-terminal-env.sh --check` 会指出哪些文件和 user-env 不一致（手动改过，或 user-env 有更新）。

## 命令一览

```bash
bash setup-terminal-env.sh                       # 安装或更新全部模块
bash setup-terminal-env.sh --only tmux,prompt    # 只处理列出的模块
bash setup-terminal-env.sh --skip claude-team    # 跳过列出的模块
bash setup-terminal-env.sh --nerd-font           # tmux 保留 catppuccin 的 Nerd Font 图标
bash setup-terminal-env.sh --check               # 只读检查，可配合 --only/--skip；有 [!!] 时退出码为 1
bash setup-terminal-env.sh --uninstall           # 撤销 prompt、claude-team 和 tmux 补全（~/.tmux.conf 不自动撤销）
```

## 每个模块改什么

| 模块 | 改动 |
|---|---|
| `tmux` | 用 `files/tmux.conf` 生成 `~/.tmux.conf`；安装 TPM 和插件；tmux 正在运行时重新加载；安装 tmux 的 bash 补全到 `~/.local/share/bash-completion/completions/tmux`（`tmux a -t <Tab>` 列出会话名；zsh 自带 tmux 补全，不需要它） |
| `prompt` | 在 `~/.bashrc` / `~/.zshrc` 里写入 `# >>> tmux-prompt >>>` 标记的一段：在 tmux 里时提示符前显示绿底 `tmux:会话名` |
| `claude-team` | 安装 `~/.local/bin/claude-team`；建 `~/.claude-team`（权限 700）；在 `~/.claude-team/settings.json` 设 TEAM 状态栏；`~/.local/bin` 不在 PATH 时在 rc 文件里加 `# >>> user-env-path >>>` 一段 |

已经存在、但不是本脚本装的 `~/.local/bin/claude-team` 或 tmux 补全文件不会被覆盖。

## claude-team

- `claude` 照常是个人账号（`~/.claude`），`claude-team` 是 Team 账号（`~/.claude-team`），两者可同时运行。
- Team 会话的标识：启动时一行紫色 TEAM；Claude 底部状态栏最前面紫色 TEAM（其余内容沿用个人账号的状态栏）；
  在 tmux 里该窗格背景变深紫，Claude 退出后自动恢复。
- 改窗格颜色：`CLAUDE_TEAM_TMUX_STYLE='bg=#1f2a44' claude-team`；设为 `none` 只做标记不变色。
- 两个账号的会话记录、记忆（auto-memory）和同步的插件/技能各自独立。

## 测试（改了 user-env 之后跑）

```bash
bash tests/test-linux.sh        # Linux 上的完整测试，每个用例用独立的 HOME 和 tmux socket，不碰真实配置
bash tests/test-macos-shells.sh   # 用容器模拟 macOS 的 bash 3.2 和 zsh 5.9（需要 docker，会临时拉镜像）
```

两者都要求本机已经运行过一次 `setup-terminal-env.sh --only tmux`（复用已下载的插件）。
容器测试不能代替真正的 Mac：第一次在 Mac 上部署时，装完跑一次 `--check`。

## 文件

```
setup-terminal-env.sh                        安装、检查、撤销
files/tmux.conf                   tmux 主配置；# @@USER_ENV_ICONS@@ 这一行由安装脚本替换
files/tmux-plain-icons.conf       没有 Nerd Font 时插入的图标替换
files/tmux-completion.bash        tmux 的 bash 补全（子命令、-t/-s 后的会话名）
files/prompt.bash                 写入 ~/.bashrc 的那一段
files/prompt.zsh                  写入 ~/.zshrc 的那一段
files/local-bin-path.sh                     把 ~/.local/bin 加进 PATH 的那一段
files/claude-team                 claude-team 命令本身
files/claude-team-statusline.sh   Team 状态栏命令（写进 settings.json）
tests/test-linux.sh                    Linux 测试
tests/test-macos-shells.sh               bash 3.2 / zsh 5.9 容器测试
```

## 以后改用 Ansible

计划（2026-10-16）：先作为独立配置保存在这里，不进任何仓库；以后可能并入 saberu 项目，用 Ansible 统一配置。
只支持 Debian 系和 macOS。

`files/` 里的内容可以直接复用，安装逻辑对应：

| 这里 | Ansible |
|---|---|
| 生成 `~/.tmux.conf` | `template`：把 `# @@USER_ENV_ICONS@@` 换成 `{% if not nerd_font %}…{% endif %}` |
| rc 文件里的标记段 | `blockinfile`：`marker: "# {mark} tmux-prompt {mark}"`、`marker_begin: ">>>"`、`marker_end: "<<<"`，会直接接管已有的同名段 |
| `~/.local/bin/claude-team` | `copy`，`mode: "0755"` |
| tmux 补全 | `copy` 到 `~/.local/share/bash-completion/completions/tmux` |
| settings.json 里的 statusLine | `slurp` + `combine` 后用 `copy` 写回 |
| TPM 和插件 | `git` + `command`（`~/.tmux/plugins/tpm/bin/install_plugins`） |
| `--check` | 用 `--check --diff` 模式运行同一个 playbook |

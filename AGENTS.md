# user-env

为当前用户配置终端环境：tmux、提示符里的 tmux 标识、claude-team（Team 账号的
Claude Code）。支持 Debian 系 Linux 和 macOS。面向人的说明（部署步骤、日常速查、
每个模块改什么、以后改用 Ansible 的计划）在 `README.md`；这里只记 agent 需要的项目事实。

## 结构

- `setup-terminal-env.sh`：安装、`--check` 只读检查、`--uninstall` 撤销；模块是
  `tmux`、`prompt`、`claude-team`，用 `--only` / `--skip` 选择。脚本只负责把
  `files/` 放到位。
- `files/`：配置内容本身，以后改用 Ansible 时直接复用；每个文件的用途见 README「文件」。
- `tests/`：`test-linux.sh` 是 Linux 上的完整测试；`test-macos-shells.sh` 在 docker
  容器里用 bash 3.2 和 zsh 5.9 测试。

## 命令

没有构建步骤。

```bash
bash setup-terminal-env.sh --check   # 只读检查本机；有 [!!] 时退出码为 1
bash tests/test-linux.sh             # 每个用例用独立的 HOME 和 tmux socket，不碰真实配置
bash tests/test-macos-shells.sh      # 需要 docker 和网络；临时拉 bash:3.2、zshusers/zsh:5.9，跑完删掉新拉的
```

两个测试都要求本机已经运行过一次 `setup-terminal-env.sh --only tmux`（复用
`~/.tmux/plugins`），改了 `files/tmux.conf` 里插件的固定版本后要在本机重新运行一次；
`test-linux.sh` 还需要 tmux、git、jq、python3、bash-completion。
容器测试代替不了真正的 Mac。

## 约束

- 在本机不带 `--check` 运行 `setup-terminal-env.sh`（安装、更新、`--uninstall`）会改
  操作者真实的家目录和正在运行的 tmux；部署到其他机器（拷过去再运行）是改外部主机。
  两者都要先得到操作者授权。验证改动用 `tests/` 和 `--check`。
- 保持脚本的这些性质：只改家目录、不需要 root；可以重复运行；内容没变就不写，变了先备份为
  `<文件>.bak.<时间>`；不覆盖不是本脚本装的文件。
- 兼容性：`setup-terminal-env.sh` 和写进 bash 的 `files/` 片段要能在 macOS 自带的
  bash 3.2 下运行；`files/prompt.zsh` 面向 zsh 5.9；`files/claude-team` 是 POSIX `sh`；
  命令用法要同时兼容 GNU 和 macOS 的 BSD 工具（容器测试覆盖不到这一点）。tmux 要求 3.2 及以上。
- 识别标记不要随手改：rc 文件里 `# >>> 名称 >>>` / `# <<< 名称 <<<` 的格式与 Ansible
  `blockinfile` 的标记一致；`claude-team-wrapper-v1`、`claude-team-statusline-v1`、
  `user-env-tmux-completion-v1` 用来认出本脚本装过的文件。改了标记，已经装过的机器就会被当成
  别人的文件，脚本会拒绝覆盖或撤销，或者跳过不更新；要改就让脚本同时认旧标记。
- `files/tmux.conf` 里 `# @@USER_ENV_ICONS@@` 必须正好一行；`status-right` 要在
  `run tpm` 之前设置（原因见文件里的注释）。
- `--help` 打印的是 `setup-terminal-env.sh` 第 2–19 行的注释；改这段注释的行数时同步改
  那条 `sed -n` 的范围。
- 改了 `files/`、模块或参数时，同步 README 里对应的表格、命令一览和「文件」一节。

## 文件检查

- shell 文件：`bash -n`（`files/prompt.zsh` 用 `zsh -n`，`files/claude-team` 用
  `sh -n`），再跑 `shellcheck`；接受的警告在代码里用 `# shellcheck disable=` 写明理由。
- tmux 配置和各模块的实际效果由 `tests/test-linux.sh` 检查。

## Git

- 主分支 `main`；没有远程仓库（README：先作为独立配置保存在这里，不进任何仓库）。
- 提交信息沿用已有风格：`类型: 中文描述`，如 `feat:`、`docs:`。
- 每个改动在从 `main` 拉出的短期分支上提交；分支名以和提交信息相同的类型开头，如
  `docs/`、`feat/`，后面跟主题。
- 合并方式：快进合并（`git merge --ff-only`）到 `main`。

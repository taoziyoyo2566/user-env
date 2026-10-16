# tmux 的 bash 补全（user-env 安装到 bash-completion 的用户目录，用到 tmux 时自动加载）
#   tmux <Tab>            子命令，如 attach-session、new-session、kill-session
#   tmux a -t <Tab>       会话名；-s 后面同样补全会话名（new -s 后面是新名字，不补全）
#   其他位置              补全文件名（如 source-file 的配置文件）
# 带 -L / -S 时，从对应的 tmux 服务器取会话名。
# user-env-tmux-completion-v1

# 把 compgen 的输出逐行放进 COMPREPLY：按行拆分，不做通配符展开
_user_env_tmux_reply() {
  local line
  while IFS= read -r line; do COMPREPLY+=("$line"); done
}

_user_env_tmux() {
  local cur prev i word cmd="" IFS=$'\n'
  local -a server=()
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}
  COMPREPLY=()

  # 找出子命令，并记下 -L/-S 指定的服务器；-L -S -f -c -T 这几个全局选项后面跟一个参数
  i=1
  while [ "$i" -lt "$COMP_CWORD" ]; do
    word=${COMP_WORDS[i]}
    case $word in
      -L|-S) server+=("$word" "${COMP_WORDS[i+1]}"); i=$((i + 2)); continue ;;
      -f|-c|-T) i=$((i + 2)); continue ;;
      -*) ;;
      *) cmd=$word; break ;;
    esac
    i=$((i + 1))
  done

  if [ -n "$cmd" ] && { [ "$prev" = -t ] || [ "$prev" = -s ]; }; then
    case $cmd:$prev in
      new:-s|new-session:-s) ;;
      *) _user_env_tmux_reply < <(compgen -W "$(tmux ${server[@]+"${server[@]}"} list-sessions -F '#S' 2>/dev/null)" -- "$cur") ;;
    esac
    # 没有可补的会话时也不退回文件名补全，免得误以为能连
    if type compopt >/dev/null 2>&1; then compopt +o default 2>/dev/null; fi
    return 0
  fi
  if [ -z "$cmd" ] && [ "${cur#-}" = "$cur" ]; then
    _user_env_tmux_reply < <(compgen -W "$(tmux list-commands -F '#{command_list_name}' 2>/dev/null
                                          tmux list-commands -F '#{command_list_alias}' 2>/dev/null)" -- "$cur")
    return 0
  fi
  # 其余情况交给默认的文件名补全（complete -o default）
}

complete -o default -F _user_env_tmux tmux

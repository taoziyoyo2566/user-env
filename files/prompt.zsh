# 在 tmux 里时，提示符最前面显示绿底「tmux:会话名」，避免忘了自己已经在 tmux 里
if [[ -n "${TMUX:-}" ]]; then
  : ${_user_env_tmux_prefix=}
  _user_env_tmux_prompt() {
    local s
    s=$(tmux display -p -t "$TMUX_PANE" '#S' 2>/dev/null)
    # 先去掉上一次加的前缀：不管主题每次重设提示符还是不重设，前缀都只出现一次
    PROMPT=${PROMPT#"$_user_env_tmux_prefix"}
    _user_env_tmux_prefix="%K{green}%F{black}%B tmux:${s//\%/%%} %b%f%k "
    PROMPT=$_user_env_tmux_prefix$PROMPT
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _user_env_tmux_prompt
fi

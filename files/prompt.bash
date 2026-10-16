# 在 tmux 里时，提示符最前面显示绿底「tmux:会话名」，避免忘了自己已经在 tmux 里
if [ -n "${TMUX:-}" ]; then
  PS1='\[\033[1;30;42m\] tmux:$(tmux display -p -t "$TMUX_PANE" "#S" 2>/dev/null) \[\033[00m\] '"$PS1"
fi

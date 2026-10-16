# claude-team 等命令装在 ~/.local/bin，确保它在 PATH 里（bash 和 zsh 通用）
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
esac

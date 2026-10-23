# Source this file from zsh. Resolve the root from this file, not the current directory.
typeset -g SHELL_COMMAND_HUB="${${(%):-%x}:A:h:h}"
# Retire only the ZIP aliases registered by earlier versions of this toolbox.
if [[ ${aliases[tidy]-} == "${(q)SHELL_COMMAND_HUB}/hub run zip-tidy" ||
      ${aliases[tidy]-} == "sh $HOME/Sites/zip-tidy.sh" ]]; then
  unalias tidy
fi
alias hub="${(q)SHELL_COMMAND_HUB}/hub"
alias vinfo="${(q)SHELL_COMMAND_HUB}/hub tui media-info"
alias zidy="${(q)SHELL_COMMAND_HUB}/hub tui zip-tidy"
alias pinfo="${(q)SHELL_COMMAND_HUB}/hub tui port-info"

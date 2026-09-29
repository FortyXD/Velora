setopt auto_cd
setopt auto_pushd pushd_ignore_dups pushd_silent
setopt auto_list auto_menu auto_param_slash complete_in_word
typeset -U path PATH

if [[ -d /opt/anaconda ]]; then
  export OPENSSL_MODULES=/opt/anaconda/lib/ossl-modules
  export CONDA_EXE=/opt/anaconda/bin/conda
  export _CONDA_EXE=/opt/anaconda/bin/conda
  export CONDA_PYTHON_EXE=/opt/anaconda/bin/python
  export _CONDA_ROOT=/opt/anaconda
  export CONDA_PREFIX=/opt/anaconda
  export CONDA_DEFAULT_ENV=base
  export CONDA_PROMPT_MODIFIER='(base) '
  export CONDA_SHLVL=1
  path=(/opt/anaconda/bin /opt/anaconda/condabin $path)

  __conda_lazy_load() {
    unfunction conda 2>/dev/null || true
    source /opt/anaconda/etc/profile.d/conda.sh
  }

  conda() {
    __conda_lazy_load
    conda "$@"
  }
fi

if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b)"
fi

autoload -Uz compinit
zmodload zsh/complist

zstyle ':completion:*' menu select=1
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%F{cyan}%d%f'
zstyle ':completion:*:warnings' format '%F{red}No matches for: %d%f'
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' squeeze-slashes true

compinit

bindkey -M menuselect '^[[Z' reverse-menu-complete

source /usr/share/fzf/completion.zsh 2>/dev/null
source /usr/share/fzf/key-bindings.zsh 2>/dev/null

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias cat='bat'
alias grep='rg'

eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
source "$HOME/.config/quickshell/ii/scripts/supergfxctl.zsh"
export PATH="/usr/local/racket/bin:$PATH"

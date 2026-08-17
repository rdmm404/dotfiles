# Zap-zsh installation and plugin storage

## Findings

- **Zap itself** is installed at `${XDG_DATA_HOME:-$HOME/.local/share}/zap`. With the default XDG setting, that is `$HOME/.local/share/zap`. The installer clones the official Zap repository into this directory. [Official `install.zsh`, lines 29–46](https://github.com/zap-zsh/zap/blob/d8e74d3d97ded884d14079f98f0a328580e4f8dc/install.zsh#L29-L46)
- **Plugins** are cloned under `$ZAP_DIR/plugins`, exposed by Zap as `$ZAP_PLUGIN_DIR`. For a repository argument such as `zsh-users/zsh-autosuggestions`, Zap uses the argument’s final path component as the directory name: `${XDG_DATA_HOME:-$HOME/.local/share}/zap/plugins/zsh-autosuggestions`. [Official `zap.zsh`, lines 3–5 and 48–56](https://github.com/zap-zsh/zap/blob/d8e74d3d97ded884d14079f98f0a328580e4f8dc/zap.zsh#L3-L56)
- **Plugin source behavior:** `plug` clones a missing plugin directory with Git, then sources a matching plugin script from that directory. A second argument can select a Git ref. [Official `zap.zsh`, lines 53–64](https://github.com/zap-zsh/zap/blob/d8e74d3d97ded884d14079f98f0a328580e4f8dc/zap.zsh#L53-L64)
- **Zsh configuration:** the installer operates on `${ZDOTDIR:-$HOME}/.zshrc`; unless `--keep` is used, it appends the default template. That template sources `zap.zsh` and declares plugins with `plug`. [Official `install.zsh`, lines 29–30 and 48–67](https://github.com/zap-zsh/zap/blob/d8e74d3d97ded884d14079f98f0a328580e4f8dc/install.zsh#L29-L67) · [Official `templates/default-zshrc`](https://github.com/zap-zsh/zap/blob/d8e74d3d97ded884d14079f98f0a328580e4f8dc/templates/default-zshrc#L1-L10)
- **Completions** are stored in `$ZAP_DIR/completion` and added to Zsh’s `fpath`. [Official `zap.zsh`, lines 3–7](https://github.com/zap-zsh/zap/blob/d8e74d3d97ded884d14079f98f0a328580e4f8dc/zap.zsh#L3-L7)

## Local check

The local installation uses the default location `/home/rdmm123/.local/share/zap`. Its `plugins/` directory currently contains cloned repositories including `exa`, `forgit`, `fzf`, `git-open`, `supercharge`, `zap-prompt`, `zsh-autopair`, `zsh-autosuggestions`, `zsh-history-substring-search`, and `zsh-syntax-highlighting`, matching the storage rule above.

## Bottom line

Unless `XDG_DATA_HOME` is overridden, look in `$HOME/.local/share/zap/plugins/` for Zap-managed plugin repositories; look in `${ZDOTDIR:-$HOME}/.zshrc` for the `plug` declarations that cause them to be installed and sourced.

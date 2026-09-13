#!/usr/bin/env bash

ubuntu_command() {
  case "$1" in
    fd) printf fdfind ;;
    bat) printf batcat ;;
    *) app_command "$1" ;;
  esac
}

ubuntu_package() {
  case "$1" in
    fd) printf fd-find ;;
    rg) printf ripgrep ;;
    *) printf '%s' "$1" ;;
  esac
}

ubuntu_zap_plugin_install() {
  local name="$1" file="$2"
  [ -r "$(zap_path)/plugins/$name/$file" ] && return 0
  command -v git >/dev/null 2>&1 || ubuntu_apt git ca-certificates || return 1
  zap_install zsh || return 1
  mkdir -p "$(zap_path)/plugins" || return 1
  git clone --quiet --depth 1 "https://github.com/zap-zsh/$name.git" "$(zap_path)/plugins/$name"
}

installer_available() {
  case "$1" in
    zsh)
      zap_available zsh && zap_available zsh-syntax-highlighting &&
        [ -r "$(zap_path)/plugins/supercharge/supercharge.plugin.zsh" ]
      ;;
    zsh-autosuggestions|zsh-autopair|zsh-history-substring-search)
      zap_available "$1"
      ;;
    eza)
      command -v eza >/dev/null 2>&1 && [ -r "$(zap_path)/plugins/exa/eza.plugin.zsh" ]
      ;;
    git-open) [ -x "$(zap_path)/plugins/git-open/git-open" ] ;;
    rtk|herdr)
      command -v "$1" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$1" ]
      ;;
    # Pi's private rg must not hide a missing system command for SSH sessions.
    rg) [ -x /usr/bin/rg ] ;;
    stow|starship|zoxide|fzf|fd|bat|git|gh)
      command -v "$(ubuntu_command "$1")" >/dev/null 2>&1
      ;;
    *) return 2 ;;
  esac
}

ubuntu_apt() {
  command -v apt-get >/dev/null 2>&1 || { dot_error 'apt-get is required on Ubuntu'; return 1; }
  if [ "$(id -u)" = 0 ]; then
    apt-get install -y -- "$@"
  else
    command -v sudo >/dev/null 2>&1 || { dot_error 'sudo is required to install Ubuntu packages'; return 1; }
    sudo apt-get install -y -- "$@"
  fi
}

# Pinned upstream release assets, with SHA-256 digests published by GitHub.
# No remote setup scripts, latest-version lookups, or shell/agent initialization.
ubuntu_install_binary() (
  local app="$1" arch repository version asset digest tmp
  arch=$(uname -m)
  case "$app:$arch" in
    herdr:x86_64)
      digest=4fa1a01158dd8043da92d31b270780b0dcc10603038d9b61cac4d81ab63fb71f ;;
    herdr:aarch64)
      digest=9c8db20fb7e7427b138d5367113f1621ffd319f2f65d6f009e2594029115f0d2 ;;
    rtk:x86_64)
      digest=7278231dfd7e6a730a4ab7f847b195bcf02289c2d57622b0dab75a6411100c8f ;;
    rtk:aarch64)
      digest=c8ea4b6560841e73157c134fd4a3293914c6ede42e786ee985cf491fde691ba7 ;;
    *) dot_error "no pinned Ubuntu binary for $app on $arch"; return 1 ;;
  esac
  case "$app" in
    herdr)
      repository=herdrdev/herdr; version=v0.9.0; asset="herdr-linux-$arch" ;;
    rtk)
      repository=rtk-ai/rtk; version=v0.49.0
      case "$arch" in
        x86_64) asset=rtk-x86_64-unknown-linux-musl.tar.gz ;;
        aarch64) asset=rtk-aarch64-unknown-linux-gnu.tar.gz ;;
      esac
      ;;
  esac
  command -v curl >/dev/null 2>&1 || ubuntu_apt curl ca-certificates || return 1
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dot-binary.XXXXXX") || return 1
  trap 'rm -rf -- "$tmp"' EXIT
  curl --fail --location --proto '=https' --proto-redir '=https' \
    "https://github.com/$repository/releases/download/$version/$asset" \
    --output "$tmp/asset" || return 1
  printf '%s  %s\n' "$digest" "$tmp/asset" | sha256sum --check --status || {
    dot_error "checksum verification failed for $app"; return 1
  }
  if [ "$app" = rtk ]; then
    # Extract only the executable to stdout, never archive-controlled paths.
    tar -xOzf "$tmp/asset" rtk > "$tmp/$app" || return 1
  else
    mv "$tmp/asset" "$tmp/$app" || return 1
  fi
  mkdir -p "$HOME/.local/bin" || return 1
  install -m 755 "$tmp/$app" "$HOME/.local/bin/$app"
)

installer_install() {
  case "$1" in
    zsh)
      command -v git >/dev/null 2>&1 || ubuntu_apt git ca-certificates || return 1
      command -v zsh >/dev/null 2>&1 || ubuntu_apt zsh || return 1
      zap_install zsh &&
        { zap_available zsh-syntax-highlighting || zap_install zsh-syntax-highlighting; } &&
        ubuntu_zap_plugin_install supercharge supercharge.plugin.zsh
      ;;
    zsh-autosuggestions|zsh-autopair|zsh-history-substring-search)
      zap_install "$1"
      ;;
    eza)
      command -v eza >/dev/null 2>&1 || ubuntu_apt eza || return 1
      ubuntu_zap_plugin_install exa eza.plugin.zsh
      ;;
    git-open)
      command -v git >/dev/null 2>&1 || ubuntu_apt git ca-certificates || return 1
      zap_install zsh || return 1
      mkdir -p "$(zap_path)/plugins" || return 1
      git clone --quiet --depth 1 https://github.com/paulirish/git-open.git "$(zap_path)/plugins/git-open"
      ;;
    rtk|herdr) ubuntu_install_binary "$1" ;;
    stow|starship|zoxide|fzf|fd|rg|bat|git|gh)
      ubuntu_apt "$(ubuntu_package "$1")"
      ;;
    *) dot_error "unsupported on Ubuntu: $1"; return 1 ;;
  esac
}

# Variables
OS := $(shell uname -s)

# Targets
stow:
	stow */ -t ~

install:
ifeq ($(OS), Darwin)
	@echo "Detected macOS"
	@echo "Installing Homebrew..."
	@if ! command -v brew > /dev/null; then \
		/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
	fi
	@echo "Running Brew Bundle..."
	brew bundle --global
else
	@echo "Detected non-macOS system"
	@echo "Installing zsh..."
	@if ! command -v zsh > /dev/null; then \
		sudo apt-get install -y zsh || sudo yum install -y zsh; \
	fi
endif
	zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1>

.PHONY: stow install

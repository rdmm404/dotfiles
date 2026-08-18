# Configuration deployment is handled by ./dot. This compatibility target keeps
# the unrelated skills package available without stowing repository internals.
SHELL := /bin/bash

stow-skills:
	stow -R skills -t ~

.PHONY: stow-skills

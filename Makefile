# Builds go through klause itself, so RUNTIME from the global configuration
# and KLAUSE_RUNTIME apply here as well.
#
#   make                                     build all images klause:<variant>
#   make IMAGES="shell python"               build only these variants
#   make update                              rebuild with the latest Fedora packages and Claude Code
#   make CLAUDE_CODE_VERSION=2.1.301         pin the Claude Code version
#   make install [PREFIX=~/.local]           copy klause and its Dockerfile below $(PREFIX)

PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
DATADIR := $(PREFIX)/share/klause

# All stages of the Dockerfile
IMAGES ?= $(shell sed -nE 's/^FROM[[:space:]]+[^[:space:]]+[[:space:]]+AS[[:space:]]+([a-z0-9_.-]+)[[:space:]]*$$/\1/Ip' Dockerfile)

CLAUDE_CODE_VERSION ?=
FEDORA_VERSION ?=
BUILD_ARGS := $(if $(CLAUDE_CODE_VERSION),--build-arg CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)) \
              $(if $(FEDORA_VERSION),--build-arg FEDORA_VERSION=$(FEDORA_VERSION))

# A new CACHE_BUST rebuilds everything from the first package installation on.
# Unlike --no-cache per image, all images then share the new layers again.
CACHE_BUST := $(shell date +%s)

.PHONY: build update install uninstall check help

build:
	@set -e; for image in $(IMAGES); do ./klause --klause-build-base $$image $(BUILD_ARGS); done

update:
	@set -e; for image in $(IMAGES); do \
	    ./klause --klause-build-base $$image --pull --build-arg CACHE_BUST=$(CACHE_BUST) $(BUILD_ARGS); \
	done

# klause looks for the Dockerfile in ../share/klause relative to itself
install:
	install -D -m 755 klause "$(DESTDIR)$(BINDIR)/klause"
	install -D -m 644 Dockerfile "$(DESTDIR)$(DATADIR)/Dockerfile"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/klause" "$(DESTDIR)$(DATADIR)/Dockerfile"
	-rmdir "$(DESTDIR)$(DATADIR)" 2>/dev/null

check:
	bash -n klause
	shellcheck klause

help:
	@sed -n 's/^#   //p' $(firstword $(MAKEFILE_LIST))

# Builds go through klause itself, so RUNTIME from the global configuration
# and KLAUSE_RUNTIME apply here as well.
#
#   make                                     build klause:latest
#   make update                              rebuild with the latest Fedora packages and Claude Code
#   make CLAUDE_CODE_VERSION=2.1.301         pin the Claude Code version
#   make install [PREFIX=~/.local]           copy klause and its Dockerfile below $(PREFIX)

PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
DATADIR := $(PREFIX)/share/klause

CLAUDE_CODE_VERSION ?=
FEDORA_VERSION ?=
BUILD_ARGS := $(if $(CLAUDE_CODE_VERSION),--build-arg CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)) \
              $(if $(FEDORA_VERSION),--build-arg FEDORA_VERSION=$(FEDORA_VERSION))

.PHONY: build update install uninstall check help

build:
	./klause --klause-build-base $(BUILD_ARGS)

# Without --no-cache, the cached layers keep the old packages and Claude Code
update:
	./klause --klause-build-base --pull --no-cache $(BUILD_ARGS)

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

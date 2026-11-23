# Task-specific klause images as stages of one Dockerfile. Each stage is built
# with "--target <stage>" and tagged klause:<stage>; a project picks one with
# IMAGE=klause:<stage> in its .klause. The stages build on each other, so their
# common layers exist only once on disk:
#
#   shell                  shell tools, git, make, Python, Node.js, Claude Code
#   ├── php                PHP, Composer
#   └── devel              C/C++ toolchain
#       ├── python         Python development, ImageMagick, ffmpeg
#       └── node           Node.js development
#           ├── go         Go toolchain
#           └── rust       Rust toolchain
#
# Deliberately no sudo: root access is only available via "klause --klause-root-shell".

ARG FEDORA_VERSION=44

# ---------------------------------------------------------------------------
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS shell

# "make update" passes a new value to rebuild from here on without discarding
# the cache, so all images share the freshly built layers again. klause passes
# the value from the label to later builds, so they reuse these layers too.
ARG CACHE_BUST=
LABEL klause.cache-bust=${CACHE_BUST}

# Node.js is needed for Claude Code itself.
RUN dnf -y install --setopt=install_weak_deps=False \
        bash-completion ca-certificates curl diffutils file findutils gawk \
        gh git git-lfs gzip jq less make man-db openssh-clients patch procps-ng \
        ripgrep sed tar unzip which xz zip \
        ShellCheck shfmt \
        python3 python3-pip \
        nodejs npm \
    && dnf clean all

# Install Claude Code globally. Updates come via an image rebuild, not via
# the auto-updater (which cannot write as non-root anyway).
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && npm cache clean --force

ENV DISABLE_AUTOUPDATER=1 \
    LANG=C.UTF-8

# ---------------------------------------------------------------------------
FROM shell AS php

RUN dnf -y install --setopt=install_weak_deps=False \
        php-cli php-xml php-mbstring php-mysqlnd composer \
    && dnf clean all

# ---------------------------------------------------------------------------
# C/C++ toolchain: Python C extensions, native Node modules, cgo and the
# linker for Rust all need it.
FROM shell AS devel

RUN dnf -y install --setopt=install_weak_deps=False \
        gcc gcc-c++ pkgconf-pkg-config openssl-devel \
    && dnf clean all

# ---------------------------------------------------------------------------
FROM devel AS python

RUN dnf -y install --setopt=install_weak_deps=False \
        python3-devel poetry uv ruff \
        ImageMagick ffmpeg \
    && dnf clean all

# ---------------------------------------------------------------------------
FROM devel AS node

RUN dnf -y install --setopt=install_weak_deps=False \
        pnpm yarnpkg \
    && dnf clean all

# ---------------------------------------------------------------------------
FROM node AS go

RUN dnf -y install --setopt=install_weak_deps=False \
        golang gopls staticcheck golangci-lint golang-x-tools-goimports delve \
    && dnf clean all

# ---------------------------------------------------------------------------
FROM node AS rust

RUN dnf -y install --setopt=install_weak_deps=False \
        rust rustup cargo rustfmt clippy rust-analyzer rust-src \
    && dnf clean all

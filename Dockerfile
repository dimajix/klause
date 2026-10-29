ARG FEDORA_VERSION=44
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION}

# Base tools, Python and Rust toolchains from the Fedora repos.
# Deliberately no sudo: root access is only available via "klause --klause-root-shell".
RUN dnf -y install --setopt=install_weak_deps=False \
        bash-completion ca-certificates curl diffutils file findutils gawk \
        gh git git-lfs gzip jq less make man-db openssh-clients patch procps-ng \
        ripgrep sed tar unzip which xz zip \
        gcc gcc-c++ pkgconf-pkg-config openssl-devel \
        nodejs npm \
        python3 python3-pip python3-devel poetry uv \
        rust cargo rustfmt clippy rust-analyzer rust-src \
    && dnf clean all

# Install Claude Code globally. Updates come via an image rebuild, not via
# the auto-updater (which cannot write as non-root anyway).
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && npm cache clean --force

ENV DISABLE_AUTOUPDATER=1 \
    LANG=C.UTF-8

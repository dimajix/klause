# klause

Claude Code in a hermitage: `klause` runs Claude Code in a container that sees
only the current working directory (and a few configuration files) from the
host.

```sh
cd ~/projects/foo
klause                                   # like "claude", just in the container
klause --resume                          # all arguments are passed to claude
klause --dangerously-skip-permissions    # ... this one too, if you want
```

## Properties

- The current directory is mounted **under the same path**. Paths in output,
  sessions and `~/.claude/projects` match the host.
- The process runs with the **same UID, GID, all supplementary groups and the
  umask** of the caller. There is no `sudo` in the container.
- There is **one persistent container** per working directory with a
  deterministic name (`klause-<directory>-<hash>`). Multiple `klause`
  invocations in the same directory run as parallel instances in the same
  container.
- If no instance has been running for `IDLE_TIMEOUT` seconds (default: 300),
  the container **stops**. It is not deleted. It is started again on the next
  invocation, and everything installed in the container is still there
  (`pip install --user`, `cargo install`, `npm` packages in the home directory,
  dnf packages installed via `--klause-root-shell`).
- The home directory in the container has the same path as on the host, but
  lives inside the container. Only the following are mounted:

  | Host                 | Mode |
  |----------------------|------|
  | Working directory    | rw   |
  | `.klause` in it      | ro   |
  | `~/.claude`          | rw   |
  | `~/.claude/ide`      | ro   |
  | `~/.gitconfig`       | ro   |
  | `~/.config/git`      | ro   |
  | Entries from `MOUNTS`| as configured |

### Note on `~/.claude.json`

Claude Code writes `~/.claude.json` via an atomic rename. A bind mount of this
single file would therefore become stale on the host after the first write.
For this reason, `CLAUDE_CONFIG_DIR=~/.claude` is set in the container, and the
global configuration lives in `~/.claude/.claude.json` there. On first start,
klause copies the host's `~/.claude.json` there once. After that, all klause
containers share this file, but it is independent of the host's. Login
(`~/.claude/.credentials.json`), settings, hooks, plugins and sessions are
shared anyway. To take it over from the host again, delete
`~/.claude/.claude.json`.

### IDE integration (PyCharm, VS Code, ...)

IDE plugins can start `klause` instead of `claude` (in PyCharm: plugin setting
for the Claude command). For claude in the container to connect to the IDE:

- Set `NETWORK=host`, globally or in `.klause`, and recreate the container with
  `klause --klause-rm`. claude connects to the IDE plugin via `127.0.0.1`, which
  in a `bridge` container is the container itself. klause points this out when
  started by an IDE.
- klause passes the variables the plugin sets (`CLAUDE_CODE_SSE_PORT`,
  `ENABLE_IDE_INTEGRATION`, `TERMINAL_EMULATOR`, `TERM_PROGRAM`,
  `TERM_PROGRAM_VERSION`) into the container.
- The IDE announces itself via a lock file in `~/.claude/ide` with its process
  ID. claude deletes lock files whose process it cannot see, and from inside the
  container that is every IDE. That would break the integration for claude on
  the host too, so `~/.claude/ide` is mounted read-only.

Limitation: when the IDE starts klause itself, claude finds the IDE by the port
in `CLAUDE_CODE_SSE_PORT`. Running `klause` by hand in the IDE's terminal
connects only if `CLAUDE_CODE_SSE_PORT` is set there as well. Otherwise claude
checks that the IDE is one of its parent processes, which it cannot see in the
container.

## Installation

```sh
make install              # copies klause into ~/.local/bin (PREFIX=... for elsewhere)
make                      # builds all images klause:<variant>; optional, otherwise each is built on first use
```

`make install` copies the Dockerfile to `~/.local/share/klause`. klause looks
for it next to the (resolved) script first, then in `../share/klause` relative
to it. After changes to the repository, run `make install` again. To work on
klause itself, link the script instead (`ln -s "$PWD/klause" ~/.local/bin/`);
it then uses the Dockerfile in the repository.

The Makefile calls `klause --klause-build-base`, so `RUNTIME` from the
configuration applies.

| Target                             | Effect |
|------------------------------------|--------|
| `make` / `make build`              | Build all [images](#images) `klause:<variant>` |
| `make IMAGES="shell python"`       | Build only these variants (also with `update`) |
| `make update`                      | Rebuild with `--pull` and a new `CACHE_BUST`: latest Fedora packages and Claude Code |
| `make CLAUDE_CODE_VERSION=2.1.301` | Pin the Claude Code version (also `FEDORA_VERSION=...`) |
| `make install` / `make uninstall`  | Install or remove `$(PREFIX)/bin/klause` and `$(PREFIX)/share/klause/Dockerfile` (default `~/.local`, `DESTDIR` is supported) |
| `make check`                       | `bash -n` and `shellcheck` on the script |

Containers keep their image after a rebuild; recreate them with
`klause --klause-rm` to use the new one.

## Commands

klause's own commands start with `--klause-` and are only recognized as the
**first** argument. Everything else is passed to claude.

| Command                 | Effect |
|-------------------------|--------|
| `--klause-help`         | Help |
| `--klause-build [...]`  | Build the [project image](#project-image) if there is a `.klause/Dockerfile`, otherwise the [image](#images) in use; further arguments are passed to `docker build` (e.g. `--build-arg CLAUDE_CODE_VERSION=2.1.301`) |
| `--klause-build-base [variant] [...]` | Build image `klause:<variant>`, by default the one this directory uses or builds on, even in a project with its own Dockerfile |
| `--klause-shell`        | Bash in the container as the caller |
| `--klause-root-shell`   | Bash in the container as root, e.g. for `dnf install` |
| `--klause-status`       | Name, state and configuration of the container for this directory |
| `--klause-list`         | All klause containers |
| `--klause-stop`         | Stop the container |
| `--klause-rm`           | Delete the container; anything installed in it is lost |

## Configuration

- global: `~/.config/klause` (or `$XDG_CONFIG_HOME/klause`). If the file
  does not exist, klause creates it with a commented-out example of all keys.
- per project: `.klause` in the current directory, either as a file or as a
  directory with the configuration in `.klause/config` and optionally a
  [Dockerfile](#project-image)
- the environment variables `KLAUSE_RUNTIME`, `KLAUSE_IMAGE`, `KLAUSE_NETWORK`,
  `KLAUSE_IDLE_TIMEOUT` take precedence

Format: one `KEY=VALUE` line per entry, `#` starts a comment, values may be
quoted. The files are **parsed, not executed**. The project file overrides the
global one; for `MOUNTS`, `PASS_ENV` and `CONTAINER_ARGS` the values are
concatenated.

| Key              | Default         | Meaning |
|------------------|-----------------|---------|
| `RUNTIME`        | `docker`        | `docker` or `podman` (rootless, with `--userns=keep-id`) |
| `IMAGE`          | `klause:shell`  | Image to use. It needs `sh` and `claude`. Only the [bundled images](#images) `klause:<variant>` and project images are built automatically when needed. With a project Dockerfile, the project `IMAGE` is the tag of the project image. |
| `BASE_IMAGE`     | `IMAGE` from the global configuration | Base image for a [project Dockerfile](#project-image), e.g. `klause:python`; ignored without one |
| `NETWORK`        | `bridge`        | `host` gives access to local services (e.g. MCP servers on `localhost`) |
| `IDLE_TIMEOUT`   | `300`           | Seconds without an instance until the container stops; `0` = never |
| `MOUNTS`         |                 | Space-separated: `path`, `path:ro`, `source:target`, `source:target:ro`. `~` and relative paths are resolved. |
| `PASS_ENV`       |                 | Names of environment variables to pass through (e.g. `ANTHROPIC_API_KEY`) |
| `CONTAINER_ARGS` |                 | Additional arguments for `docker create` |

A key may appear several times in one file; for `MOUNTS`, `PASS_ENV` and
`CONTAINER_ARGS` the lines are concatenated as well. Comments must be on lines
of their own, not after a value.

Example `~/.config/klause` that shares the typical package caches with the
host (sources that do not exist are skipped with a warning):

```ini
# Maven (only the repository: ~/.m2/settings.xml may hold credentials)
MOUNTS="~/.m2/repository"
# Gradle
MOUNTS="~/.gradle/caches ~/.gradle/wrapper"
# npm, Yarn
MOUNTS="~/.npm ~/.cache/yarn"
# pip, Poetry, uv
MOUNTS="~/.cache/pip ~/.cache/pypoetry ~/.cache/uv"
# Cargo and configuration; if it sets build.target-dir, mount that directory too
MOUNTS="~/.cargo/config.toml:ro ~/.cargo/registry ~/.cargo/git"
# Go
MOUNTS="~/go/pkg/mod ~/.cache/go-build"
```

Note that the container can write to these caches, so a compromised build in
the container could poison them for the host. Only share the caches you need.

Without `~/.cargo/config.toml`, cargo in the container ignores the host's
configuration and, for example, builds into `./target` instead of a
`build.target-dir` such as `/var/tmp/cargo-target`. If the configuration
refers to tools like `mold` or `sccache`, they must be installed in the image
as well. A single mounted file goes stale in the container when an editor
replaces it on save; `klause --klause-stop` picks up the new version.

Example `.klause`:

```ini
NETWORK=host
IMAGE=klause:python
MOUNTS="~/data/testset:ro"
```

**Caution:** A `.klause` in a third-party repository can weaken the isolation
via `MOUNTS`, `NETWORK` or `CONTAINER_ARGS`, and its Dockerfile runs arbitrary
commands during the build. Check it before you run `klause` in a third-party
repo.

For the same reason, `.klause` is mounted **read-only** into the container, so
claude cannot change its own mounts, network or image. The container remembers
whether `.klause` was a file, a directory or missing when it was created:

- If `.klause` appears afterwards (claude can create it if it did not exist),
  klause points this out. Check it before you recreate the container.
- If `.klause` was removed or replaced (e.g. file by directory), klause refuses
  to start the stopped container until it is recreated with `klause --klause-rm`.
  Docker would otherwise create the missing mount source as a directory owned
  by root.

### Project image

If the project needs more than the default image (other toolchains, system
packages, services), put a `Dockerfile` into the `.klause` directory:

```
.klause/
├── config        # the former .klause file, optional
└── Dockerfile
```

```dockerfile
ARG KLAUSE_IMAGE=klause:shell
FROM ${KLAUSE_IMAGE}
RUN dnf -y install --setopt=install_weak_deps=False postgresql java-21-openjdk-devel \
    && dnf clean all
```

- klause builds the image when it creates the container and the image is
  missing, or with `klause --klause-build`. If needed, its base image is built
  first.
- The build argument `KLAUSE_IMAGE` is `BASE_IMAGE`, by default the global
  `IMAGE` (`klause:shell`). Select one of the [images](#images) in
  `.klause/config`, e.g. `BASE_IMAGE=klause:rust`. `IMAGE` there would name the
  project image, so klause refuses `IMAGE=klause:<variant>` with a Dockerfile.
- The image is named after the container, `klause-<directory>-<hash>:latest`.
  `IMAGE` in `.klause/config` overrides that name.
- The build context is the `.klause` directory, not the project. Files for
  `COPY` go next to the Dockerfile.
- klause points out on start when the image is older than the files in
  `.klause` (except `config`) or than its base image. It does not rebuild by
  itself; rebuild with `klause --klause-build`, then recreate the container with
  `klause --klause-rm`.

### When does a configuration change take effect?

Mounts, network, image, groups, `IDLE_TIMEOUT` and the type of `.klause` are
fixed when the container is **created**. After a change, or after an image rebuild, the container has to
be deleted with `klause --klause-rm`. Anything installed is lost in the
process. If a newer image is available, klause points this out on start.
`PASS_ENV` and all environment variables take effect immediately.

## Images

The bundled `Dockerfile` is based on Fedora and builds several task-specific
images as stages that build on each other. A project selects one with
`IMAGE=klause:<variant>` in its `.klause`; without that, `klause:shell` is used.
Common layers exist only once on disk, so all images together take about as
much space as the largest one plus the variant-specific parts.

| Image           | Based on | Adds |
|-----------------|----------|------|
| `klause:shell`  | Fedora   | Claude Code (via npm, auto-updater disabled; update via `make update`), git, git-lfs, GitHub CLI, make, ripgrep, jq, ShellCheck, shfmt, Python 3 with pip, Node.js with npm, common command-line tools |
| `klause:php`    | `shell`  | PHP (cli, xml, mbstring, mysqlnd), Composer |
| `klause:devel`  | `shell`  | gcc, g++, pkg-config, OpenSSL headers; base for the following images |
| `klause:python` | `devel`  | Python headers, Poetry, uv, ruff, ImageMagick, ffmpeg |
| `klause:node`   | `devel`  | pnpm, Yarn (the C/C++ toolchain is for native modules) |
| `klause:go`     | `node`   | Go, gopls, staticcheck, golangci-lint, goimports, delve |
| `klause:rust`   | `node`   | Rust, Cargo, rustup, rustfmt, clippy, rust-analyzer, rust-src |

Each image is built when a container needs it and it is missing, or with
`klause --klause-build-base <variant>` or `make`. For more tools, add a
[project Dockerfile](#project-image) on top of one of them, or install packages
in the container via `--klause-root-shell`.

`make update` passes a new build argument `CACHE_BUST` instead of
`--no-cache`, so all images share the freshly built layers again. The value is
stored as a label in the images, and klause passes it to later builds as well.
With `--no-cache`, an image gets layers of its own.

The GitHub CLI (`gh`) does not share its login with the host. Either pass a
token with `PASS_ENV="GH_TOKEN"`, or mount the host's login with
`MOUNTS="~/.config/gh"` (only works if the token is in `hosts.yml` and not in
the system keyring). Either way, claude in the container can then act on
GitHub with your permissions, so prefer a fine-grained token.

## Technical details

- The container's main process is a small sh supervisor. It recognizes
  instances started via `exec` by `PPid 0` (their parent process lies outside
  the PID namespace). If there are no such processes for `IDLE_TIMEOUT`
  seconds, it exits and the container stops.
- On creation, klause adds the user and groups to the container's
  `/etc/passwd` and `/etc/group` as root. Group names containing spaces are
  sanitized in the process (`domain users` → `domain_users`). klause also
  creates the home directory.
- Podman (rootless): supplementary groups are kept via
  `--group-add keep-groups`, but shown as `nobody` (65534) in the container,
  since they cannot be mapped into the user namespace. Access checks on mounted
  files still work. Docker and Podman containers are separate; switching
  `RUNTIME` creates a new container.
- SELinux: mounts are not relabeled (`--security-opt label=disable`).
- `~/.claude/settings.json` is shared with the host. Hooks and status lines
  that call host programs must also find them in the image.

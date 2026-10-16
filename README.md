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
ln -s "$PWD/klause" ~/.local/bin/klause
klause --klause-build     # optional, otherwise happens on first start
```

The Dockerfile is looked up next to the (resolved) script.

## Commands

klause's own commands start with `--klause-` and are only recognized as the
**first** argument. Everything else is passed to claude.

| Command                 | Effect |
|-------------------------|--------|
| `--klause-help`         | Help |
| `--klause-build [...]`  | Build image `klause:latest`; further arguments are passed to `docker build` (e.g. `--no-cache`, `--build-arg CLAUDE_CODE_VERSION=2.1.301`) |
| `--klause-shell`        | Bash in the container as the caller |
| `--klause-root-shell`   | Bash in the container as root, e.g. for `dnf install` |
| `--klause-status`       | Name, state and configuration of the container for this directory |
| `--klause-list`         | All klause containers |
| `--klause-stop`         | Stop the container |
| `--klause-rm`           | Delete the container; anything installed in it is lost |

## Configuration

- global: `~/.config/klause` (or `$XDG_CONFIG_HOME/klause`). If the file
  does not exist, klause creates it with a commented-out example of all keys.
- per project: `.klause` in the current directory
- the environment variables `KLAUSE_RUNTIME`, `KLAUSE_IMAGE`, `KLAUSE_NETWORK`,
  `KLAUSE_IDLE_TIMEOUT` take precedence

Format: one `KEY=VALUE` line per entry, `#` starts a comment, values may be
quoted. The files are **parsed, not executed**. The project file overrides the
global one; for `MOUNTS`, `PASS_ENV` and `CONTAINER_ARGS` the values are
concatenated.

| Key              | Default         | Meaning |
|------------------|-----------------|---------|
| `RUNTIME`        | `docker`        | `docker` or `podman` (rootless, with `--userns=keep-id`) |
| `IMAGE`          | `klause:latest` | Image to use. It needs `sh` and `claude`. Only `klause:latest` is built automatically when needed. |
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
# Cargo
MOUNTS="~/.cargo/registry ~/.cargo/git"
# Go
MOUNTS="~/go/pkg/mod ~/.cache/go-build"
```

Note that the container can write to these caches, so a compromised build in
the container could poison them for the host. Only share the caches you need.

Example `.klause`:

```ini
NETWORK=host
IMAGE=klause:latest
MOUNTS="~/data/testset:ro"
```

**Caution:** A `.klause` in a third-party repository can weaken the isolation
via `MOUNTS`, `NETWORK` or `CONTAINER_ARGS`. Check the file before you run
`klause` in a third-party repo.

### When does a configuration change take effect?

Mounts, network, image, groups and `IDLE_TIMEOUT` are fixed when the container
is **created**. After a change, or after an image rebuild, the container has to
be deleted with `klause --klause-rm`. Anything installed is lost in the
process. If a newer image is available, klause points this out on start.
`PASS_ENV` and all environment variables take effect immediately.

## Image

The bundled `Dockerfile` is based on Fedora and contains:

- Claude Code (via npm, auto-updater disabled; update via `--klause-build --no-cache`)
- Python 3, pip, Poetry
- Rust, Cargo, rustfmt, clippy, rust-analyzer (from the Fedora repos)
- git, ripgrep, jq, gcc, make and common command-line tools

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

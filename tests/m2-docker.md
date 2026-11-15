# M2 Docker Preparation

## Scope

This entry point prepares the six base-image environments required by M2.
It builds local test images and records prerequisites for the generator and
direct IOC tests. It does not run IOC acceptance or start a service manager.
The [canonical milestone](../docs/milestone-574face.md) owns progress and
observed results; [the case specification](m2-case-spec.md) owns acceptance.

## Invocation

Run from the tools repository as a non-root user with Docker access:

```bash
bash tests/test-docker.bash
bash tests/test-docker.bash debian13
bash tests/test-docker.bash ubuntu24 ubuntu26
```

With no arguments, targets run sequentially: debian13, debian12, rocky8,
rocky10, ubuntu24, ubuntu26. Unknown options, unknown targets and duplicate
targets exit 2. Help exits 0. Each invocation creates a fresh retained
directory under `work/m2-verification/docker.*`; it does not resume or
overwrite an earlier run.

Each tag is `jeonghanlee/<target>-epics:1.5.0`. The host pulls it, records
image inspection and resolves an immutable digest. The frozen
`tests/docker/Dockerfile` builds a derived image from that digest. Only this
small directory is sent as build context. No image is published. Build
output, the base-image label, full derived-image inspection and the local
`sha256:` image ID are retained. Each worker uses that exact local image ID,
the caller's UID/GID, no capabilities, no-new-privileges and an
isolated network namespace. The frozen source is mounted read-only at
`/src`; separate writable mounts provide `/work` and `/evidence`.

The build installs `ripgrep` through apt on Debian/Ubuntu, and `ripgrep`
plus `diffutils` through the base image's existing dnf repositories on
Rocky. Package installation runs as root only inside the image build;
preflight and subsequent test execution remain non-root. The Dockerfile
does not request a system upgrade or replace the EPICS distribution.

Before installation, it inventories `/opt/epics` members, types, modes,
owners, groups and symlink targets, and hashes every regular file. After
installation it compares membership/metadata and verifies those hashes.
Any difference fails the build before the successful payload-check record
is written. Build records remain in `/usr/local/share/tools-m2` inside the
image; the worker retains package-version and payload-check records in its
command receipts alongside a fresh full installed-package inventory.

Package repositories may change. The recipe is not a package lockfile:
retained image IDs and recorded package versions identify the tested
environment. Rebuilding a changed environment requires fresh preflight
and dependent IOC results. Docker's build cache can reuse an identical
existing test layer; the saved ID identifies the layer actually used.

## Source And Command Evidence

The independent inventory contains Git-tracked and non-ignored untracked
files, including current edits. Git-ignored workspaces are excluded. The
snapshot preserves relative paths, modes, hashes and symlink targets.
Membership and content are compared after copying and before/after every
worker. Later source edits do not change the saved snapshot or its results.

| Path under a run | Contents |
| --- | --- |
| `inventory/`, `inventory.sha256`, `source.tar`, `source/` | Source identity, selected targets and frozen source bytes |
| `commands/` | Docker client/server and Git identity receipts |
| `<target>/commands/`, `<target>/test-image.id` | Pull, base digest, build, both image inspections, creation, attached execution, terminal state, logs and removal receipts |
| `<target>/evidence/commands/` | Actual image commands with argv, cwd, stdout, stderr, native status, UTC and monotonic bounds |
| `<target>/evidence/observations.tsv` | Preparation name, expected value and actual value |
| `<target>/evidence/terminal.txt`, `result.txt` | Worker collection completion, native status and evaluated preparation result |
| `<target>/workspace/` | Retained PTY and Git capability-probe artifacts |
| `coverage.tsv`, `result.txt` | Per-target outcomes and host completion/native status |

`docker-capture.bash` preserves command failures independently of successful
receipt capture. Receipt-storage failure terminates collection. The host
distinguishes attached-command status from inspected container exit status;
only a stopped worker with status 0 and its saved Passed result can qualify
as prepared. Logs and inspection precede removal of the owned container.
An interrupted active container is stopped as emergency cleanup and retained.

## Preparation Contract

`docker-preflight.bash` is an internal worker for fresh evidence/workspace
directories. It reads the image's OS identity, provenance and Base header,
sources its actual `setEpicsEnv.bash`, and records the resulting EPICS paths.
It inventories required executables, package versions, all 12 commonIocsh
fragments and module loader configuration hashes.

Real probes require PTY output plus status 7, `setsid --wait` status 7,
background INT status 130 after resetting inherited signal disposition,
timeout status 124, accepted socket-query syntax and successful Git project
initialization. The signal launcher uses Perl's strict/warnings pragmas and
no optional module. Interpreter identity and the real probe run are retained
for each target. Help/version receipts alone do not prove all options used
by future IOC tests.

The host bounds each pull at 600 seconds, each build at 900 seconds and
each worker at 180 seconds.
These are collection guards, not IOC performance requirements. Receipt
timestamps describe individual command intervals, not throughput or clock
accuracy. Evidence is a bounded inventory and finite probe set; there is no
long-duration observation in this stage.

Missing dependencies or unusable evidence make preparation Incomplete and
prevent readiness. Native nonzero outcomes are preserved; otherwise an
Incomplete invocation exits 2. INT/TERM preserve 130/143. Completed target
records remain valid if a later target is interrupted; absent terminal
receipts are incomplete observations and must not be reconstructed.

Filesystem-boundary checks use the real worker: a directory at
`terminal.txt` prevents evaluation, a directory at `result.txt` prevents
successful result persistence, and a directory at `observations.tsv`
prevents collection. Selecting a different OS must expose the identity
mismatch. These controls are narrower than per-assertion mutation proof.

IOC generation/build/startup, all client options, callback tracing, logging
transport, asyn readback, IOC cleanup, frozen-evidence replay and full
negative-proof coverage remain separate acceptance work. Preparation counts
are not M2 functional assertion counts. A missing prerequisite must remain
visible until a documented test environment supplies it and is verified
again.

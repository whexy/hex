# Hex (whexy fork)

A standalone copy of [anomalyco/hex](https://github.com/anomalyco/hex), kept for
the iOS app. Upstream's [README](../README.md) describes Hex itself. Rules for
agents working on fork code are in [AGENTS.md](AGENTS.md).

## Branch

`dev`, the default branch, is upstream's `dev` with this fork's commits
rebased on top. Changes land as pull requests, rebase-merged.

Each upstream update rebases the fork's commits onto upstream and
force-pushes `dev`. Anything that consumes this repository should pin a
commit, not the branch.

## Upstream workflows

Upstream's workflow files stay unchanged, so rebases never conflict on them.
All of them except `agent-policy.yml`, upstream's pull request policy check,
are disabled in the repository's Actions settings.

These publish to upstream's services with upstream's credentials, so they stay
off:

| Workflow | What it publishes |
| --- | --- |
| `release.yml` | Signed desktop builds on every push to `dev`, and stable releases |
| `release-ios.yml` | `ios-beta-*` releases on a schedule, which start upstream's Xcode Cloud build |
| `release-typescript.yml` | The TypeScript SDK to npm |
| `deploy.yml` | The website to Cloudflare |

These build and test the desktop app. They are off because the fork ships only
the iOS app for now, and none of them builds or tests it:

| Workflow | What it checks |
| --- | --- |
| `compile.yml` | Clippy on Linux, macOS and Windows, on pull requests |
| `test-builds.yml` | Unsigned desktop builds on every push to `dev` |
| `check-linux.yml`, `check-macos.yml`, `check-windows.yml` | Full desktop test suites |
| `build-desktop.yml`, `windows-installers.yml`, `windows-setup-engine.yml` | Builds that other workflows call |
| `windows-installer.yml` | Installers around upstream's published Windows release |
| `aur-check.yml` | Upstream's AUR release key, which this repository does not have |

To turn one back on, run `gh workflow enable <file> -R whexy/hex`. Their macOS
jobs need upstream's Blacksmith runners, which this repository does not have,
so those jobs wait in the queue until they time out.

## iPhone app: WeHex

The fork ships upstream's iPhone app (`ios/`) to TestFlight as **WeHex**, on
Wenxuan's Apple team (`26DMRHRW6Z`):

| Upstream | Fork |
| --- | --- |
| Team `5NZ4Q7NXJ4` | Team `26DMRHRW6Z` |
| `anomaly.hex.mobile`, `.keyboard`, `.widgets`, `.tests` | `dev.whexy.hex`, `.keyboard`, `.widgets`, `.tests` |
| App Group `group.anomaly.hex.mobile` | App Group `group.dev.whexy.hex` |
| Home screen "Hex", keyboard "Hex Keyboard" | "WeHex", "WeHex Keyboard" |
| Xcode Cloud on `ios-beta-*` tags | [`self-hosted-ios.yml`](workflows/self-hosted-ios.yml) on every iOS change to `dev` |

No upstream file is edited for this. [`ios/fork/identity.sh`](../ios/fork/identity.sh)
rewrites the identity in a checkout before XcodeGen runs, and fails on any line
it doesn't expect, so an upstream change to signing stops the build instead of
shipping a half-renamed app. To build WeHex locally:

```sh
bash ios/fork/ci.sh prepare   # rewrite, fetch the cleanup model, xcodegen, resolve packages
bash ios/fork/ci.sh test
git checkout -- ios           # undo the rewrite before committing
```

How a build ships, how to retry one, and what expires:
[operations.md](operations.md).

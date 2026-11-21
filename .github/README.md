# Hex (whexy fork)

A private copy of [anomalyco/hex](https://github.com/anomalyco/hex), kept for
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
The four that publish are disabled in the repository's Actions settings,
because they would release to upstream's services with upstream's
credentials:

| Workflow | What it publishes |
| --- | --- |
| `release.yml` | Signed desktop builds on every push to `dev`, and stable releases |
| `release-ios.yml` | `ios-beta-*` releases on a schedule, which start upstream's Xcode Cloud build |
| `release-typescript.yml` | The TypeScript SDK to npm |
| `deploy.yml` | The website to Cloudflare |

Upstream's build and test workflows stay enabled. Their macOS jobs run on
Blacksmith runners, which this repository does not have, so those jobs wait
in the queue until they time out.

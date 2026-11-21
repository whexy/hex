# Fork

This repository is a private copy of anomalyco/hex. Its `dev` branch is
upstream's `dev` with the fork's commits rebased on top (see
[README.md](README.md)). Upstream's root `AGENTS.md` still applies; these rules
come on top.

- Put fork code in paths upstream does not have. Every edit to an upstream
  file conflicts with later upstream changes, so keep such edits few and
  small, and list them below.
- Leave the root `README.md` and `AGENTS.md` identical to upstream's. Fork
  docs live in `.github/README.md` and this file.
- Leave upstream's workflow files unchanged. Turn an upstream workflow off
  with `gh workflow disable`, and name new fork workflows `self-hosted-*`.
- Keep each change one commit, so a rebase can carry it and a fix can be
  folded into it.

Fork-only paths: `.github/README.md`, `.github/AGENTS.md`.

Upstream files the fork edits: none.

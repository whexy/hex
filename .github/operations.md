# Operations

## WeHex on TestFlight

### How a build ships

[`self-hosted-ios.yml`](workflows/self-hosted-ios.yml) runs on a GitHub-hosted
Mac (`macos-26`, free on this public repository):

```ts
pull request into dev ─ iOS inputs changed? ─ no ─▶ NOOP
                                             └ yes ▶ check: identity rewrite, unit tests, unsigned archive
                                                     (no secrets, never publishes)
push to dev ─ iOS inputs changed since the newest fork-ios/<n> tag? ─ no ─▶ NOOP
                                                                     └ yes ▶ testflight
dispatch on dev ─▶ testflight (upload=false: sign and export only)

testflight ─ secrets present? ─ no ─▶ FAILED(secrets), nothing built
            └ prepare ▶ unit tests ▶ signed archive ─ dev still at this commit? ─ no ─▶ SUPERSEDED
                                                     └ yes ▶ upload ▶ tag fork-ios/<run>
```

- iOS inputs: `ios/` (including `ios/fork/`), `app/AppIcon.icon`,
  `tests/fixtures/vocabulary/audio/term-hex-1.wav`, and the workflow itself.
- The build number (`CFBundleVersion`) is the workflow's `run_number`. The
  version (`CFBundleShortVersionString`) stays upstream's `MARKETING_VERSION`.
- Each uploaded commit gets the annotated tag `fork-ios/<run>`. It keeps that
  commit after the next force-push, and the next push compares against it.
- Every run writes one `state=` line to its summary: `NOOP(<why>)`, `CHECKED`,
  `EXPORTED`, `UPLOADED`, `SUPERSEDED` or `FAILED(<stage>)`.
- A build reaches the internal testers without review. App Store Connect then
  processes it for a few minutes.
- Nothing is kept as an artifact, because artifacts on a public repository can
  be downloaded by anyone.

### Retry

Never press "Re-run": it reuses `run_number`, and with it the build number, so
the job refuses it. Never rename the workflow file either, because
`run_number` counts per file. Dispatch a new run on `dev` instead:

```sh
gh workflow run self-hosted-ios.yml --repo whexy/hex --ref dev -f upload=true
gh workflow run self-hosted-ios.yml --repo whexy/hex --ref dev    # sign and export, no upload
```

### Secrets and settings

Signing material lives only in the `testflight` environment. Its deployment
branch policy admits `dev` alone, so a pull request (even one that edits this
workflow) cannot read it. The key and the `.p12` files go to `$RUNNER_TEMP`
and a temporary keychain, both removed at the end of the job.

| `testflight` secret | Value |
| --- | --- |
| `ASC_KEY_ID` | An App Store Connect API key with the App Manager role (the one whexy/t3code uses) |
| `ASC_ISSUER_ID` | That key's issuer ID |
| `ASC_PRIVATE_KEY` | That key's `.p8` contents |
| `IOS_DEVELOPMENT_P12` | An Apple Development identity of team `26DMRHRW6Z`, as a base64 `.p12` |
| `IOS_DISTRIBUTION_P12` | An Apple Distribution identity of the same team, as a base64 `.p12` |
| `IOS_P12_PASSWORD` | The password of both `.p12` files |

| Repository variable | Effect |
| --- | --- |
| `IOS_RUNNER` | JSON `runs-on` for the `testflight` job; unset is `"macos-26"`. The `check` job always uses GitHub's runner, since it runs pull requests. |
| `IOS_XCODE` | An Xcode path to select (e.g. `/Applications/Xcode_26.4.app`); unset keeps the image's default. |

The archive is signed automatically with development profiles that Xcode makes
through the API key. The export signs manually, with one `IOS_APP_STORE`
profile per bundle (`dev.whexy.hex`, `.keyboard`, `.widgets`), because an App
Manager key cannot use Xcode's cloud-managed distribution certificates.
[`store-profiles.sh`](../ios/fork/store-profiles.sh) installs the newest active
one for each bundle and fails, naming the bundle, when one is missing.

### Made once by hand

The public App Store Connect API cannot create these:

- The App Group `group.dev.whexy.hex`, assigned to `dev.whexy.hex` and
  `dev.whexy.hex.keyboard` (the widgets read no shared data).
- The app record "WeHex" for `dev.whexy.hex`, and the internal tester group.

### What expires

| What | When | Then |
| --- | --- | --- |
| Apple Distribution certificate, and with it every `IOS_APP_STORE` profile | 2027-11-08 | Make a new certificate and `.p12`, replace `IOS_DISTRIBUTION_P12`, and create the three profiles again. |
| Apple Development certificate in `IOS_DEVELOPMENT_P12` | about a year after it was made (`asc certificates list`) | The archive fails to sign; replace the `.p12`. |
| App Store Connect API key | never, until revoked | Replace the three `ASC_*` secrets. |
| The hosted image's Xcode | when GitHub updates `macos-26` | Pin one with `IOS_XCODE`. |
| Upstream's cleanup-tagger model (release `ios-model-cleanup-tagger-1` on anomalyco/hex) | if upstream deletes that release | `prepare` fails on the download; the SHA-256 in `ios/scripts/fetch-cleanup-model.sh` pins its contents. |

An extension that upstream adds later needs its own bundle ID, its own
`IOS_APP_STORE` profile and a rewrite in `ios/fork/identity.sh`;
`identity.sh` fails until it has one.

### Upstream's iOS release

Upstream builds on Xcode Cloud from `ios-beta-*` tags cut by
`release-ios.yml`, on its own team. That workflow is disabled here, and
`ios/ci_scripts/`, `ios/ExportOptions.plist` and `ios/appstoreconnect.json` are
left as upstream has them; no fork build reads them.

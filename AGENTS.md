# Klipa desktop collaboration rules

These rules apply to every agent in this public repository. `origin/main` is
the canonical source branch. Public history must remain independent of the
private mobile, web, infrastructure, store, and operational repositories.

## Start of every task

1. Run `git fetch --prune origin` and `git status --short --branch`.
2. Fast-forward a clean, behind-only `main`. If local commits, dirty files, or
   divergence exist, inspect and preserve them before doing anything else.
3. Read `README.md` and the directly relevant file under `docs/`. Security,
   persistence, network, packaging, and release changes must follow their
   documented gates rather than an inferred shortcut.
4. Keep the architecture shallow: Flutter view to Riverpod controller to a
   concrete repository/service or the small media-player port. Do not add a
   general abstraction layer, service locator, event bus, local server,
   background service, telemetry, or Klipa API dependency incidentally.

## Validation and handoff

Run the narrowest relevant test during development. Before handing off a
completed change, run the applicable full platform checks:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build linux --release
```

On Windows, use `tool/build_windows.ps1` as documented in `README.md`; do not
claim native Windows validation from a Linux build. Inspect `git diff --check`
and `git status --short`, commit all scoped durable changes, fetch and reconcile
again, push, and verify local `HEAD` equals `origin/main`.

## Security and public-source boundary

- Use only synthetic, owned, or legally documented test content. Never place a
  provider URL, credential, token, authorization header, customer data, or
  private diagnostic in code, commands, logs, issues, tests, or screenshots.
- Do not copy private Klipa source, internal instructions, infrastructure,
  signing material, store automation, or unreleased assets into this public
  repository.
- Preserve the local-first and zero-startup-network contracts in
  `docs/product.md`, `docs/architecture.md`, and `docs/security-model.md`.
- Generated packages, native runtimes, reports, and artifacts under `dist/`
  remain local unless an authorized release procedure says otherwise.

## External distribution

Creating or pushing a `v*` tag can start the signing and publishing workflow.
Tags, signing requests, GitHub releases, package-repository changes, and any
external artifact upload require explicit authorization. Follow
`docs/release-checklist.md` and `docs/code-signing-policy.md`; a successful
local build is not a release approval.

# Security policy

The source repository remains private. Report suspected security issues
privately to `hello@klipa.tv`; do not disclose them in public channels.

Do not put credentials, tokenized URLs, provider hostnames, private IPs,
subscription details, or unredacted diagnostics in an issue or discussion.

## Supported versions

The latest 0.1.x desktop release is supported. Older preview builds should be
upgraded before reporting a security issue.

## Security invariants

- No plaintext persistence of playlists, stream URLs, guide URLs, or credentials.
- No TLS-verification bypass.
- No arbitrary playlist headers, protocols, scripts, shell commands, or HTML.
- No telemetry, remote configuration, local HTTP server, or custom updater.
- Native media and database artifacts are inventoried before distribution.

See [docs/security-model.md](docs/security-model.md) for the enforced controls,
accepted lightweight playback trust boundary, and pre-distribution blockers.

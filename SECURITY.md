# Security policy

This repository is still private local development and has no public security
intake yet. A private security contact must be configured before publication.

Do not put credentials, tokenized URLs, provider hostnames, private IPs,
subscription details, or unredacted diagnostics in an issue or discussion.

## Supported versions

No released version is supported yet.

## Security invariants

- No plaintext persistence of playlists, stream URLs, guide URLs, or credentials.
- No TLS-verification bypass.
- No arbitrary playlist headers, protocols, scripts, shell commands, or HTML.
- No telemetry, remote configuration, local HTTP server, or custom updater.
- Native media and database artifacts are inventoried before distribution.

See [docs/security-model.md](docs/security-model.md) for the enforced controls,
known subresource/DNS gaps, and pre-distribution blockers.

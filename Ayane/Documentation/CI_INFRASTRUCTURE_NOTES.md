# CI infrastructure notes

## Maven Central 403 on GitHub-hosted Windows runners

A Windows workflow attempt on the Interaction Core V2 branch failed before project source compilation because Maven Central returned HTTP 403 for a broad set of unrelated, normally public artifacts. The same branch's Android workflow was able to resolve dependencies, which distinguishes this incident from a Kotlin or application-code compilation failure.

Triage rules:

1. Do not change dependency versions merely to hide a repository-wide 403.
2. Re-run the failed Windows job once on a fresh hosted runner.
3. If the second attempt fails with the same repository-wide 403, capture the first failing URL and runner image version.
4. Only add a repository mirror after confirming the mirror's integrity, availability, TLS behavior and artifact provenance.
5. Never disable dependency verification, TLS validation or checksum checks to make CI green.
6. A later source compilation or test failure must be treated separately from this infrastructure incident.

This note exists so an external dependency outage cannot be mistaken for a KIN product regression or “fixed” with an unsafe supply-chain workaround.

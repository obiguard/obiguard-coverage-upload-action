# Obiguard Coverage Upload

Upload an [lcov](https://github.com/linux-test-project/lcov) code coverage report to
[Obiguard](https://obiguard.ai)'s SOC &gt; Code Coverage feature, from a GitHub Actions workflow.

This action is a thin wrapper around a `curl`/`jq` POST to your org's Obiguard gateway — see
[`upload.sh`](./upload.sh) if you'd rather inline the logic yourself instead of depending on this
action.

## Prerequisites

1. A Code Coverage token, created from your org's **SOC &gt; Log Ingestion** page in Obiguard (New
   token → Data type: "Code Coverage"). Store it as a repo or org secret, e.g.
   `OBIGUARD_COVERAGE_TOKEN`.
2. If you're on the hosted Obiguard gateway, you can skip `gateway-url` entirely — it defaults to
   `https://gateway.obiguard.ai/v1/coverage`. Self-hosted instances should override it with their
   own endpoint, shown on the **SOC &gt; Code Coverage &gt; Set up CI uploads** page (it looks like
   `https://<your-gateway-host>/v1/coverage`).
3. A step earlier in the same job that produces an lcov report (Jest, pytest-cov, `gcov2lcov` for
   Go, etc. all work — anything that emits lcov).

## Usage

```yaml
name: CI

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20

      - run: npm ci
      - run: npm test -- --coverage --coverageReporters=lcov

      - name: Upload coverage to Obiguard
        uses: obiguard/obiguard-coverage-upload-action@v1
        with:
          lcov-path: coverage/lcov.info
        env:
          OBIGUARD_COVERAGE_TOKEN: ${{ secrets.OBIGUARD_COVERAGE_TOKEN }}
```

Self-hosting an Obiguard instance? Point `gateway-url` at it instead of the default
`https://gateway.obiguard.ai/v1/coverage`:

```yaml
      - name: Upload coverage to Obiguard
        uses: obiguard/obiguard-coverage-upload-action@v1
        with:
          lcov-path: coverage/lcov.info
          gateway-url: https://<your-gateway-host>/v1/coverage
        env:
          OBIGUARD_COVERAGE_TOKEN: ${{ secrets.OBIGUARD_COVERAGE_TOKEN }}
```

`repo`, `branch`, and `commit-sha` default to the current `github.repository` /
`github.ref_name` / `github.sha` — you only need to set them if you want to override those (e.g.
uploading a coverage run for a different ref than the one currently checked out).

## Inputs

| Input             | Required | Default                | Description                                                                 |
| ------------------ | -------- | ----------------------- | ----------------------------------------------------------------------------- |
| `lcov-path`        | yes      | —                       | Path to the lcov report file                                                  |
| `gateway-url`      | no       | `https://gateway.obiguard.ai/v1/coverage` | Obiguard gateway coverage endpoint. Ignored if `destinations` is set.         |
| `repo`             | no       | `github.repository`     | `repoFullName`, e.g. `your-org/your-repo`                                     |
| `branch`           | no       | `github.ref_name`       | Branch name                                                                    |
| `commit-sha`       | no       | `github.sha`            | Commit SHA                                                                     |
| `destinations`     | no       | —                       | Advanced: multiple `<url>=<token>` pairs, one per line — see below            |
| `fail-on-error`    | no       | `false`                 | Fail the step if any destination upload fails, instead of warning & continuing |
| `connect-timeout`  | no       | `5`                     | Max seconds to establish a connection per destination                         |
| `max-time`         | no       | `15`                    | Max seconds for the whole request per destination                            |

The `OBIGUARD_COVERAGE_TOKEN` env var is required unless `destinations` is set.

The token is read from the `OBIGUARD_COVERAGE_TOKEN` **environment variable**, not a `with:` input
— set it via this step's `env:`, the same way you'd pass `SONAR_TOKEN` to
`sonarqube-scan-action`, so it's handled by Actions' normal secret redaction rather than being an
ordinary input value.

## Multiple destinations

If you need the same report sent to more than one Obiguard instance in one run (e.g. staging and
production, or you're migrating between a self-hosted and hosted deployment), use `destinations`
instead of `gateway-url`:

```yaml
      - name: Upload coverage to Obiguard
        uses: obiguard/obiguard-coverage-upload-action@v1
        with:
          lcov-path: coverage/lcov.info
          destinations: |
            https://staging.example.com/v1/coverage=${{ secrets.OBIGUARD_COVERAGE_TOKEN_STAGING }}
            https://gateway.obiguard.ai/v1/coverage=${{ secrets.OBIGUARD_COVERAGE_TOKEN_PROD }}
```

Each destination is attempted independently. By default, a failed destination logs a
`::warning::` annotation and the step still succeeds — set `fail-on-error: true` if you want the
step to fail when any destination is unreachable or rejects the upload.

## Other CI providers

This action is GitHub-Actions-specific (it reads `GITHUB_REPOSITORY`/`GITHUB_REF_NAME`/`GITHUB_SHA`
as defaults). On another CI provider, use [`upload.sh`](./upload.sh) directly, or the equivalent
`curl`/`jq` call — the upload request itself is identical everywhere; only how you obtain the
repo/branch/commit values differs.

## Requirements for self-hosted runners

`curl` and `jq` must be on `PATH`. Both are preinstalled on GitHub-hosted `ubuntu-latest`,
`macos-latest`, and `windows-latest` runners.

## Releases

Versioning and tagging are automated via [release-please](https://github.com/googleapis/release-please) —
see [`.github/workflows/release-please.yml`](./.github/workflows/release-please.yml). To cut a
release:

1. Merge commits to `main` using [Conventional Commits](https://www.conventionalcommits.org/)
   (`fix: ...` → patch, `feat: ...` → minor, `feat!: ...` or a `BREAKING CHANGE:` footer → major).
2. release-please opens (and keeps up to date) a "Release PR" that accumulates a version bump and
   changelog from those commits.
3. Merging that PR tags the release (e.g. `v1.4.0`), publishes a GitHub Release, and automatically
   moves the floating `v1` tag to point at it — the same tag consumers pin `uses: ...@v1` to.

`version.txt` and `CHANGELOG.md` are owned by release-please — don't hand-edit them; the Release PR
is the only thing that should change them.

Note: the very first `v1.0.0` tag/release, and enabling the GitHub Marketplace listing, are
one-time manual steps (see below) — this automation takes over from there.

# Kedify Apply Recommendations Demo

This repository is a small Helm-based demo for `kedify apply recommendations`.

It mirrors the explicit values structure used by the Kedify CLI test chart so the recommendation patcher can safely map rendered workloads back to `chart/values.yaml`.

## Repository Layout

- `chart/`: demo Helm chart that renders several Deployments
- `scripts/apply-kedify-recommendations.sh`: fetches live recommendations and applies them workload by workload
- `.github/workflows/apply-kedify-recommendations.yml`: CI workflow that installs `kedify`, runs the script, and opens a PR with `gh` when values change

## Required GitHub Configuration

Set these before enabling the workflow:

- Repository secret `KEDIFY_TOKEN`: Kedify API token
- Repository variable `KEDIFY_CLUSTER_ID`: cluster ID to inspect

Optional repository variables:

- `KEDIFY_API_URL`: defaults to `https://api.dev.kedify.io/v1`
- `KEDIFY_MIN_CONFIDENCE`: defaults to `20`

## What The Workflow Does

1. Checks out this demo repository.
2. Installs `kedify` from the Kedify Homebrew tap.
3. Fetches live recommendations with `kedify list recommendations`.
4. Filters to waiting Deployment recommendations and deduplicates them down to unique workloads.
5. Runs `kedify apply recommendations` once per workload against `chart/values.yaml`.
6. Pushes a branch and opens or updates a pull request with `gh` if the values file changed.

## Local Usage

You can run the same flow locally:

```bash
export KEDIFY_TOKEN=...
export KEDIFY_CLUSTER_ID=ecf6a4d3-fc2c-403b-b70c-6de243ddfbbb
export KEDIFY_MIN_CONFIDENCE=20

./scripts/apply-kedify-recommendations.sh
```

The script expects `kedify`, `helm`, and `jq` to be available on `PATH`.

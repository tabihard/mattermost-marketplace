# Mattermost Marketplace (self-hosted fork)

This is a self-hosted fork of [mattermost/mattermost-marketplace](https://github.com/mattermost/mattermost-marketplace), the stateless HTTP service that backs the Mattermost Plugin Marketplace (normally run by Mattermost at `https://api.integrations.mattermost.com`).

By default this fork **proxies the official catalog** and overlays any plugins you add locally to `plugins.json` on top of it, so System Admins see both the official plugins and your own private ones. It ships ready to deploy to **AWS Lambda** (API Gateway + CloudFront), but the same binary also runs as a plain standalone HTTP server anywhere.

## Architecture

- `cmd/marketplace` — standalone HTTP server (`go run ./cmd/marketplace server`).
- `cmd/lambda` — AWS Lambda entry point. `plugins.json` is compiled directly into the binary via `//go:embed`, so the function needs no external database or storage at runtime.
- `internal/store` — pluggable backends: `static` (reads `plugins.json`), `proxy` (queries an upstream marketplace over HTTP), and `merged` (combines several stores, later stores winning on conflicts).
- `serverless.yml` — Serverless Framework stack: a Lambda function behind API Gateway, fronted by a CloudFront distribution for caching.

## Developing

### Environment Setup

1. Install [Go](https://golang.org/doc/install) 1.22+.

### Running locally

```
$ make run-server
```

This starts the server on `:8085`, backed by `plugins.json` and proxying `https://api.integrations.mattermost.com` (the default `BUILD_UPSTREAM_URL`, see below). Try it:

```
$ curl 'http://localhost:8085/api/v1/plugins?per_page=5'
$ curl 'http://localhost:8085/api/v1/health'
```

### Testing

```
$ make test
```

### Proxying upstream (own additions + official catalog)

The marketplace merges results from every configured store, with later stores winning on version conflicts. This fork wires up `plugins.json` (your local additions) followed by an upstream proxy (the official marketplace) by default.

To change or disable the upstream at build time (baked into the binary, used by both `make build-server` and `make build-lambda`):

```
# point at a different upstream (e.g. a staging marketplace)
BUILD_UPSTREAM_URL=https://api.staging.integrations.mattermost.com make build-lambda

# fully private catalog, no upstream proxying at all
BUILD_UPSTREAM_URL= make build-lambda
```

When running the standalone server without rebuilding, you can also override it per-invocation:

```
go run ./cmd/marketplace server --upstream https://api.integrations.mattermost.com
```

### Adding your own plugin to `plugins.json`

Build and sign your plugin bundle, upload it somewhere it can be downloaded over HTTPS (S3, GitHub Releases, etc.), then run:

```
go run ./cmd/generator/ add <repo-or-plugin-id> <version> --community
```

e.g.

```
go run ./cmd/generator/ add my-internal-plugin v1.0.0 --community
```

`generator add` supports additional flags (`--official`, `--partner`, `--enterprise`, `--cloud`, `--on-prem`, `--beta`, `--experimental`); see `go run ./cmd/generator/ add --help`. Double-check the `diff` of `plugins.json` afterward.

Note: bare `go run ./cmd/generator` (no subcommand) mirrors Mattermost's own internal release pipeline for `mattermost-plugin-*` repos under the `mattermost` GitHub org — you generally don't need it for a private/self-hosted catalog; use `generator add` instead.

## Self-hosting on AWS Lambda

### Prerequisites

- An AWS account and credentials (`aws configure`, or `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars) with permission to manage Lambda, API Gateway, CloudFront, IAM, and CloudFormation.
- [Node.js](https://nodejs.org/) and the Serverless Framework: `npm i -g "serverless@<4.0.0"`.
- Go 1.22+.

### First deploy

```
$ SLS_STAGE=production make deploy-lambda
```

This runs `make clean build-lambda package-artifact`, then `serverless deploy`, which provisions the full CloudFormation stack (Lambda function, API Gateway, CloudFront distribution). The first deploy can take several minutes, mostly waiting on CloudFront. Serverless prints the API Gateway endpoint URL and the CloudFront domain (e.g. `dxxxxxxxxxxxxx.cloudfront.net`) when it finishes — the CloudFront domain is what you'll point Mattermost at, since it caches responses and is what `serverless.yml` is set up to front.

### Fast iteration

Once the stack exists, redeploy just the function code (skips the CloudFormation update, much faster):

```
$ SLS_STAGE=production make deploy-lambda-fast
```

### Custom domain (optional)

To serve the marketplace from your own domain instead of the CloudFront default, request/import an ACM certificate **in `us-east-1`** for your domain, then add `Aliases` and `ViewerCertificate` to the `CloudFrontDistribution` resource in `serverless.yml`, and point a DNS CNAME/ALIAS record at the resulting CloudFront domain.

### Point your Mattermost server at it

In System Console → Plugins → Plugin Management (or `config.json` under `PluginSettings`), set:

```json
{
  "PluginSettings": {
    "EnableMarketplace": true,
    "MarketplaceUrl": "https://<your-cloudfront-domain-or-custom-domain>"
  }
}
```

System Admins will then see the Marketplace tab in System Console → Plugin Management, backed by your self-hosted service.

### CI/CD

`.github/workflows/build-and-deploy.yml` builds and tests on every push, and deploys (`serverless deploy function`) on pushes to `main`. It expects the CloudFormation stack to already exist (i.e. you've run `make deploy-lambda` once by hand) and reads AWS credentials from the `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` repository secrets.

### Tearing down

```
$ serverless remove --stage production
```

## License

Apache 2.0 — see [LICENSE](LICENSE). Based on [mattermost/mattermost-marketplace](https://github.com/mattermost/mattermost-marketplace).

export GO111MODULE=on

BUILD_TAG = $(shell git describe --tags --abbrev=0 2>/dev/null || echo dev)
BUILD_HASH = $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
BUILD_HASH_SHORT = $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
LDFLAGS += -X "github.com/manybugsdev/mattermost-marketplace/internal/api.buildTag=$(BUILD_TAG)"
LDFLAGS += -X "github.com/manybugsdev/mattermost-marketplace/internal/api.buildHash=$(BUILD_HASH)"
LDFLAGS += -X "github.com/manybugsdev/mattermost-marketplace/internal/api.buildHashShort=$(BUILD_HASH_SHORT)"
# Proxy to the official Mattermost marketplace by default, overlaying any plugins added locally
# to plugins.json on top of it. Override (e.g. `make BUILD_UPSTREAM_URL= build-lambda`) to run a
# fully private catalog with no upstream proxying.
BUILD_UPSTREAM_URL ?= https://api.integrations.mattermost.com
LDFLAGS += -X "main.upstreamURL=$(BUILD_UPSTREAM_URL)"
SLS_STAGE ?= "dev"

$(shell cp plugins.json ./cmd/lambda/)

## Checks the code style, tests, builds and bundles.
all: check-style test build

## Runs go vet and golangci-lint against all packages.
.PHONY: check-style
check-style:
	go vet ./...

# https://stackoverflow.com/a/677212/1027058 (check if a command exists or not)
	@if ! [ -x "$$(command -v golangci-lint)" ]; then \
		echo "golangci-lint is not installed. Please see https://github.com/golangci/golangci-lint#install for installation instructions."; \
		exit 1; \
	fi; \

	golangci-lint run ./...

## Runs test against all packages.
.PHONY: test
test:
	go test -ldflags="$(LDFLAGS)" ./...

## Build builds the various commands
.PHONY: build
build: build-server build-lambda

## Compile the server for the current platform.
.PHONY: build-server
build-server:
	go build -ldflags="$(LDFLAGS)" -o dist/marketplace ./cmd/marketplace/

## Run the Plugin Marketplace
.PHONY: run
run: run-server

## Run the Plugin Marketplace
.PHONY: run-server
run-server:
	go run -ldflags="$(LDFLAGS)" ./cmd/marketplace server

## Compile the server as a lambda function
# GOARCH is pinned explicitly (rather than inherited from the host) so the artifact always
# matches the `architecture: x86_64` set in serverless.yml, regardless of what machine (e.g. an
# Apple Silicon Mac) builds it.
.PHONY: build-lambda
build-lambda:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w $(LDFLAGS)" -tags lambda.norpc -o dist/bootstrap ./cmd/lambda/

## Package the lambda binary into a .zip artifact
.PHONY: package-artifact
package-artifact:
	zip -j dist/mattermost-marketplace.zip dist/bootstrap

## Deploy the lambda stack
.PHONY: deploy-lambda
deploy-lambda: clean build-lambda package-artifact
	serverless deploy --verbose --stage $(SLS_STAGE)

## Deploy the lambda function only to an existing stack
.PHONY: deploy-lambda-fast
deploy-lambda-fast: clean build-lambda package-artifact
	serverless deploy function -f server --stage $(SLS_STAGE)

## Update plugins.json
.PHONY: plugins.json
plugins.json:
	@echo "This command is deprecated. Use go run ./cmd/generator/ add instead."
	go run ./cmd/generator --database plugins.json --debug

## Clean all generated files
.PHONY: clean
clean:
	rm -rf ./dist

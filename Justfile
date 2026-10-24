set shell := ["bash", "-euo", "pipefail", "-c"]

nim_flags := "-d:release -d:strip --opt:speed"
nim_image := "nimlang/nim:2.2.12"

default:
    @just --list

# Version string from grimoire.nimble (e.g. 0.1.0)
version:
    @grep -E '^version' grimoire.nimble | head -1 | sed -E 's/.*= *"([^"]+)".*/\1/'

# Build release binaries for macOS arm64 and Linux amd64 into dist/
build:
    #!/usr/bin/env bash
    set -euo pipefail
    v="$(just version)"
    just build-darwin "$v"
    just build-linux "$v"
    echo "Built dist/grim-${v}-darwin-arm64 and dist/grim-${v}-linux-amd64"

build-darwin version:
    mkdir -p dist
    nim c {{nim_flags}} -o:"dist/grim-{{version}}-darwin-arm64" src/grimoire.nim

build-linux version:
    #!/usr/bin/env bash
    set -euo pipefail
    v="{{version}}"
    out="grim-${v}-linux-amd64"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    rsync -a \
        --exclude .git \
        --exclude dist \
        --exclude grim \
        --exclude nimble.paths \
        --exclude nimcache \
        --exclude .cursor \
        ./ "$tmp/"
    mkdir -p "$tmp/dist"
    docker run --rm --platform linux/amd64 \
        -v "$tmp:/work" \
        -w /work \
        -u "$(id -u):$(id -g)" \
        -e HOME=/tmp/nimhome \
        -e NIMBLE_DIR=/tmp/nimhome/.nimble \
        {{nim_image}} \
        bash -c 'mkdir -p /tmp/nimhome/.nimble && nimble install -y --depsOnly && nim c {{nim_flags}} --path:src -o:"dist/'"$out"'" src/grimoire.nim'
    mkdir -p dist
    cp "$tmp/dist/$out" "dist/$out"

# Run tests, build, tag, and publish a GitHub release for the nimble version
release:
    #!/usr/bin/env bash
    set -euo pipefail
    v="$(just version)"
    just preflight "$v"
    nimble test
    just build-darwin "$v"
    just build-linux "$v"
    (
        cd dist
        shasum -a 256 "grim-${v}-darwin-arm64" "grim-${v}-linux-amd64" > SHA256SUMS
    )
    git tag "v${v}"
    git push origin "v${v}"
    notes="$(mktemp)"
    trap 'rm -f "$notes"' EXIT
    {
        echo "## Binaries"
        echo ""
        echo "- \`grim-${v}-darwin-arm64\` — macOS Apple Silicon"
        echo "- \`grim-${v}-linux-amd64\` — Linux x86_64 (glibc, dynamic; built in \`nimlang/nim:2.2.12\`)"
        echo ""
        echo "Verify with \`SHA256SUMS\` in this release."
    } > "$notes"
    gh release create "v${v}" \
        --title "v${v}" \
        --notes-file "$notes" \
        "dist/grim-${v}-darwin-arm64" \
        "dist/grim-${v}-linux-amd64" \
        "dist/SHA256SUMS"
    echo "Published https://github.com/aboisvert/grimoire/releases/tag/v${v}"

preflight version:
    #!/usr/bin/env bash
    set -euo pipefail
    v="{{version}}"
    command -v nim >/dev/null || { echo "nim not found"; exit 1; }
    command -v docker >/dev/null || { echo "docker not found"; exit 1; }
    command -v gh >/dev/null || { echo "gh not found"; exit 1; }
    if [[ -z "$v" ]]; then
        echo "empty version from grimoire.nimble"
        exit 1
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "working tree is not clean"
        exit 1
    fi
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ "$branch" != "main" ]]; then
        echo "expected branch main, got $branch"
        exit 1
    fi
    git fetch origin main
    if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
        echo "HEAD is not origin/main"
        exit 1
    fi
    if git rev-parse "v${v}" >/dev/null 2>&1; then
        echo "tag v${v} already exists locally"
        exit 1
    fi
    if git ls-remote --tags origin "refs/tags/v${v}" | grep -q .; then
        echo "tag v${v} already exists on origin"
        exit 1
    fi
    if gh release view "v${v}" >/dev/null 2>&1; then
        echo "GitHub release v${v} already exists"
        exit 1
    fi

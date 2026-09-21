#!/usr/bin/env bash

set -euo pipefail

base_sha="${1:?Usage: quality-check-changed-files.sh <base-sha>}"

mapfile -d '' prettier_files < <(
  git diff --diff-filter=ACMR --name-only -z "$base_sha" HEAD -- \
    ':(glob).github/**/*.yml' \
    ':(glob).github/**/*.yaml' \
    ':(glob).github/**/*.js' \
    ':(glob)force-app/**/*.css' \
    ':(glob)force-app/**/*.html' \
    ':(glob)force-app/**/*.js' \
    ':(glob)force-app/**/*.json' \
    ':(glob)config/**/*.json' \
    '*.json'
)

if ((${#prettier_files[@]} > 0)); then
  echo "Checking formatting of ${#prettier_files[@]} changed file(s)"
  npx --no-install prettier --check "${prettier_files[@]}"
else
  echo "No changed files require a Prettier check"
fi

mapfile -d '' eslint_files < <(
  git diff --diff-filter=ACMR --name-only -z "$base_sha" HEAD -- \
    ':(glob)force-app/main/default/aura/**/*.js' \
    ':(glob)force-app/main/default/lwc/**/*.js'
)

if ((${#eslint_files[@]} > 0)); then
  echo "Linting ${#eslint_files[@]} changed JavaScript file(s)"
  npx --no-install eslint "${eslint_files[@]}"
else
  echo "No changed Aura or LWC JavaScript files require linting"
fi

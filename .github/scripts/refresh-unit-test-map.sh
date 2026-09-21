#!/usr/bin/env bash

set -euo pipefail

target_org="${1:?Usage: npm run test-map:refresh -- <target-org>}"

echo "Running all local Apex tests in ${target_org} before refreshing the map"
sf apex run test \
  --target-org "${target_org}" \
  --test-level RunLocalTests \
  --code-coverage \
  --wait 60

echo "All Apex tests passed; generating config/unitTestMap.json"
node .github/scripts/generate-unit-test-map.js \
  "${target_org}" \
  config/unitTestMap.json

npx --no-install prettier --write config/unitTestMap.json

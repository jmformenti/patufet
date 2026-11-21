#!/usr/bin/env bash
# Report the deprecated setup inputs a caller still passes (java-version, node-version):
# a warning annotation on stderr, and on stdout the "Key: value" line for
# run-summary.sh. Nothing at all when neither is set.
#
# Usage: deprecated-inputs.sh <java-version> <node-version>
set -euo pipefail

names=()
[ -z "${1:-}" ] || names+=(java-version)
[ -z "${2:-}" ] || names+=(node-version)
[ "${#names[@]}" -gt 0 ] || exit 0

list="${names[*]}"
list="${list// /, }"
echo "::warning::Deprecated input(s) $list: move them to .github/patufet/setup/action.yml (docs/customization.md#preparing-the-environment, docs/migration.md). They will be removed." >&2
echo "Deprecated inputs: $list → .github/patufet/setup/action.yml"

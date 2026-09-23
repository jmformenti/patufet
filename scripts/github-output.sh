#!/usr/bin/env bash
# Append stdin to $GITHUB_OUTPUT as a multi-line output <name>, with a random
# delimiter so that no content (a plan, a report) can end the value early or
# inject other outputs.
#
# Usage: <command> | github-output.sh <name>
set -euo pipefail

name="${1:?usage: github-output.sh <name>}"
value=$(cat)
delim="PATUFET_EOF_$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
printf '%s<<%s\n%s\n%s\n' "$name" "$delim" "$value" "$delim" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"

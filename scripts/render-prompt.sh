#!/usr/bin/env bash
# Render a prompt template: substitutes {{name}} placeholders with the value of
# the environment variable TPL_<name>, then appends the consumer repository's
# optional extension file (project-specific instructions). The extension file
# is appended verbatim, so a "{{ x }}" in it (Vue, Handlebars...) survives.
#
# Usage: render-prompt.sh <template.md> [<extension-file>]
# Output: rendered prompt on stdout. Unknown placeholders are replaced by an
# empty string and reported on stderr so a typo never reaches Claude silently.
set -euo pipefail

template="${1:?usage: render-prompt.sh <template.md> [<extension-file>]}"
extension="${2:-}"

python3 - "$template" "$extension" <<'PY'
import os
import re
import sys

template_path, extension_path = sys.argv[1], sys.argv[2]
text = open(template_path, encoding="utf-8").read()

def substitute(match):
    name = match.group(1)
    value = os.environ.get("TPL_" + name)
    if value is None:
        print(f"render-prompt: placeholder {{{{{name}}}}} has no TPL_{name} variable; replaced by empty string",
              file=sys.stderr)
        return ""
    return value

text = re.sub(r"\{\{\s*([A-Za-z0-9_]+)\s*\}\}", substitute, text)

if extension_path and os.path.isfile(extension_path):
    extra = open(extension_path, encoding="utf-8").read().strip()
    if extra:
        text += "\n\n## Project-specific instructions\n\n" + extra + "\n"

sys.stdout.write(text)
PY

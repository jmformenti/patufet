# Uninstalling patufet

For humans and coding agents alike. An agent does it as a pull request whose body lists
what was removed, what was left and why.

patufet leaves files, labels and (if you created them for it) a secret and the App.
Nothing else: no repository setting or branch protection is touched, and the
`<!-- patufet:plan -->` comments stay in the issues as plain text.

## 1. In-flight work

Stop if there is any, unless the owner said to close it. Runs already started complete on
their own.

```bash
gh issue list --label ready-to-implement,in-progress,to-refine
gh pr list --search "head:agent/issue-"
```

## 2. Keep the project knowledge

Read `.github/patufet/implement.md`, `review.md` and `e2e.md`: anything still true about the
project (test anchors, review rules, paths to always check) moves to `CLAUDE.md` or the
README before the files go.

## 3. Remove the files

```bash
git rm -r .github/workflows/patufet.yml .github/workflows/patufet-mention.yml \
          .github/patufet .claude/commands/plan-issue.md
```

If the caller used renamed labels (`label-*` inputs), note their names for the next step.

## 4. Delete the flow labels patufet created, and only those

The bootstrap never modified a label that already existed, so some of the eight names may
belong to the repository (a `blocked` or `pass` used by a project board, for instance).
Deleting a label also removes it from every issue and PR, closed ones included.

Delete only the labels created for patufet. The adoption PR records the bootstrap's
`create` / `keep` line for each label; if that record is missing, ask the owner. A matching
description is no proof: a label that existed before may have the same one.

```bash
gh label list --limit 1000 --json name,description \
  --jq '.[] | select(.name | IN("ready-to-implement","in-progress","to-refine","blocked","pass","warning","fail","needs-human-review"))'
gh label delete <name> --yes      # one by one, for the labels created for patufet
```

## 5. Secret and App: the owner decides

Check whether any remaining workflow still uses `anthropics/claude-code-action`:

```bash
grep -lE 'anthropics/claude-code-action' .github/workflows/*.y*ml
```

If none does, the owner may run `gh secret delete CLAUDE_CODE_OAUTH_TOKEN` (or
`ANTHROPIC_API_KEY`) and uninstall the Claude GitHub App from the repository settings. Keep
both if `@claude` is still used through another workflow. An agent never deletes the secret
itself.

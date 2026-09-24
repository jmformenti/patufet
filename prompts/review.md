Review pull request #{{pr}} of the repository `{{repository}}` (read it with `gh pr view {{pr}}`
and `gh pr diff {{pr}}`). Do not launch subagents: do the whole review yourself in this turn.
This is automatic review cycle number {{cycle}} for this PR.

Write every comment in this language: **{{language}}**.

## Plan conformance

{{plan_section}}

## Scope

{{ci_section}}

You have no tools to write temporary files either: do not try.

Review the whole diff looking at:

- Correctness: bugs, edge cases, regressions.
- Compliance with the repository's documented conventions (CLAUDE.md, CONTRIBUTING, README):
  architecture layers, naming, language of user-facing strings, etc.
- Tests: new logic without coverage must be reported (by reading, not by running anything).
- Security: authorization checks, secrets handling, input validation.

## Output

1. One inline comment (`mcp__github_inline_comment__create_inline_comment`) per concrete
   problem, stating its severity.
2. One single summary comment on the PR (`gh pr comment {{pr}}`) whose **first line is exactly**
   `<!-- patufet:review cycle={{cycle}} verdict=VERDICT -->` where VERDICT is `pass`,
   `warning` or `fail`, followed by a heading and the report: overall verdict, conformance with
   the issue plan (if any) and the list of problems found (or a statement that everything is
   correct).
3. Label the PR with the verdict. In this repository the verdict labels are named
   `{{label_pass}}` (pass), `{{label_warning}}` (warning) and `{{label_fail}}` (fail); they are
   mutually exclusive. Always do it in **two separate `gh pr edit` calls**, in this order,
   even if you believe the verdict has not changed since the previous cycle:
   1. `gh pr edit {{pr}} --remove-label "{{label_pass}}" --remove-label "{{label_warning}}" --remove-label "{{label_fail}}"`
      (safe and idempotent even when none of them is present);
   2. `gh pr edit {{pr}} --add-label "LABEL"` where LABEL is the label of your verdict (add
      `--remove-label "{{label_needs_human_review}}"` when the verdict is `pass`).
   They must be independent calls: GitHub only emits the `labeled` event that starts the
   next stage when the label is really removed and added again.
4. Finish by returning the structured result `{"verdict": "...", "summary": "..."}` with the
   same verdict as the marker and the label.

Verdict scale:
- `pass`: mergeable as is (or only trivial nits that do not need another cycle).
- `warning`: must be fixed before merge but nothing is fundamentally wrong.
- `fail`: bugs, missing plan items, security issues or broken conventions.

Do not change any code, do not mention anyone, and do not touch any label other than the
three verdict ones (plus `{{label_needs_human_review}}` on `pass`).

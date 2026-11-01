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

## If the Scope section above says that CI failed

- Find the cause from the diff and the logs. When it is in the diff, explain it in an inline
  comment on the line responsible, with the fix you suggest; otherwise explain it in the report.
- The verdict must be `fail`.
- If the failure is clearly unrelated to the diff (runner, network, an outage, a flaky test the
  diff does not touch), say so in the report and do not ask for code changes. Also mention the
  human reviewer in the report ({{human_reviewer}}) and add the label
  `{{label_needs_human_review}}`. The verdict is still `fail`.

## Output

1. One inline comment (`mcp__github_inline_comment__create_inline_comment`) per concrete
   problem, stating its severity.
2. One single summary comment on the PR (`gh pr comment {{pr}}`) whose **first line is exactly**
   `<!-- patufet:review cycle={{cycle}} verdict=VERDICT -->` where VERDICT is `pass`,
   `warning` or `fail`, followed by a title in bold (`**Review: ...**`) and the report: overall
   verdict, conformance with the issue plan (if any) and the list of problems found (or a
   statement that everything is correct). **No line of this comment may start with `#`**: the
   tool rejects such a command, so use bold text instead of Markdown headings.
3. After posting the report, label the PR with the verdict in **one single call**:
   `gh pr edit {{pr}} --add-label "LABEL"`, where LABEL is `{{label_pass}}` for pass,
   `{{label_warning}}` for warning and `{{label_fail}}` for fail (add
   `--remove-label "{{label_needs_human_review}}"` to that call when the verdict is `pass`). The
   workflow has already removed the previous verdict label, so do not remove any. Adding the
   label starts the next stage: add it once.
4. Finish by returning the structured result `{"verdict": "...", "summary": "..."}` with the
   same verdict as the marker and the label.

Verdict scale:
- `pass`: mergeable as is (or only trivial nits that do not need another cycle). Never when CI
  failed.
- `warning`: must be fixed before merge but nothing is fundamentally wrong.
- `fail`: bugs, missing plan items, security issues or broken conventions.

Do not change any code, do not mention anyone, and do not touch any label other than the
three verdict ones (plus `{{label_needs_human_review}}` on `pass`). The only exception to both
is a CI failure unrelated to the diff, as described above.

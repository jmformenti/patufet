Pull request #{{pr}} of the repository `{{repository}}` passed the automatic code review. The
application is already running with this PR's branch, and the environment exported by the
project's e2e hook is:

{{e2e_env}}

Write every comment in this language: **{{language}}**.

## What to test

{{plan_section}}

Read the PR diff (`gh pr diff {{pr}}`) and, with the Playwright tools, drive the application to
check live:

- The basic path (log in with the provided test credentials if the app has authentication, the
  main screens load without errors).
- The specific functionality introduced or modified by this PR.
- Browser console errors or clearly broken UI.

## Output

Post one single comment on the PR (`gh pr comment {{pr}}`) whose **first line is exactly**
`<!-- patufet:e2e run={{run}} verdict=VERDICT -->` where VERDICT is `pass` or `fail`, followed by a
title in bold (`**E2E: ...**`) and a description of what you tested and the result. If something
fails, explain precisely what you saw broken (steps to reproduce, error message, observed
behaviour). **No line of this comment may start with `#`**: the tool rejects such a command, so
use bold text instead of Markdown headings.

If the verdict is `fail`, after posting the comment send the PR back to the fix stage in **one
single call**:
`gh pr edit {{pr}} --remove-label "{{label_pass}}" --remove-label "{{label_warning}}" --add-label "{{label_fail}}"`.
Adding that label starts the next stage: do it once. If the verdict is `pass`, do not touch any
label.

Finish by returning the structured result `{"verdict": "...", "summary": "..."}` with the same
verdict as the marker.

Do not change any code and do not mention anyone: a deterministic step after you asks for the
human review when everything works.

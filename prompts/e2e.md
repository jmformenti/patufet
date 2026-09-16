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
`<!-- patufet:e2e verdict=VERDICT -->` where VERDICT is `pass` or `fail`, followed by a
heading and a description of what you tested and the result. If something fails, explain
precisely what you saw broken (steps to reproduce, error message, observed behaviour).

If the verdict is `fail`, send the PR back to the fix stage by relabelling it in **two
separate `gh pr edit` calls**, in this order:
1. `gh pr edit {{pr}} --remove-label pass --remove-label warning --remove-label fail`
2. `gh pr edit {{pr}} --add-label fail`
They must be independent calls so that GitHub emits a new `labeled` event even if the PR
already had `fail` before. If the verdict is `pass`, do not touch any label.

Finish by returning the structured result `{"verdict": "...", "summary": "..."}` with the same
verdict as the marker.

Do not change any code and do not mention anyone: a deterministic step after you asks for the
human review when everything works.

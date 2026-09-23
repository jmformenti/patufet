# jq module shared by the scripts that read issue / PR comments.

# Keep only comments whose author is trusted — a repository collaborator, or
# one of the bots that post on behalf of the automation. Comments by anybody
# else are never fed to an agent that has write access.
def trusted:
  select((.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))
         or (.user.type == "Bot" and (.user.login | IN("claude[bot]", "github-actions[bot]"))));

# The body of the latest plan comment written by a collaborator (bots cannot
# approve a plan), or empty. $legacy, when not empty, also accepts comments
# containing that heading.
def latest_plan($marker; $legacy):
  [ .[]
    | select(.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))
    | select((.body | contains($marker)) or ($legacy != "" and (.body | contains($legacy))))
  ] | last | .body // empty;

# Trusted comments carrying the "<!-- patufet:<kind>" marker.
def reports($kind):
  [ .[] | trusted | select(.body | contains("<!-- patufet:" + $kind)) ];

# The verdict of the report of one run: the latest trusted
# "<!-- patufet:<kind> ... verdict=V -->" marker whose attributes include $key
# ("cycle=3" for a review, "run=<id>.<attempt>" for e2e). Reports of earlier
# runs never count. Empty when there is none.
def verdict($kind; $key):
  [ reports($kind)[]
    | .body
    | capture("<!-- patufet:" + $kind + "(?<attrs>[^>]*)-->")? | .attrs
    | select((. + " ") | contains(" " + $key + " "))
    | capture("verdict=(?<v>pass|warning|fail)")? | .v
  ] | last // empty;

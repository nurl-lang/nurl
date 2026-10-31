### Fixed

- **`nurl upgrade` finds the latest release when the GitHub API refuses
  it** (Agora #218). `nurl upgrade` and the once-a-day update notice
  (`stdlib/ext/update_check.nu`) asked only `api.github.com`, which allows
  60 unauthenticated requests an hour per IP and answers 403 past that.
  On a shared IP (a CI runner, a cloud sandbox, a NAT gateway) the upgrade
  then said "could not reach the release index (offline?)". The tag now
  comes from github.com's `releases/latest` redirect, which is not
  rate-limited, through the new `httpc_redirect_location` (one request,
  not followed, the redirect's `Location`). The API is asked once, as the
  fallback. When neither names a tag, the message says both reasons it
  can fail and how to pin a version. The installers did the same in
  Agora #216. `tools/tests/test_update_check_latest.py` stands in for
  GitHub and runs in CI.

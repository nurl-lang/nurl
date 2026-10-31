### Fixed

- **The installers find the latest release when the GitHub API refuses
  them** (Agora #216). `install.sh` and `install.ps1` resolved "latest"
  only through `api.github.com`. Unauthenticated, that API allows 60
  requests an hour per IP and answers 403 past that, and CI runners, cloud
  sandboxes and NAT gateways share their IP. An install there stopped with
  "could not determine the latest release tag", after three retries that
  only spent more of the quota. Both installers now read the tag from
  github.com's `releases/latest` redirect, which is not rate-limited, and
  ask the API once, as the fallback. When neither names a tag, the error
  says how to pin one (`--version vX.Y.Z`, `NURL_VERSION`).
  `tools/tests/test_installer_latest.py` stands in for GitHub (the API
  answering 403) and now runs in CI with the unpack controls of
  `test_installer_unpack.py`, which no job had run.

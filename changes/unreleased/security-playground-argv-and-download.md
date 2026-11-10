### Security

- **The unikernel boot command no longer lets a program's `argv` inject
  shell code** (`nurlapi/main.nu`). `/build_unikernel` and the MCP tool
  `nurl_build_unikernel` return ready-to-paste `qemu …` commands whose
  `-append` carries the guest's argv as `args="…"`. The caller-controlled
  `args` was interpolated into that command inside a double-quoted shell
  context, where `$(…)`, backticks, or a stray `"` ran on the caller's
  machine the moment they pasted the command. The argv is now emitted as
  an inert single-quoted token (`__sh_push_sq`); the server's own
  `wallclock=$(date +%s)` stays the one intended expansion. The guest
  still receives the identical `args="…"`.

- **Build artifacts are served as downloads, not renderable pages**
  (`nurlapi/main.nu`). `/download/<build_id>/<file>` streams
  attacker-controlled bytes under an attacker-chosen filename from the
  playground's own origin, and derived a `Content-Type` from the file
  extension — so an ELF a caller named `x.html` came back as `text/html`
  and a browser ran any `<script>` embedded in its bytes (stored XSS).
  Artifact downloads now set `Content-Disposition: attachment` and
  `X-Content-Type-Options: nosniff`, and a type a browser would render as
  active markup (HTML, SVG, XML) is downgraded to
  `application/octet-stream`. The bundled playground UI under `/static`
  is unaffected.

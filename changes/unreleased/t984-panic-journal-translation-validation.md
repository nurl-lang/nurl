### Added

- **Translation validation of the panic journal** (formal phase D1, Agora
  #984). `tools/ncore/tv.sh prog.nu --journal` also checks, in each function
  that may run under a `recover` frame, that at every call that may panic
  the values the frame owns are registered with the journal, so a caught
  panic releases them, each once, and that no registration outlives its
  frame. What may panic is nurlc's own answer: the core IR's inline panic
  points and call graph, and `--may-panic=` for runtime entries.
  `tools/ncore/tv/selftest.sh` shows that it catches a missing
  registration, a missing forget and a double registration.

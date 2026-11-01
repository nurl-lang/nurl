### Changed

- **A fiber's stack grows as deep as the fiber goes, up to 1 MB** (Agora
  #328). A fiber's stack was a fixed 64 KB, and how deep a program recurses
  depends on how it was built. A JSON document at JSON_MAX_DEPTH needs
  about 12 KB at -O2 but about 256 KB at -O0, where no stack slot is
  reused, so a debug build overflowed a fiber on input its release build
  handles. Each fiber now reserves 1 MB of address space (4 MB under
  `NURL_SAN=1`) and turns into memory only the pages it touches. On Linux
  and macOS that is commit-on-touch. On Windows the stack grows a page at a
  time through a guard page, as a thread's does.
  - Idle fibers cost no more: 10,000 of them stay at 45 MB of RSS on Linux,
    and on Windows commit 222 MB instead of 672 MB, since the fixed stack
    was committed whole.
  - A recycled stack keeps at most its top 64 KB as memory.
  - Fiber spawn and exit take the same time.

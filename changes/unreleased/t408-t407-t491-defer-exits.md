### Fixed

- **The borrow checker replays defers in the order they run** (Agora
  #408, #407, #491). Three ways a `;` defer read or stored freed memory
  and compiled clean:
  - A value bound after the last defer is released at a way out before
    the defers run. The checker replayed them while it was still live,
    so a defer reading it through a holder that viewed it (`; { (
    nurl_println . w v ) … }`, then `: String b …  = w @ W { (
    string_data b ) }`) read a released String. It is refused now, at
    `^`, at `\` and at the body's end.
  - A defer armed on some paths only, in a `?` arm or a loop body, was
    never replayed at a way out, so a view of a local it stored into an
    `inout` holder went unchecked. Every way out now also checks the path
    where such a defer ran.
  - A binding of an inner block that a defer armed in that block reads
    stopped being tracked at the block's `}`, so clearing its container
    after the block went unchecked. It now lives, with what it borrows,
    up to the exit where the defer reads it.

  Spec §5.3 now states the order. Programs that were safe stay accepted:
  a defer that only points a holder back, an owned block-local read by a
  defer, a borrow whose container stays unchanged.

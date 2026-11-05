### Added

- **`tcp_listener_pending`: whether a connection waits in a listener's
  accept queue, without taking it** (Agora #500). It answers 1 or 0,
  within a timeout, or -1 where the listener cannot be asked (a stopped
  listener, one over a transport, the wasm bridge). This is when a
  connection arrives as far as the server can know. A client's
  `connect()` returning is not always that moment: on macOS the server
  side of a loopback handshake completes a kernel step later, and with
  every CPU busy that step waits for the busy server thread's next
  `kevent`. `sched_accept_admission` now counts from this arrival, and no
  longer fails on the macOS runner with an admission delay of 32 or 48.

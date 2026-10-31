### Changed

- **Why kTLS stays opt-in, measured on a VAES CPU** (Agora #94).
  `docs/NETWORKING.md` said kTLS pays for bulk traffic and that a CPU
  whose kernel AES-GCM uses VAES might make it the faster path. On a
  Tiger Lake laptop (Linux 6.18, `aes_gcm_enc_update_vaes_avx10_256`)
  the tls-bench bulk cell runs at 2 030–2 200 MB/s under kTLS against
  3 100–3 290 MB/s in the userspace record layer. The kernel's TLS
  `sendmsg` holds the socket lock for the whole 1 MB body, so the ACKs
  that would open the window wait in the backlog (rwnd-limited 36–67 %
  of the time); in 64 KB calls the stall goes (0.1 %) and the server
  runs out of CPU instead, because the kernel's send path costs
  0.46–0.49 ns per byte against the userspace path's 0.27–0.29. The
  section now carries the measurements and the breakdown, and the
  `std/tls.nu` comment no longer says kTLS pays for bulk.

### Changed

- **The HTTP and TLS server tests run on Windows: no test shells out
  any more** (Agora #123). Twelve server/client tests wrote POSIX shell
  into `process_run_shell`: a background `{ python3 -c … > /tmp/x; mv …; } &`,
  a `for … sleep 0.05; cat /tmp/…` loop, `openssl … | grep`. On Windows that
  shell is cmd.exe, so the HTTP server, the TLS servers, the per-IP DoS
  caps, pipelining, panic isolation, SNI, mTLS, ALPN and large TLS records
  were never exercised there. The tests:
  async_http_server_tls, http_server_dos, http_server_limits,
  http_server_panic, http_server_pipelined, http_server_seq,
  http_server_tls, http_server_tls_extras, net_loopback, net_write_pair,
  tls_alpn_server, tls_large_record.
  - The client (python3, curl or openssl) is a child process started with
    an argument vector (`process_spawn` / `process_run`), so there is no
    quoting.
  - What the client prints comes back over its stdout pipe
    (`compiler/tests/loopback_client_mod.nu`), so there are no temp files
    and no polling. A client still running at the timeout is killed, so
    the test fails on its output instead of hanging.
  - Certificates are written to the test's working directory, not
    `/tmp`, by openssl run the same way.
  - The `posix-shell` requirement token is gone from test_skips.sh and
    run_tests.ps1.
  - The POSIX goldens are unchanged.

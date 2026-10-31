### Changed

- **Measured numbers live on the `bench-data` branch, and main moves only
  through the merge queue** (Agora #290). The nine benchmark and fuzz
  workflows used to push their reports straight to main: bench, http,
  http2, http3, pq, tls, wasm, http-torture and fuzz. That was about a dozen
  commits a day, and each one made the merge queue rebuild and re-run every
  group in flight. The v0.83.0 release group ran three times, once for a
  bench commit.
  - The workflows now publish through `tools/bench_data.sh`. If another
    publisher pushes first, it replays onto the new tip, and tls-bench
    renders its per-family index on the branch itself.
  - Only a run of main's code publishes (bench.yml: also a release tag).
  - nurl-lang.org's build fetches `bench/results/latest.json` from the
    branch, and the site is rebuilt whenever the bench workflow completes.
    That also ends a release tag's deploy publishing the previous release's
    table.
  - The reports are gone from main's tree and ignored there. The docs link
    to them on the branch, and `tools/bench_data.sh fetch PATH` copies one
    into a checkout.

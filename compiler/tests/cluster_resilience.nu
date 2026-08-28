// cluster_resilience.nu — offline tests for the resilience layer of
// stdlib/ext/cluster.nu (RetryPolicy backoff + CircuitBreaker).
//
// No network, no real sleeping: exercises the pure backoff math and the
// breaker state machine directly. Timing-deterministic (long cooldown
// never elapses within a test; cooldown=0 is the half-open boundary).
//
// Exercises:
//   * retry_backoff_ms — geometric growth capped at max_delay_ms
//   * circuit breaker — threshold open, success reset, half-open probe
//   * cluster_err_name / cluster_err_retryable for ClCircuitOpen

$ `stdlib/ext/cluster.nu`

@ pb b v → v { ( nurl_print ? v `true\n` `false\n` ) }

@ main → i {
    // ── Backoff: base 100ms, ×2, capped 1000ms ───────────────────
    : RetryPolicy p ( retry_new 5 100 1000 200 F )
    ( nurl_print `backoff:\n` )
    : ~ i k 0
    ~ < k 5 {
        ( nurl_println_int ( retry_backoff_ms p k ) )
        = k + k 1
    }
    // expect 100, 200, 400, 800, 1000 (1600 capped)

    // ── Circuit breaker: threshold 2, long cooldown ──────────────
    : CircuitBreaker cb ( cb_new 2 100000 )
    ( nurl_print `allow fresh: ` ) ( pb ( cb_allow cb ) )  // true
    ( cb_record_failure cb )
    ( nurl_print `open after 1: ` ) ( pb ( cb_is_open cb ) )  // false
    ( cb_record_failure cb )
    ( nurl_print `open after 2: ` ) ( pb ( cb_is_open cb ) )  // true
    ( nurl_print `allow open: ` ) ( pb ( cb_allow cb ) )  // false (cooldown)
    ( nurl_print `fails: ` ) ( nurl_println_int ( cb_fails cb ) )  // 2
    ( cb_record_success cb )
    ( nurl_print `allow recovered: ` ) ( pb ( cb_allow cb ) )  // true
    ( nurl_print `open recovered: ` ) ( pb ( cb_is_open cb ) )  // false
    ( cb_free cb )

    // ── Half-open: cooldown 0 → immediate probe allowed ──────────
    : CircuitBreaker cb2 ( cb_new 1 0 )
    ( cb_record_failure cb2 )
    ( nurl_print `cb2 open: ` ) ( pb ( cb_is_open cb2 ) )  // true
    ( nurl_print `cb2 halfopen allow: ` ) ( pb ( cb_allow cb2 ) )  // true
    ( cb_free cb2 )

    // ── Error classification ─────────────────────────────────────
    ( nurl_println ( cluster_err_name # ClusterErr ClCircuitOpen ) )
    ( nurl_print `net retryable: ` ) ( pb ( cluster_err_retryable # ClusterErr ClNet ) )  // true
    ( nurl_print `badresp retryable: ` ) ( pb ( cluster_err_retryable # ClusterErr ClBadResp ) )  // false
    ( nurl_print `circuit retryable: ` ) ( pb ( cluster_err_retryable # ClusterErr ClCircuitOpen ) )  // false

    ^ 0
}

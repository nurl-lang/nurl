// bench/tls_bench/rust/src/bin/tls_client.rs — reqwest, the Rust peer of
// NURL's packages/http-client (bench/tls_bench/client.nu), for the
// client-side rows. Both are the library an application would actually
// call, used the way an application would; both run single-threaded,
// sequentially, against the same server.
//
//   tls_client <mode> <url> <secs>
//     full    a new connection per request, no session resumption
//     resume  a new connection per request, resuming the cached session
//     ka      one pooled keep-alive connection, requests back to back
//
// Offers what client.nu offers: X25519MLKEM768 first (the provider's
// default list), ALPN http/1.1 — the server's choice decides the rest.
// Prints the same key=value line as tls_load.

use std::time::{Duration, Instant};

use tls_bench::{client_config, pct};

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let (mode, url, secs) = (a[1].clone(), a[2].clone(), a[3].parse::<f64>().unwrap());
    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();

    let tls = client_config("default", "default", mode == "resume");
    let mut b = reqwest::Client::builder().use_preconfigured_tls(tls).http1_only();
    if mode != "ka" {
        b = b.pool_max_idle_per_host(0);
    }
    let client = b.build().unwrap();

    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    rt.block_on(async move {
        let (mut ok, mut err, mut bytes) = (0u64, 0u64, 0u64);
        let mut lat: Vec<u32> = Vec::new();
        let t0 = Instant::now();
        let end = t0 + Duration::from_secs_f64(secs);
        while Instant::now() < end {
            let t = Instant::now();
            let mut rq = client.get(&url);
            if mode != "ka" {
                rq = rq.header("connection", "close");
            }
            let r = async { rq.send().await?.error_for_status()?.bytes().await }.await;
            match r {
                Ok(body) => {
                    ok += 1;
                    bytes += body.len() as u64;
                    lat.push(t.elapsed().as_micros() as u32);
                }
                Err(_) => err += 1,
            }
        }
        let el = t0.elapsed();
        lat.sort_unstable();
        println!(
            "ok={ok} err={err} elapsed_ns={} bytes={bytes} p50_us={} p99_us={} p999_us={}",
            el.as_nanos(),
            pct(&lat, 500),
            pct(&lat, 990),
            pct(&lat, 999)
        );
    });
}

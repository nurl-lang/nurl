// bench/tls_bench/rust/src/bin/tls_load.rs — the TLS load generator.
//
// A deliberately thin HTTP/1.1 client over tokio-rustls (aws-lc-rs), so
// the generator's own cost per handshake is as small as the protocol
// allows and the same generator drives both servers. Closed loop: each of
// --conns tasks runs its next operation the moment the last one returns,
// which saturates the server (rates) — and with --conns 1 measures
// unloaded latency.
//
//   tls_load --addr 127.0.0.1:18543 --mode hs|ka --conns N --secs T
//            [--path /] [--group x25519|p256|mlkem] [--suite aes128|chacha]
//            [--resume 0|1] [--plain 0|1]
//
//   hs  a fresh TCP + TLS connection per request ("Connection: close"):
//       handshake rate and handshake latency (TCP connect → handshake
//       complete, client view), and the request latency on top.
//   ka  N keep-alive connections, requests back to back: request rate,
//       bytes/s, per-request latency. --plain 1 drives plaintext HTTP for
//       the TLS-overhead baseline.
//
// Prints ONE line of key=value pairs (gen_tls_results.py parses it):
//   ok err elapsed_ns bytes resumed hs_p50_us hs_p99_us hs_p999_us
//   p50_us p99_us p999_us

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use rustls::pki_types::ServerName;
use tls_bench::{arg, client_config, pct};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::TlsConnector;

#[derive(Default)]
struct Tally {
    ok: u64,
    err: u64,
    bytes: u64,
    resumed: u64,
    hs_us: Vec<u32>,
    req_us: Vec<u32>,
}

/// Read one HTTP/1.1 response with a Content-Length body; returns the body
/// length. `buf` is reused across calls; bytes past this response (there
/// are none for a request/response client) are not expected.
async fn read_response<S: AsyncRead + Unpin>(s: &mut S, buf: &mut Vec<u8>) -> std::io::Result<u64> {
    buf.clear();
    let mut chunk = [0u8; 65536];
    let head_end;
    loop {
        let n = s.read(&mut chunk).await?;
        if n == 0 {
            return Err(std::io::ErrorKind::UnexpectedEof.into());
        }
        buf.extend_from_slice(&chunk[..n]);
        if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            head_end = i + 4;
            break;
        }
    }
    let head = std::str::from_utf8(&buf[..head_end]).map_err(|_| std::io::ErrorKind::InvalidData)?;
    if !head.starts_with("HTTP/1.1 200") {
        return Err(std::io::ErrorKind::InvalidData.into());
    }
    let clen: u64 = head
        .split("\r\n")
        .find_map(|l| {
            let (k, v) = l.split_once(':')?;
            k.eq_ignore_ascii_case("content-length").then(|| v.trim().parse().ok())?
        })
        .ok_or(std::io::ErrorKind::InvalidData)?;
    let mut have = (buf.len() - head_end) as u64;
    while have < clen {
        let n = s.read(&mut chunk).await?;
        if n == 0 {
            return Err(std::io::ErrorKind::UnexpectedEof.into());
        }
        have += n as u64;
    }
    Ok(clen)
}

async fn request<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S, req: &[u8], buf: &mut Vec<u8>) -> std::io::Result<u64> {
    s.write_all(req).await?;
    s.flush().await?;
    read_response(s, buf).await
}

struct Job {
    addr: String,
    connector: Option<TlsConnector>,
    stop: Arc<AtomicBool>,
    // The end of the measurement window. Every operation races it, so an
    // operation still in flight at the end is dropped, not waited for: a
    // server doing two handshakes a second must not stretch a 10 s cell by
    // the whole queue it has in front of it — and what did not complete
    // inside the window is not counted.
    end: tokio::time::Instant,
}

async fn hs_task(job: Arc<Job>, path: String) -> Tally {
    let mut t = Tally::default();
    let req = format!("GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n").into_bytes();
    let name = ServerName::try_from("localhost").unwrap();
    let mut buf = Vec::with_capacity(1 << 16);
    let conn = job.connector.clone().expect("hs mode needs TLS");
    while !job.stop.load(Ordering::Relaxed) {
        let t0 = Instant::now();
        let op = async {
            let tcp = TcpStream::connect(&job.addr).await?;
            tcp.set_nodelay(true)?;
            let mut tls = conn.connect(name.clone(), tcp).await?;
            let hs = t0.elapsed().as_micros() as u32;
            let resumed = matches!(tls.get_ref().1.handshake_kind(), Some(rustls::HandshakeKind::Resumed));
            let n = request(&mut tls, &req, &mut buf).await?;
            Ok::<_, std::io::Error>((n, resumed, hs))
        };
        let Ok(r) = tokio::time::timeout_at(job.end, op).await else { break };
        match r {
            Ok((n, resumed, hs)) => {
                t.ok += 1;
                t.bytes += n;
                t.resumed += resumed as u64;
                t.hs_us.push(hs);
                t.req_us.push(t0.elapsed().as_micros() as u32);
            }
            Err(e) => {
                note(&e, &mut t);
                tokio::time::sleep(Duration::from_millis(1)).await;
            }
        }
    }
    t
}

/// Count an error; the first one per task goes to stderr, so a failing
/// cell says why instead of only how often.
fn note(e: &std::io::Error, t: &mut Tally) {
    if t.err == 0 {
        eprintln!("tls_load: {e}");
    }
    t.err += 1;
}

/// Requests back to back on one keep-alive connection until stop or an
/// error (the caller then reconnects).
async fn drive<S: AsyncRead + AsyncWrite + Unpin>(mut s: S, job: &Job, req: &[u8], buf: &mut Vec<u8>, t: &mut Tally) {
    while !job.stop.load(Ordering::Relaxed) {
        let t0 = Instant::now();
        let Ok(r) = tokio::time::timeout_at(job.end, request(&mut s, req, buf)).await else { return };
        match r {
            Ok(n) => {
                t.ok += 1;
                t.bytes += n;
                t.req_us.push(t0.elapsed().as_micros() as u32);
            }
            Err(e) => {
                note(&e, t);
                return;
            }
        }
    }
}

async fn ka_task(job: Arc<Job>, path: String) -> Tally {
    let mut t = Tally::default();
    let req = format!("GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n").into_bytes();
    let name = ServerName::try_from("localhost").unwrap();
    let mut buf = Vec::with_capacity(1 << 16);
    while !job.stop.load(Ordering::Relaxed) {
        let Ok(tcp) = tokio::time::timeout_at(job.end, TcpStream::connect(&job.addr)).await else { break };
        let tcp = match tcp {
            Ok(s) => s,
            Err(e) => {
                note(&e, &mut t);
                tokio::time::sleep(Duration::from_millis(1)).await;
                continue;
            }
        };
        let _ = tcp.set_nodelay(true);
        match &job.connector {
            Some(c) => match tokio::time::timeout_at(job.end, c.connect(name.clone(), tcp)).await {
                Ok(Ok(tls)) => drive(tls, &job, &req, &mut buf, &mut t).await,
                Ok(Err(e)) => note(&e, &mut t),
                Err(_) => break,
            },
            None => drive(tcp, &job, &req, &mut buf, &mut t).await,
        }
    }
    t
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let addr = arg(&args, "--addr", "127.0.0.1:18543");
    let mode = arg(&args, "--mode", "hs");
    let conns: usize = arg(&args, "--conns", "64").parse().unwrap();
    let secs: f64 = arg(&args, "--secs", "10").parse().unwrap();
    let path = arg(&args, "--path", "/");
    let group = arg(&args, "--group", "x25519");
    let suite = arg(&args, "--suite", "aes128");
    let resume = arg(&args, "--resume", "0") == "1";
    let plain = arg(&args, "--plain", "0") == "1";

    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
    let connector = (!plain).then(|| TlsConnector::from(Arc::new(client_config(&group, &suite, resume))));
    let stop = Arc::new(AtomicBool::new(false));

    // Worker threads = the CPUs this process may run on (taskset).
    let rt = tokio::runtime::Builder::new_multi_thread().enable_all().build().unwrap();
    let total = rt.block_on(async move {
        let t0 = tokio::time::Instant::now();
        let end = t0 + Duration::from_secs_f64(secs);
        let job = Arc::new(Job { addr, connector, stop: stop.clone(), end });
        let mut hs = Vec::new();
        for _ in 0..conns {
            let (j, p) = (job.clone(), path.clone());
            hs.push(if mode == "hs" { tokio::spawn(hs_task(j, p)) } else { tokio::spawn(ka_task(j, p)) });
        }
        tokio::time::sleep_until(end).await;
        stop.store(true, Ordering::Relaxed);
        let mut all = Tally::default();
        for h in hs {
            let t = h.await.unwrap();
            all.ok += t.ok;
            all.err += t.err;
            all.bytes += t.bytes;
            all.resumed += t.resumed;
            all.hs_us.extend(t.hs_us);
            all.req_us.extend(t.req_us);
        }
        (all, end - t0) // the window; nothing after `end` was counted
    });
    let (mut t, el) = total;
    t.hs_us.sort_unstable();
    t.req_us.sort_unstable();
    println!(
        "ok={} err={} elapsed_ns={} bytes={} resumed={} hs_p50_us={} hs_p99_us={} hs_p999_us={} p50_us={} p99_us={} p999_us={}",
        t.ok,
        t.err,
        el.as_nanos(),
        t.bytes,
        t.resumed,
        pct(&t.hs_us, 500),
        pct(&t.hs_us, 990),
        pct(&t.hs_us, 999),
        pct(&t.req_us, 500),
        pct(&t.req_us, 990),
        pct(&t.req_us, 999),
    );
}

// bench/tls_bench/rust/src/bin/tls_server.rs — the Rust peer of the NURL
// HttpApp server in the TLS benchmark.
//
// Same routes and byte-identical bodies as bench/http_torture/server.nu:
//   GET /     → "Hello, World!\n"   (14 bytes)
//   GET /1k   → 1024    bytes of 'x'
//   GET /16k  → 16384   bytes of 'x'
//   GET /1m   → 1048576 bytes of 'x'
//
//   tls_server <port>                     plaintext HTTP/1.1
//   tls_server <port> <cert.pem> <key.pem> TLS 1.3 (rustls, aws-lc-rs)
//
// TLS configuration, held equal to NURL's where the two differ by default:
//   * TLS 1.3 only — NURL's server speaks nothing else.
//   * One NewSessionTicket per connection (rustls sends two by default;
//     NURL one) under the provider's stateless ticketer, so both servers
//     resume, and both pay the same per-connection ticket cost.
//   * ALPN "http/1.1" — the load generator offers only that, so neither
//     server negotiates h2 and the rows compare HTTP/1.1 to HTTP/1.1.
//   * Groups and suites are the provider defaults; the CLIENT pins the one
//     it measures (tls_load --group / --suite), so the server's preference
//     order never decides a row.

use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::Arc;

use http_body_util::Full;
use hyper::body::Bytes;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response};
use hyper_util::rt::TokioIo;
use tokio::net::TcpListener;

#[derive(Clone)]
struct Bodies {
    hello: Bytes,
    b1k: Bytes,
    b16k: Bytes,
    b1m: Bytes,
}

async fn route(
    req: Request<hyper::body::Incoming>,
    b: Bodies,
) -> Result<Response<Full<Bytes>>, Infallible> {
    let (body, ctype) = match req.uri().path() {
        "/1k" => (b.b1k.clone(), "application/octet-stream"),
        "/16k" => (b.b16k.clone(), "application/octet-stream"),
        "/1m" => (b.b1m.clone(), "application/octet-stream"),
        "/" => (b.hello.clone(), "text/plain; charset=utf-8"),
        _ => {
            return Ok(Response::builder()
                .status(404)
                .body(Full::new(Bytes::from_static(b"not found\n")))
                .unwrap())
        }
    };
    Ok(Response::builder()
        .status(200)
        .header("content-type", ctype)
        .body(Full::new(body))
        .unwrap())
}

fn tls_config(cert_path: &str, key_path: &str) -> Arc<rustls::ServerConfig> {
    let certs = rustls_pemfile::certs(&mut std::io::BufReader::new(
        std::fs::File::open(cert_path).expect("open TLS cert"),
    ))
    .collect::<Result<Vec<_>, _>>()
    .expect("parse TLS cert");
    let key = rustls_pemfile::private_key(&mut std::io::BufReader::new(
        std::fs::File::open(key_path).expect("open TLS key"),
    ))
    .expect("read TLS key")
    .expect("TLS key present");
    let mut cfg = rustls::ServerConfig::builder_with_protocol_versions(&[&rustls::version::TLS13])
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .expect("build rustls ServerConfig");
    cfg.ticketer = rustls::crypto::aws_lc_rs::Ticketer::new().expect("ticketer");
    cfg.send_tls13_tickets = 1;
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Arc::new(cfg)
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
    let args: Vec<String> = std::env::args().collect();
    let port: u16 = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(18444);
    let bodies = Bodies {
        hello: Bytes::from_static(b"Hello, World!\n"),
        b1k: Bytes::from(vec![b'x'; 1024]),
        b16k: Bytes::from(vec![b'x'; 16384]),
        b1m: Bytes::from(vec![b'x'; 1048576]),
    };
    let acceptor = if args.len() >= 4 {
        Some(tokio_rustls::TlsAcceptor::from(tls_config(&args[2], &args[3])))
    } else {
        None
    };
    let addr: SocketAddr = ([127, 0, 0, 1], port).into();
    let listener = TcpListener::bind(addr).await?;
    loop {
        let (stream, _) = listener.accept().await?;
        let _ = stream.set_nodelay(true);
        let bodies = bodies.clone();
        let acceptor = acceptor.clone();
        tokio::spawn(async move {
            let svc = service_fn(move |r| route(r, bodies.clone()));
            match acceptor {
                Some(acc) => {
                    let Ok(tls) = acc.accept(stream).await else { return };
                    let _ = http1::Builder::new()
                        .keep_alive(true)
                        .serve_connection(TokioIo::new(tls), svc)
                        .await;
                }
                None => {
                    let _ = http1::Builder::new()
                        .keep_alive(true)
                        .serve_connection(TokioIo::new(stream), svc)
                        .await;
                }
            }
        });
    }
}

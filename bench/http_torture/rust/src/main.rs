// bench/http_torture/rust — hyper/rustls peer for the torture harness.
//
// Extends bench/rust_http_server with sized routes so both peers serve
// byte-identical bodies:
//   GET /     → "Hello, World!\n"    (14 bytes)
//   GET /1k   → 1024   bytes of 'x'
//   GET /16k  → 16384  bytes of 'x'
//   GET /1m   → 1048576 bytes of 'x'
//
// Each sized body is a precomputed `Bytes` cloned per response (a cheap
// refcount bump, no copy) — the closest Rust analogue to NURL copying a
// precomputed buffer, kept deliberately in each server's idiom rather
// than forced identical.
//
//   default              → plaintext on 127.0.0.1:18081
//   TLS_CERT + TLS_KEY    → HTTPS via tokio-rustls on TLS_PORT (18444)

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

impl Bodies {
    fn new() -> Self {
        Bodies {
            hello: Bytes::from_static(b"Hello, World!\n"),
            b1k: Bytes::from(vec![b'x'; 1024]),
            b16k: Bytes::from(vec![b'x'; 16384]),
            b1m: Bytes::from(vec![b'x'; 1048576]),
        }
    }
}

async fn route(
    req: Request<hyper::body::Incoming>,
    bodies: Bodies,
) -> Result<Response<Full<Bytes>>, Infallible> {
    let (body, ctype) = match req.uri().path() {
        "/1k" => (bodies.b1k.clone(), "application/octet-stream"),
        "/16k" => (bodies.b16k.clone(), "application/octet-stream"),
        "/1m" => (bodies.b1m.clone(), "application/octet-stream"),
        "/" => (bodies.hello.clone(), "text/plain; charset=utf-8"),
        _ => {
            return Ok(Response::builder()
                .status(404)
                .body(Full::new(Bytes::from_static(b"not found\n")))
                .unwrap());
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
    let mut cfg = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .expect("build rustls ServerConfig");
    // Enable TLS 1.3 session resumption so the peer genuinely resumes —
    // rustls issues no tickets unless a ticketer is installed. This makes
    // the resumption dimension a fair, true comparison (NURL, which has no
    // TLS 1.3 resumption, pays a full handshake per connection either way).
    cfg.ticketer = rustls::crypto::ring::Ticketer::new().expect("ticketer");
    Arc::new(cfg)
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let bodies = Bodies::new();

    let tls = match (std::env::var("TLS_CERT"), std::env::var("TLS_KEY")) {
        (Ok(c), Ok(k)) if !c.is_empty() && !k.is_empty() => Some((c, k)),
        _ => None,
    };

    if let Some((cert, key)) = tls {
        let port: u16 = std::env::var("TLS_PORT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(18444);
        let addr: SocketAddr = ([127, 0, 0, 1], port).into();
        let acceptor = tokio_rustls::TlsAcceptor::from(tls_config(&cert, &key));
        let listener = TcpListener::bind(addr).await?;
        println!("rust hyper https_torture listening on https://{}/", addr);
        loop {
            let (stream, _) = listener.accept().await?;
            let acceptor = acceptor.clone();
            let bodies = bodies.clone();
            tokio::spawn(async move {
                let tls_stream = match acceptor.accept(stream).await {
                    Ok(s) => s,
                    Err(_) => return,
                };
                let io = TokioIo::new(tls_stream);
                let _ = http1::Builder::new()
                    .keep_alive(true)
                    .serve_connection(io, service_fn(move |r| route(r, bodies.clone())))
                    .await;
            });
        }
    } else {
        let addr: SocketAddr = ([127, 0, 0, 1], 18081).into();
        let listener = TcpListener::bind(addr).await?;
        println!("rust hyper http_torture listening on http://{}/", addr);
        loop {
            let (stream, _) = listener.accept().await?;
            let io = TokioIo::new(stream);
            let bodies = bodies.clone();
            tokio::spawn(async move {
                let _ = http1::Builder::new()
                    .keep_alive(true)
                    .serve_connection(io, service_fn(move |r| route(r, bodies.clone())))
                    .await;
            });
        }
    }
}

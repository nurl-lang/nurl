// bench/rust_http2_server/src/main.rs — minimal hello-world HTTP/2 server
// for the HTTP/2 peer-comparison benchmark (bench/run_http2.sh).
//
// Two modes, one binary — the bench harness runs both:
//   * default          → cleartext HTTP/2, prior knowledge (RFC 9113 §3.4),
//                        on 127.0.0.1:18091
//   * TLS_CERT + TLS_KEY set (PEM paths) → HTTP/2 over TLS via tokio-rustls
//                        with ALPN "h2", on the port named by TLS_PORT
//                        (default 18451)
//
// Serves "Hello, World!\n" (14 bytes, text/plain) on `/`, the same body as
// the HTTP/1.1 peers, so the two reports are comparable per request.
//
// hyper's `http2` connection builder is what axum / warp / tonic drive
// underneath; hitting it directly gives the cleanest "as fast as Rust
// HTTP/2 gets" datapoint. The tokio multi-thread runtime (one worker per
// core) matches the NURL peer's fiber-per-connection async runtime.
//
// Build:
//     cargo build --release --manifest-path bench/rust_http2_server/Cargo.toml

use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::Arc;

use http_body_util::Full;
use hyper::body::Bytes;
use hyper::server::conn::http2;
use hyper::service::service_fn;
use hyper::{Request, Response};
use hyper_util::rt::{TokioExecutor, TokioIo};
use tokio::net::TcpListener;

async fn hello(_req: Request<hyper::body::Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let body = "Hello, World!\n";
    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/plain; charset=utf-8")
        .body(Full::new(Bytes::from(body)))
        .unwrap())
}

// Load a PEM cert chain + private key into a rustls ServerConfig that
// offers HTTP/2 over ALPN.
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
    cfg.alpn_protocols = vec![b"h2".to_vec()];
    Arc::new(cfg)
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let _ = rustls::crypto::ring::default_provider().install_default();

    let tls = match (std::env::var("TLS_CERT"), std::env::var("TLS_KEY")) {
        (Ok(c), Ok(k)) if !c.is_empty() && !k.is_empty() => Some((c, k)),
        _ => None,
    };

    if let Some((cert, key)) = tls {
        let port: u16 = std::env::var("TLS_PORT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(18451);
        let addr: SocketAddr = ([127, 0, 0, 1], port).into();
        let acceptor = tokio_rustls::TlsAcceptor::from(tls_config(&cert, &key));
        let listener = TcpListener::bind(addr).await?;
        println!("rust hyper http2 server listening on https://{}/ (ALPN h2)", addr);

        loop {
            let (stream, _) = listener.accept().await?;
            let acceptor = acceptor.clone();
            tokio::spawn(async move {
                let tls_stream = match acceptor.accept(stream).await {
                    Ok(s) => s,
                    Err(_) => return, // handshake failure: drop the connection
                };
                let io = TokioIo::new(tls_stream);
                if let Err(err) = http2::Builder::new(TokioExecutor::new())
                    .serve_connection(io, service_fn(hello))
                    .await
                {
                    eprintln!("rust hyper http2 server: connection error: {:?}", err);
                }
            });
        }
    } else {
        let addr: SocketAddr = ([127, 0, 0, 1], 18091).into();
        let listener = TcpListener::bind(addr).await?;
        println!("rust hyper http2 server listening on http://{}/ (h2c prior knowledge)", addr);

        loop {
            let (stream, _) = listener.accept().await?;
            let io = TokioIo::new(stream);
            tokio::spawn(async move {
                if let Err(err) = http2::Builder::new(TokioExecutor::new())
                    .serve_connection(io, service_fn(hello))
                    .await
                {
                    eprintln!("rust hyper http2 server: connection error: {:?}", err);
                }
            });
        }
    }
}

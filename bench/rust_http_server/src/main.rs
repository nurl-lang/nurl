// bench/http_server.rs — minimal hello-world HTTP server for the
// peer-comparison benchmark (Tier D #3).
//
// Two modes, one binary — the bench harness runs both:
//   * default          → plaintext HTTP on 127.0.0.1:18081
//   * TLS_CERT + TLS_KEY set (PEM paths) → HTTPS/TLS via tokio-rustls,
//                         on the port named by TLS_PORT (default 18444)
//
// Serves "Hello, World!\n" (14 bytes, text/plain) on `/`.
//
// Why hyper directly? hyper is the de-facto Rust HTTP library — it's
// what `actix-web`, `axum`, and `warp` build on. Hitting hyper itself
// gives the cleanest "as fast as Rust HTTP gets" datapoint without
// the framework overhead a higher-level crate would add. TLS is
// tokio-rustls — the same rustls stack `axum`/`warp` reach for.
//
// Build:
//     cargo build --release --manifest-path bench/rust_http_server/Cargo.toml
//
// The runner script bench/run_http.sh drives both modes automatically.

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

async fn hello(_req: Request<hyper::body::Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let body = "Hello, World!\n";
    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/plain; charset=utf-8")
        .body(Full::new(Bytes::from(body)))
        .unwrap())
}

// Load a PEM cert chain + private key into a rustls ServerConfig.
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

    let cfg = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .expect("build rustls ServerConfig");
    Arc::new(cfg)
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    // Default the crypto provider so ServerConfig::builder() works without
    // an explicit provider selection.
    let _ = rustls::crypto::ring::default_provider().install_default();

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
        println!("rust hyper https_server listening on https://{}/", addr);

        loop {
            let (stream, _) = listener.accept().await?;
            let acceptor = acceptor.clone();
            tokio::spawn(async move {
                let tls_stream = match acceptor.accept(stream).await {
                    Ok(s) => s,
                    Err(_) => return, // handshake failure: drop the connection
                };
                let io = TokioIo::new(tls_stream);
                if let Err(err) = http1::Builder::new()
                    .keep_alive(true)
                    .serve_connection(io, service_fn(hello))
                    .await
                {
                    eprintln!("rust hyper https_server: connection error: {:?}", err);
                }
            });
        }
    } else {
        let addr: SocketAddr = ([127, 0, 0, 1], 18081).into();
        let listener = TcpListener::bind(addr).await?;
        println!("rust hyper http_server listening on http://{}/", addr);

        loop {
            let (stream, _) = listener.accept().await?;
            let io = TokioIo::new(stream);
            tokio::spawn(async move {
                // Keep the connection open across requests just like NURL's
                // server_run does — http1::Builder's default already does
                // HTTP/1.1 keep-alive.
                if let Err(err) = http1::Builder::new()
                    .keep_alive(true)
                    .serve_connection(io, service_fn(hello))
                    .await
                {
                    eprintln!("rust hyper http_server: connection error: {:?}", err);
                }
            });
        }
    }
}

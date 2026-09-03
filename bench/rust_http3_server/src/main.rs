// bench/rust_http3_server/src/main.rs — minimal hello-world HTTP/3 server
// for the HTTP/3 peer-comparison benchmark (bench/run_http3.sh).
//
// quinn terminates QUIC (rustls for the TLS 1.3 handshake, ALPN "h3"),
// h3 + h3-quinn speak HTTP/3 and QPACK on top. Serves "Hello, World!\n"
// (14 bytes, text/plain) on every request, the same body as the HTTP/1.1
// and HTTP/2 peers, so the three reports are comparable per request.
//
// Env: TLS_CERT / TLS_KEY (PEM paths, required), TLS_PORT (default 18461).
// Listens on 127.0.0.1:TLS_PORT over UDP.
//
// Build:
//     cargo build --release --manifest-path bench/rust_http3_server/Cargo.toml

use std::net::SocketAddr;
use std::sync::Arc;

use bytes::Bytes;
use h3::server::RequestStream;
use http::{Response, StatusCode};
use quinn::crypto::rustls::QuicServerConfig;

fn load_certs(path: &str) -> Vec<rustls::pki_types::CertificateDer<'static>> {
    let pem = std::fs::read(path).expect("read TLS_CERT");
    rustls_pemfile::certs(&mut &pem[..])
        .collect::<Result<Vec<_>, _>>()
        .expect("parse certs")
}

fn load_key(path: &str) -> rustls::pki_types::PrivateKeyDer<'static> {
    let pem = std::fs::read(path).expect("read TLS_KEY");
    rustls_pemfile::private_key(&mut &pem[..])
        .expect("parse key")
        .expect("no private key in TLS_KEY")
}

async fn serve_request<S>(mut stream: RequestStream<S, Bytes>)
where
    S: h3::quic::BidiStream<Bytes>,
{
    // Drain the (empty) request body first: dropping it unread makes the
    // h3 crate send STOP_SENDING, which h2load counts as a failed request.
    while let Ok(Some(_chunk)) = stream.recv_data().await {}
    let resp = Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "text/plain; charset=utf-8")
        .body(())
        .unwrap();
    if stream.send_response(resp).await.is_err() {
        return;
    }
    let _ = stream.send_data(Bytes::from_static(b"Hello, World!\n")).await;
    let _ = stream.finish().await;
}

#[tokio::main]
async fn main() {
    let cert_path = std::env::var("TLS_CERT").expect("TLS_CERT");
    let key_path = std::env::var("TLS_KEY").expect("TLS_KEY");
    let port: u16 = std::env::var("TLS_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(18461);

    let mut tls = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(load_certs(&cert_path), load_key(&key_path))
        .expect("tls config");
    tls.alpn_protocols = vec![b"h3".to_vec()];
    tls.max_early_data_size = 0;

    let quic_tls = QuicServerConfig::try_from(tls).expect("quic tls");
    let server_config = quinn::ServerConfig::with_crypto(Arc::new(quic_tls));
    let addr: SocketAddr = ([127, 0, 0, 1], port).into();
    let endpoint = quinn::Endpoint::server(server_config, addr).expect("bind udp");
    eprintln!("http3_server: listening on udp {addr}");

    while let Some(incoming) = endpoint.accept().await {
        tokio::spawn(async move {
            let conn = match incoming.await {
                Ok(c) => c,
                Err(_) => return,
            };
            let mut h3_conn = match h3::server::Connection::new(h3_quinn::Connection::new(conn)).await {
                Ok(c) => c,
                Err(_) => return,
            };
            loop {
                match h3_conn.accept().await {
                    Ok(Some(resolver)) => {
                        tokio::spawn(async move {
                            if let Ok((_req, stream)) = resolver.resolve_request().await {
                                serve_request(stream).await;
                            }
                        });
                    }
                    Ok(None) => break,
                    Err(_) => break,
                }
            }
        });
    }
}

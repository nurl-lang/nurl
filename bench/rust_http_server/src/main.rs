// bench/http_server.rs — minimal hello-world HTTP server for the
// peer-comparison benchmark (Tier D #3).
//
// Same shape as bench/http_server.nu: listens on 127.0.0.1:18081
// (different port so the runner can keep all three peers alive
// simultaneously if needed). Serves "Hello, World!\n" (14 bytes,
// text/plain) on `/`.
//
// Why hyper directly? hyper is the de-facto Rust HTTP library — it's
// what `actix-web`, `axum`, and `warp` build on. Hitting hyper itself
// gives the cleanest "as fast as Rust HTTP gets" datapoint without
// the framework overhead a higher-level crate would add.
//
// Build:
//     cargo build --release --manifest-path bench/http_server.cargo.toml
//
// Run:
//     ./target/release/http_server
//
// The runner script bench/run_http.sh does both automatically.

use std::convert::Infallible;
use std::net::SocketAddr;

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

#[tokio::main]
async fn main() -> std::io::Result<()> {
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

// bench/rust_http_server — the Rust side of the HTTP peer benchmark
// (Tier D #3).
//
// Two modes, one binary — the bench harness runs both:
//   * default          → plaintext HTTP on 127.0.0.1:18081
//   * TLS_CERT + TLS_KEY set (PEM paths) → HTTPS/TLS via tokio-rustls,
//                         on the port named by TLS_PORT (default 18444)
//
// Routes — the same as bench/http_server.nu, answer for answer:
//
//   /                  "Hello, World!\n" (14 bytes, text/plain)
//   /plaintext         "Hello, World!"
//   /json              {"message":"Hello, World!"}, serialised per request
//
// and, when DATABASE_URL names a Postgres (schema: bench/http_db_schema.sql),
// the TechEmpower database tests plus HttpArena's async-db profile:
// /db, /queries?queries=N, /fortunes, /updates?queries=N,
// /async-db?min=&max=&limit= (see http_server.nu for what each returns).
//
// Why hyper directly? hyper is the de-facto Rust HTTP library — it's
// what `actix-web`, `axum`, and `warp` build on. Hitting hyper itself
// gives the cleanest "as fast as Rust HTTP gets" datapoint without
// the framework overhead a higher-level crate would add. TLS is
// tokio-rustls — the same rustls stack `axum`/`warp` reach for. The
// database is tokio-postgres: one client, its statements prepared once,
// requests from every task pipelined on its one connection — the same
// shape as the NURL server's one packages/psql connection — and the N
// queries of one /queries or /updates request sent together
// (`try_join_all`), so they share round trips too.
//
// Build:
//     cargo build --release --manifest-path bench/rust_http_server/Cargo.toml
//
// The runner script bench/run_http.sh drives every mode automatically.

use std::cell::Cell;
use std::convert::Infallible;
use std::fmt::Write as _;
use std::net::SocketAddr;
use std::sync::Arc;

use futures_util::future::try_join_all;
use http_body_util::Full;
use hyper::body::Bytes;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response};
use hyper_util::rt::TokioIo;
use serde::Serialize;
use tokio::net::TcpListener;
use tokio_postgres::{Client, NoTls, Statement};

type Resp = Response<Full<Bytes>>;

fn respond(status: u16, ctype: &'static str, body: impl Into<Bytes>) -> Resp {
    Response::builder()
        .status(status)
        .header("content-type", ctype)
        .body(Full::new(body.into()))
        .unwrap()
}

fn text(body: &'static str) -> Resp {
    respond(200, "text/plain; charset=utf-8", body)
}

fn json<T: Serialize>(v: &T) -> Resp {
    respond(200, "application/json; charset=utf-8", serde_json::to_vec(v).unwrap())
}

fn db_error(e: tokio_postgres::Error) -> Resp {
    respond(500, "text/plain; charset=utf-8", e.to_string())
}

// ── request parameters ───────────────────────────────────────────────

// The integer value of query parameter `key`, or `dflt` when it is absent
// or not an integer.
fn query_int(req: &Request<hyper::body::Incoming>, key: &str, dflt: i32) -> i32 {
    req.uri()
        .query()
        .and_then(|q| {
            q.split('&').find_map(|kv| {
                let (k, v) = kv.split_once('=').unwrap_or((kv, ""));
                (k == key).then(|| v.parse().ok()).flatten()
            })
        })
        .unwrap_or(dflt)
}

// TechEmpower's `queries`: absent or not an integer → 1, then 1..500.
fn query_count(req: &Request<hyper::body::Incoming>) -> usize {
    query_int(req, "queries", 1).clamp(1, 500) as usize
}

// A random World id, 1..10000: SplitMix64 over a per-thread counter.
fn world_id() -> i32 {
    thread_local!(static STATE: Cell<u64> = Cell::new(0x853c_49e6_748f_ea9b ^ std::process::id() as u64));
    STATE.with(|s| {
        let mut z = s.get().wrapping_add(0x9e37_79b9_7f4a_7c15);
        s.set(z);
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^= z >> 31;
        (z % 10_000) as i32 + 1
    })
}

// ── JSON ─────────────────────────────────────────────────────────────

#[derive(Serialize)]
struct Message {
    message: &'static str,
}

#[derive(Serialize)]
struct World {
    id: i32,
    #[serde(rename = "randomNumber")]
    random_number: i32,
}

#[derive(Serialize)]
struct Rating {
    score: i32,
    count: i32,
}

// The text columns are borrowed from the row (no copy), as the NURL side
// escapes them straight from psql's cell views.
#[derive(Serialize)]
struct Item<'a> {
    id: i32,
    name: &'a str,
    category: &'a str,
    price: i32,
    quantity: i32,
    active: bool,
    tags: serde_json::Value,
    rating: Rating,
}

#[derive(Serialize)]
struct Items<'a> {
    items: Vec<Item<'a>>,
    count: usize,
}

// ── the database ─────────────────────────────────────────────────────

struct Db {
    client: Client,
    world: Statement,
    fortunes: Statement,
    update: Statement,
    items: Statement,
}

async fn db_connect(url: &str) -> Result<Db, tokio_postgres::Error> {
    let (client, conn) = tokio_postgres::connect(url, NoTls).await?;
    tokio::spawn(async move {
        if let Err(e) = conn.await {
            eprintln!("rust hyper http_server: database connection: {e}");
        }
    });
    let world = client.prepare("SELECT id, randomnumber FROM world WHERE id = $1").await?;
    let fortunes = client.prepare("SELECT id, message FROM fortune").await?;
    let update = client
        .prepare(
            "UPDATE world SET randomnumber = v.rn FROM (SELECT unnest($1::int[]) AS id, \
             unnest($2::int[]) AS rn) AS v WHERE world.id = v.id",
        )
        .await?;
    let items = client
        .prepare(
            "SELECT id, name, category, price, quantity, active, tags, rating_score, rating_count \
             FROM items WHERE price BETWEEN $1 AND $2 LIMIT $3",
        )
        .await?;
    Ok(Db { client, world, fortunes, update, items })
}

async fn world_get(db: &Db, id: i32) -> Result<World, tokio_postgres::Error> {
    let row = db.client.query_one(&db.world, &[&id]).await?;
    Ok(World { id, random_number: row.get(1) })
}

async fn worlds(db: &Db, n: usize) -> Result<Vec<World>, tokio_postgres::Error> {
    try_join_all((0..n).map(|_| world_get(db, world_id()))).await
}

async fn h_db(db: &Db) -> Resp {
    match world_get(db, world_id()).await {
        Ok(w) => json(&w),
        Err(e) => db_error(e),
    }
}

async fn h_queries(db: &Db, n: usize) -> Resp {
    match worlds(db, n).await {
        Ok(ws) => json(&ws),
        Err(e) => db_error(e),
    }
}

async fn h_updates(db: &Db, n: usize) -> Resp {
    let mut ws = match worlds(db, n).await {
        Ok(ws) => ws,
        Err(e) => return db_error(e),
    };
    for w in ws.iter_mut() {
        w.random_number = world_id();
    }
    // One statement for the lot, its rows in id order: two requests
    // updating overlapping rows then lock them in the same order and
    // cannot deadlock each other.
    let mut order: Vec<usize> = (0..n).collect();
    order.sort_unstable_by_key(|&k| ws[k].id);
    let ids: Vec<i32> = order.iter().map(|&k| ws[k].id).collect();
    let rns: Vec<i32> = order.iter().map(|&k| ws[k].random_number).collect();
    if let Err(e) = db.client.execute(&db.update, &[&ids, &rns]).await {
        return db_error(e);
    }
    json(&ws)
}

// HTML-escape `text` onto `out`: & < > " ' — enough for element content
// and quoted attribute values alike.
fn push_escaped(out: &mut String, text: &str) {
    let mut start = 0;
    for (k, b) in text.bytes().enumerate() {
        let entity = match b {
            b'&' => "&amp;",
            b'<' => "&lt;",
            b'>' => "&gt;",
            b'"' => "&quot;",
            b'\'' => "&#39;",
            _ => continue,
        };
        out.push_str(&text[start..k]);
        out.push_str(entity);
        start = k + 1;
    }
    out.push_str(&text[start..]);
}

async fn h_fortunes(db: &Db) -> Resp {
    let rows = match db.client.query(&db.fortunes, &[]).await {
        Ok(rows) => rows,
        Err(e) => return db_error(e),
    };
    let mut fs: Vec<(i32, String)> = Vec::with_capacity(rows.len() + 1);
    for row in &rows {
        fs.push((row.get(0), row.get(1)));
    }
    fs.push((0, "Additional fortune added at request time.".to_string()));
    fs.sort_by(|a, b| a.1.cmp(&b.1));
    let mut out = String::with_capacity(2048);
    out.push_str(
        "<!DOCTYPE html><html><head><title>Fortunes</title></head><body><table>\
         <tr><th>id</th><th>message</th></tr>",
    );
    for (id, message) in &fs {
        let _ = write!(out, "<tr><td>{id}</td><td>");
        push_escaped(&mut out, message);
        out.push_str("</td></tr>");
    }
    out.push_str("</table></body></html>");
    respond(200, "text/html; charset=utf-8", out)
}

async fn h_async_db(db: &Db, req: &Request<hyper::body::Incoming>) -> Resp {
    let lo = query_int(req, "min", 10);
    let hi = query_int(req, "max", 50);
    let limit = query_int(req, "limit", 50).clamp(1, 50) as i64;
    // HttpArena: a database that is down answers an empty list.
    let rows = db.client.query(&db.items, &[&lo, &hi, &limit]).await.unwrap_or_default();
    let items: Vec<Item<'_>> = rows
        .iter()
        .map(|r| Item {
            id: r.get(0),
            name: r.get(1),
            category: r.get(2),
            price: r.get(3),
            quantity: r.get(4),
            active: r.get(5),
            tags: r.get(6),
            rating: Rating { score: r.get(7), count: r.get(8) },
        })
        .collect();
    let count = items.len();
    json(&Items { items, count })
}

// ── routing ──────────────────────────────────────────────────────────

async fn route(req: Request<hyper::body::Incoming>, db: Option<Arc<Db>>) -> Result<Resp, Infallible> {
    let resp = match (req.uri().path(), db.as_deref()) {
        ("/", _) => text("Hello, World!\n"),
        ("/plaintext", _) => text("Hello, World!"),
        ("/json", _) => json(&Message { message: "Hello, World!" }),
        ("/db", Some(db)) => h_db(db).await,
        ("/queries", Some(db)) => h_queries(db, query_count(&req)).await,
        ("/fortunes", Some(db)) => h_fortunes(db).await,
        ("/updates", Some(db)) => h_updates(db, query_count(&req)).await,
        ("/async-db", Some(db)) => h_async_db(db, &req).await,
        _ => respond(404, "text/plain; charset=utf-8", "Not Found"),
    };
    Ok(resp)
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

    // The database routes exist only when a database is configured, so
    // the plaintext and TLS suites run the same binary with no Postgres.
    let db = match std::env::var("DATABASE_URL") {
        Ok(url) if !url.is_empty() => match db_connect(&url).await {
            Ok(db) => Some(Arc::new(db)),
            Err(e) => {
                eprintln!("rust hyper http_server: DATABASE_URL: {e}");
                std::process::exit(1);
            }
        },
        _ => None,
    };

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
            let db = db.clone();
            tokio::spawn(async move {
                let tls_stream = match acceptor.accept(stream).await {
                    Ok(s) => s,
                    Err(_) => return, // handshake failure: drop the connection
                };
                let io = TokioIo::new(tls_stream);
                if let Err(err) = http1::Builder::new()
                    .keep_alive(true)
                    .serve_connection(io, service_fn(move |req| route(req, db.clone())))
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
            let db = db.clone();
            tokio::spawn(async move {
                // Keep the connection open across requests just like NURL's
                // server_run does — http1::Builder's default already does
                // HTTP/1.1 keep-alive.
                if let Err(err) = http1::Builder::new()
                    .keep_alive(true)
                    .serve_connection(io, service_fn(move |req| route(req, db.clone())))
                    .await
                {
                    eprintln!("rust hyper http_server: connection error: {:?}", err);
                }
            });
        }
    }
}

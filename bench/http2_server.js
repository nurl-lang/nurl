// bench/http2_server.js — minimal hello-world HTTP/2 server for the
// HTTP/2 peer-comparison benchmark (bench/run_http2.sh).
//
// Same shape as bench/http_server.nu and the Rust sibling in
// bench/rust_http2_server. Two modes, one file — the harness runs both:
//   * default              → cleartext HTTP/2, prior knowledge
//                            (RFC 9113 §3.4), on 127.0.0.1:18092
//   * TLS_CERT + TLS_KEY set (PEM paths) → HTTP/2 over TLS with ALPN "h2"
//                            on the port named by TLS_PORT (default 18452),
//                            via Node's built-in `http2` module,
//                            allowHTTP1: false so every connection is h2
//
// Serves "Hello, World!\n" (14 bytes, text/plain) on `/` — the body the
// HTTP/1.1 peers serve, so the two reports compare per request. Uses only
// Node's built-in `http2` module, no dependencies (the same rule the other
// bench peers follow).
//
// Run:
//     node bench/http2_server.js                              # h2c
//     TLS_CERT=c.pem TLS_KEY=k.pem node bench/http2_server.js  # h2 over TLS
//
// The runner script bench/run_http2.sh does this automatically.

const http2 = require('node:http2');
const fs = require('node:fs');

const BODY = 'Hello, World!\n';

function onStream(stream) {
    stream.respond({
        ':status': 200,
        'content-type': 'text/plain; charset=utf-8',
    });
    stream.end(BODY);
}

const certPath = process.env.TLS_CERT;
const keyPath = process.env.TLS_KEY;

let server;
let port;
let scheme;

if (certPath && keyPath) {
    server = http2.createSecureServer({
        cert: fs.readFileSync(certPath),
        key: fs.readFileSync(keyPath),
        allowHTTP1: false,
    });
    port = Number(process.env.TLS_PORT) || 18452;
    scheme = 'https';
} else {
    server = http2.createServer();
    port = 18092;
    scheme = 'http';
}

server.on('stream', onStream);
// A session that errors (a client vanishing mid-run) must not take the
// process down with it.
server.on('sessionError', () => {});

server.listen(port, '127.0.0.1', () => {
    console.log(`node http2 server listening on ${scheme}://127.0.0.1:${port}/`);
});

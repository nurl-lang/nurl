// bench/http_server.js — minimal hello-world HTTP server for the
// peer-comparison benchmark (Tier D #3).
//
// Same shape as bench/http_server.nu and bench/http_server.rs.
// Listens on 127.0.0.1:18082. Serves "Hello, World!\n" (14 bytes,
// text/plain) on `/`. Uses Node's built-in `http` module — no
// dependencies — so the comparison stays "what ships in the
// standard distribution" (the same rule the existing
// bench/json_parse.{js,nu,py,rs} files follow).
//
// Run:
//     node bench/http_server.js
//
// The runner script bench/run_http.sh does this automatically.

const http = require('node:http');

const BODY = 'Hello, World!\n';

const server = http.createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(BODY);
});

// Default keep-alive timeout in Node 24 is 5s. Bump it so a 10s
// benchmark run doesn't see connection churn between hot requests.
server.keepAliveTimeout = 60_000;
server.headersTimeout = 65_000;

server.listen(18082, '127.0.0.1', () => {
    console.log('node http_server listening on http://127.0.0.1:18082/');
});

// bridge: run the BROWSER worker.js unmodified inside a node worker thread
import { parentPort } from 'node:worker_threads';
import { readFileSync } from 'node:fs';

globalThis.postMessage = (m) => parentPort.postMessage(m);
const src = readFileSync(new URL('../web/worker.js', import.meta.url), 'utf8');
(new Function(src))();          // sloppy scope → `onmessage =` lands on globalThis
parentPort.on('message', (d) => globalThis.onmessage({ data: d }));

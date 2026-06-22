import { Container, getContainer } from "@cloudflare/containers";
import { decideAction } from "./recovery";

// ── Why this file has a custom fetch override ─────────────────────────────
//
// The playground container occasionally wedges: the nurlapi server process is
// still *alive* (so the Durable Object's view stays `running` + `'healthy'`)
// but is no longer accepting connections on port 8000 — e.g. after a heavy
// compile burst, an OOM that took a worker rather than PID 1, or a soft
// deadlock. In that state the @cloudflare/containers runtime never recovers
// on its own:
//
//   • startAndWaitForPorts() early-returns WITHOUT re-checking the port when
//     `state.status === 'healthy' && container.running` (container.ts), so it
//     never notices the server stopped listening; and
//   • containerFetch() catches the proxy failure and returns a 500 whose body
//     is "Error proxying request to container: The container is not listening
//     in the TCP address 10.0.0.1:8000" — but it does NOT mark the instance
//     unhealthy or restart it.
//
// So every subsequent request repeats the same failure forever, and since
// continuous traffic keeps renewActivityTimeout() alive the instance never
// even sleeps to recycle. A clean crash/OOM of PID 1 *does* self-heal (the DO
// sees `!running` and cold-starts), which is exactly why the stuck state is a
// hang, not a crash.
//
// The fix: detect that wedged-proxy 500, force-destroy the instance (so the
// next start spins up a fresh container), and replay the request. This makes
// any server-side wedge self-heal within a single request instead of becoming
// a sticky outage.

// How many times to recycle+retry before giving up and surfacing the error.
// (The classification policy lives in ./recovery, kept pure for unit testing.)
const MAX_RECYCLES = 2;

export class NurlContainer extends Container<Env> {
  defaultPort = 8000;
  sleepAfter = "10m";
  // Forward all env vars the API container needs here if any.
  envVars = {
    NURL_API_URL: this.env.NURL_API_URL,
  };

  // The default onError rethrows; rethrowing from a lifecycle callback (e.g.
  // the one destroy() triggers) can poison the DO. Log and swallow instead.
  override onError(error: unknown): void {
    console.error("[nurl-container] lifecycle error:", error);
  }

  // Self-healing proxy — see the file header for the failure it recovers from.
  override async fetch(request: Request): Promise<Response> {
    // WebSocket upgrades (the /pptws voice relay) can't be buffered or
    // replayed — proxy them straight through with no retry.
    if ((request.headers.get("Upgrade") ?? "").toLowerCase() === "websocket") {
      return super.fetch(request);
    }

    // Buffer the body once so the request can be replayed after a recycle.
    // Compile requests (POST /build*) carry the user's source and must
    // survive a retry; their bodies are small.
    const hasBody = request.method !== "GET" && request.method !== "HEAD";
    const bodyBuf = hasBody ? await request.arrayBuffer() : undefined;
    const replay = (): Request =>
      new Request(request.url, {
        method: request.method,
        headers: request.headers,
        body: bodyBuf,
      });

    for (let attempt = 0; ; attempt++) {
      let res: Response;
      try {
        res = await super.fetch(replay());
      } catch (e) {
        // The base fetch normally returns a 500 rather than throwing, but a
        // thrown error is just as much a proxy failure — recycle and retry.
        if (attempt >= MAX_RECYCLES) {
          const msg = e instanceof Error ? e.message : String(e);
          return new Response(`container unavailable after recovery: ${msg}\n`, {
            status: 502,
          });
        }
        await this.recycle("threw: " + (e instanceof Error ? e.message : String(e)));
        continue;
      }

      // Cheap exits first; only read the body for an unresolved 500.
      if (res.status !== 500 || attempt >= MAX_RECYCLES) return res;

      const action = decideAction(res.status, await res.clone().text(), attempt, MAX_RECYCLES);
      if (action === "return") return res; // a real 500 from nurlapi — pass through.
      if (action === "recycle") {
        // Alive-but-not-listening: the DO won't re-check the port on its own,
        // so tear the instance down — the retry's start spins a fresh one.
        await this.recycle("proxy reported container not listening");
      }
      // "retry" → the instance is already restarting; just re-issue.
    }
  }

  // Force-destroy the current instance so the next containerFetch starts a
  // fresh one. Never throws (destroy() routes through our swallowing onError,
  // but guard anyway so a failed teardown can't abort the retry loop).
  private async recycle(reason: string): Promise<void> {
    console.warn(`[nurl-container] recycling instance: ${reason}`);
    try {
      await this.destroy();
    } catch (e) {
      console.error("[nurl-container] destroy() during recycle failed:", e);
    }
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Singleton: one container instance routes all requests. The fetch
    // override above makes that instance self-heal, so a wedge recovers
    // within a request instead of becoming a sticky outage. For horizontal
    // scaling swap to getRandom(env.NURL_CONTAINER, N) (uses max_instances).
    const container = getContainer(env.NURL_CONTAINER);
    return container.fetch(request);
  },
} satisfies ExportedHandler<Env>;

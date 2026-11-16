import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// The only place the real Gemini key lives. Set via:
//   supabase secrets set GEMINI_API_KEY=... --project-ref afmlredstfjtcblujeyv
// It never ships to the app, so it can't be pulled out of the APK.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

// Per-user, per-day caps. Tune here without an app release. Vision (photo
// scans) is capped tighter than text since it's the pricier call.
const DAILY_LIMITS: Record<string, number> = {
  text: 60,
  vision: 30,
};

// "latest" alias rather than a dated version (e.g. gemini-2.5-flash) --
// Google periodically retires dated models for new API keys entirely
// (confirmed 2026-08: gemini-2.5-flash/-lite both 404 as "no longer
// available to new users"), and the alias is what keeps working without an
// app release when that happens again.
const DEFAULT_MODEL = "gemini-flash-latest";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Gemini's own 429/503 are transient under load — a short jittered backoff
// clears most of them without the user ever seeing a failure. Anything else
// (4xx from a bad request, auth errors) is not retried.
async function callGeminiWithRetry(
  model: string,
  payload: unknown,
): Promise<Response> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`;
  const backoffMs = [0, 500, 1500];
  let lastRes: Response | null = null;
  for (const base of backoffMs) {
    if (base > 0) {
      await new Promise((r) => setTimeout(r, base + Math.floor(Math.random() * 250)));
    }
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (res.status !== 429 && res.status !== 503) return res;
    lastRes = res;
  }
  return lastRes!;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  if (!GEMINI_API_KEY) {
    return jsonResponse(
      { error: "server_misconfigured", message: "GEMINI_API_KEY secret not set" },
      500,
    );
  }

  let body: {
    kind?: string;
    model?: string;
    contents?: unknown;
    generationConfig?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "bad_request", message: "invalid JSON body" }, 400);
  }

  const kind = body.kind;
  if (kind !== "text" && kind !== "vision") {
    return jsonResponse({ error: "bad_request", message: "kind must be 'text' or 'vision'" }, 400);
  }
  if (!body.contents) {
    return jsonResponse({ error: "bad_request", message: "contents is required" }, 400);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // Run as the calling user (not the service role) so auth.uid() inside the
  // RPC resolves to them and a request can only ever touch their own quota
  // row, enforced by RLS as a backstop even if the RPC logic ever had a bug.
  const supabase = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: quota, error: quotaError } = await supabase
    .rpc("check_and_increment_ai_usage", {
      p_kind: kind,
      p_daily_limit: DAILY_LIMITS[kind],
    })
    .single();

  if (quotaError) {
    return jsonResponse({ error: "unauthorized", message: quotaError.message }, 401);
  }
  if (!quota?.allowed) {
    return jsonResponse(
      {
        error: "quota_exceeded",
        message: "You've reached today's AI limit. It resets at midnight UTC.",
      },
      429,
    );
  }

  const model = body.model || DEFAULT_MODEL;
  const geminiPayload = {
    contents: body.contents,
    generationConfig: body.generationConfig ?? {},
  };

  const geminiRes = await callGeminiWithRetry(model, geminiPayload);
  const geminiJson = await geminiRes.json().catch(() => null);

  if (!geminiRes.ok) {
    // The quota slot was already spent by check_and_increment above, but
    // Gemini itself failed (rate limit, transient 5xx) — that's not the
    // user's fault, so give the slot back rather than making them burn part
    // of today's allowance on a request that produced nothing.
    await supabase.rpc("refund_ai_usage", { p_kind: kind });
    return jsonResponse(
      {
        error: "upstream_error",
        message: geminiJson?.error?.message ?? "Gemini request failed",
      },
      502,
    );
  }

  const text = (geminiJson?.candidates?.[0]?.content?.parts ?? [])
    .map((p: { text?: string }) => p.text ?? "")
    .join("");

  return jsonResponse({ text, remaining: quota.remaining });
});

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically into every edge function — no secret to set for this one.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // Resolve *who* is asking using their own token, never a client-supplied
  // id — otherwise one user could delete another by editing the request.
  const callerClient = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  const uid = userData.user.id;

  // Everything below needs the service role: deleting another user's
  // auth record and their storage objects are both outside what RLS and the
  // anon key are allowed to do, even for the user's own data.
  const admin = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!);

  // storage.objects has no foreign key to auth.users, so ON DELETE CASCADE
  // on the auth user never reaches the avatar files — remove them first,
  // while the uid is still known to be theirs.
  const { data: files } = await admin.storage.from("avatars").list(uid);
  if (files && files.length > 0) {
    await admin.storage.from("avatars").remove(
      files.map((f) => `${uid}/${f.name}`),
    );
  }

  // Deleting the auth user cascades through every table declared
  // `references auth.users(id) on delete cascade` — profiles, meals,
  // daily_logs, ai_messages, ai_usage, etc. — in this one call.
  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    return jsonResponse(
      { error: "delete_failed", message: deleteError.message },
      500,
    );
  }

  return jsonResponse({ success: true });
});

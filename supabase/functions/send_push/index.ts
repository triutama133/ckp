// Supabase Edge Function: send_push
// Expects JSON: { user_id, title, body }
// Env required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FCM_SERVER_KEY
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const fcmKey = Deno.env.get("FCM_SERVER_KEY") ?? "";

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }
    if (!supabaseUrl || !serviceKey || !fcmKey) {
      return new Response("Missing env vars", { status: 500 });
    }
    const { user_id, title, body } = await req.json();
    if (!user_id || !title || !body) {
      return new Response("Invalid payload", { status: 400 });
    }

    const tokensRes = await fetch(`${supabaseUrl}/rest/v1/device_tokens?user_id=eq.${user_id}&select=token`, {
      headers: {
        "apikey": serviceKey,
        "Authorization": `Bearer ${serviceKey}`,
      },
    });
    const tokens = await tokensRes.json();
    const tokenList = (tokens ?? []).map((t: { token: string }) => t.token).filter(Boolean);
    if (tokenList.length === 0) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), { status: 200 });
    }

    const fcmRes = await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `key=${fcmKey}`,
      },
      body: JSON.stringify({
        registration_ids: tokenList,
        notification: { title, body },
        data: { user_id },
      }),
    });
    const fcmBody = await fcmRes.json();
    return new Response(JSON.stringify({ ok: true, fcm: fcmBody }), { status: 200 });
  } catch (e) {
    return new Response(`Error: ${e}`, { status: 500 });
  }
});

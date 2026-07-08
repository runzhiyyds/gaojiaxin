// Supabase Edge Function: on_points_added
// 依据 point_records 新增记录，给另一方发送 FCM 推送（FCM HTTP v1 + 服务账号）。

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";
import { getFcmAccessToken, sendFcmV1 } from "../_shared/fcm_v1.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// 项目设置 → 服务账号 → 生成新的私钥，下载的 JSON 整份粘贴到 Secrets，名称为 FCM_SERVICE_ACCOUNT_JSON
const fcmServiceAccountJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  try {
    const body = await req.json();
    const {
      record_id,
      couple_space_id,
      to_user_id,
      points,
      note,
    } = body as {
      record_id: string;
      couple_space_id: string;
      to_user_id: string;
      points: number;
      note?: string | null;
    };

    if (!record_id || !couple_space_id || !to_user_id) {
      return new Response("Bad Request", { status: 400 });
    }

    const { data: devices, error: devicesError } = await supabase
      .from("push_devices")
      .select("device_token, platform")
      .eq("user_id", to_user_id)
      .eq("couple_space_id", couple_space_id)
      .eq("is_active", true);

    if (devicesError) {
      console.error("push_devices query error", devicesError);
      return new Response("Error querying devices", { status: 500 });
    }

    const title = `TA 给你加了 ${points} 分`;
    const bodyText = note ? `备注：${note}` : "";

    if (!fcmServiceAccountJson || !devices || devices.length === 0) {
      console.log("No FCM service account or no devices, skipping send");
      return new Response(
        JSON.stringify({ success: true, sent: 0 }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    const projectId = JSON.parse(fcmServiceAccountJson).project_id as string;
    const accessToken = await getFcmAccessToken(fcmServiceAccountJson);
    const sentTokens: string[] = [];

    await Promise.all(
      devices.map(async (d: any) => {
        const token = d.device_token as string;
        try {
          const { ok, error } = await sendFcmV1(
            projectId,
            accessToken,
            token,
            title,
            bodyText,
            {
              type: "points_added",
              recordId: record_id,
              coupleSpaceId: couple_space_id,
            }
          );

          await supabase.from("push_logs").insert({
            user_id: to_user_id,
            couple_space_id,
            device_token: token,
            event_type: "points_added",
            payload: body,
            success: ok,
            error_message: ok ? null : error ?? null,
          });

          if (ok) sentTokens.push(token);
        } catch (err) {
          console.error("FCM send error", err);
          await supabase.from("push_logs").insert({
            user_id: to_user_id,
            couple_space_id,
            device_token: token,
            event_type: "points_added",
            payload: body,
            success: false,
            error_message: `${err}`,
          });
        }
      }),
    );

    return new Response(
      JSON.stringify({ success: true, sent: sentTokens.length }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("on_points_added error", err);
    return new Response("Internal Server Error", { status: 500 });
  }
});


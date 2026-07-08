// Supabase Edge Function: on_redeem_success
// 依据 exchange_records 新增记录或状态变更，给另一方发送 FCM 推送（FCM HTTP v1 + 服务账号）。

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";
import { getFcmAccessToken, sendFcmV1 } from "../_shared/fcm_v1.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
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
      exchange_id,
      couple_space_id,
      from_user_id,
      to_user_id,
      good_name,
      points_spent,
    } = body as {
      exchange_id: string;
      couple_space_id: string;
      from_user_id: string;
      to_user_id: string;
      good_name: string;
      points_spent: number;
    };

    if (!exchange_id || !couple_space_id || !to_user_id) {
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

    const title = "TA 兑换了一个奖励";
    const bodyText = `${good_name}（消耗 ${points_spent} 分）`;

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
              type: "redeem_success",
              redeemId: exchange_id,
              coupleSpaceId: couple_space_id,
              fromUserId: from_user_id,
            }
          );

          await supabase.from("push_logs").insert({
            user_id: to_user_id,
            couple_space_id,
            device_token: token,
            event_type: "redeem_success",
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
            event_type: "redeem_success",
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
    console.error("on_redeem_success error", err);
    return new Response("Internal Server Error", { status: 500 });
  }
});


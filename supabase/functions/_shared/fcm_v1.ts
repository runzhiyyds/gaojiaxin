// FCM HTTP v1：用服务账号 JSON 取 OAuth2 并发送推送（替代已停用的 Legacy Server Key）

export interface ServiceAccountJson {
  type?: string;
  project_id: string;
  private_key_id?: string;
  private_key: string;
  client_email: string;
  client_id?: string;
  auth_uri?: string;
  token_uri?: string;
  auth_provider_x509_cert_url?: string;
  client_x509_cert_url?: string;
}

let cachedAccessToken: { token: string; exp: number } | null = null;

/** 用服务账号 JSON 获取 Google OAuth2 access_token（带简单缓存） */
export async function getFcmAccessToken(serviceAccountJsonStr: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.exp > now + 60) {
    return cachedAccessToken.token;
  }

  const sa: ServiceAccountJson = JSON.parse(serviceAccountJsonStr);
  const privateKeyPem = sa.private_key.replace(/\\n/g, "\n");
  const clientEmail = sa.client_email;
  const audience = "https://oauth2.googleapis.com/token";

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: audience,
    iat: now,
    exp: now + 3600,
  };

  const encoder = new TextEncoder();
  const b64 = (b: Uint8Array) =>
    btoa(String.fromCharCode(...b))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");

  const headerB64 = b64(encoder.encode(JSON.stringify(header)));
  const payloadB64 = b64(encoder.encode(JSON.stringify(payload)));
  const signatureInput = `${headerB64}.${payloadB64}`;

  const pemContents = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(signatureInput)
  );
  const sigB64 = b64(new Uint8Array(sig));
  const jwt = `${signatureInput}.${sigB64}`;

  const tokenRes = await fetch(audience, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const text = await tokenRes.text();
    throw new Error(`FCM OAuth2 token failed: ${tokenRes.status} ${text}`);
  }

  const tokenData = await tokenRes.json();
  const accessToken = tokenData.access_token as string;
  cachedAccessToken = { token: accessToken, exp: now + 3500 };
  return accessToken;
}

/** 调用 FCM HTTP v1 发送一条消息；data 的值必须是字符串 */
export async function sendFcmV1(
  projectId: string,
  accessToken: string,
  deviceToken: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<{ ok: boolean; error?: string }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const bodyPayload = {
    message: {
      token: deviceToken,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(bodyPayload),
  });

  if (res.ok) return { ok: true };
  const errText = await res.text();
  return { ok: false, error: errText };
}

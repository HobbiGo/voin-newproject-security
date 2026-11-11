// VOIN: pemulihan login simulasi, bukan pembayaran nyata.

const enc = new TextEncoder();

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff"
    }
  });
}

function b64(bytes) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s)
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function unb64(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  s += "=".repeat((4 - s.length % 4) % 4);
  return Uint8Array.from(atob(s), c => c.charCodeAt(0));
}

async function signingKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

async function equalSecret(a, b) {
  const x = new Uint8Array(
    await crypto.subtle.digest("SHA-256", enc.encode(a))
  );
  const y = new Uint8Array(
    await crypto.subtle.digest("SHA-256", enc.encode(b))
  );
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

async function issueToken(secret, origin) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64(enc.encode(JSON.stringify({
    alg: "HS256",
    typ: "JWT"
  })));
  const payload = b64(enc.encode(JSON.stringify({
    sub: "simulation-admin",
    iss: "voin-simulation",
    aud: origin,
    exp: now + 3600
  })));
  const message = header + "." + payload;
  const signature = await crypto.subtle.sign(
    "HMAC",
    await signingKey(secret),
    enc.encode(message)
  );
  return message + "." + b64(new Uint8Array(signature));
}

async function authenticated(request, env) {
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return false;

  try {
    const parts = auth.slice(7).split(".");
    if (parts.length !== 3) return false;

    const header = JSON.parse(
      new TextDecoder().decode(unb64(parts[0]))
    );
    if (header.alg !== "HS256") return false;

    const valid = await crypto.subtle.verify(
      "HMAC",
      await signingKey(env.JWT_SECRET),
      unb64(parts[2]),
      enc.encode(parts[0] + "." + parts[1])
    );
    if (!valid) return false;

    const payload = JSON.parse(
      new TextDecoder().decode(unb64(parts[1]))
    );

    return (
      payload.sub === "simulation-admin" &&
      payload.iss === "voin-simulation" &&
      payload.aud === new URL(request.url).origin &&
      payload.exp > Math.floor(Date.now() / 1000)
    );
  } catch {
    return false;
  }
}

const HTML = `<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VOIN — Login Simulasi</title>
<style>
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;
padding:24px;background:#06111c;color:#e4f5f4;font-family:Arial,sans-serif}
.card{width:100%;max-width:430px;padding:32px;background:#0b202b;
border:1px solid #34535a;border-radius:16px}
h1{font-size:24px;color:#a3f5e3;margin:0 0 12px}
p{font-size:14px;line-height:1.6;color:#abc4c5}
input,button{width:100%;padding:14px;border-radius:8px;font-size:16px}
input{background:#081923;color:white;border:1px solid #416368;margin:12px 0}
button{background:#83e5d3;color:#062626;border:0;cursor:pointer;font-weight:bold}
button:disabled{opacity:.5;cursor:wait}
#message{min-height:24px;white-space:pre-wrap}
.secondary{margin-top:18px;background:#203c43;color:#e4f5f4}
[hidden]{display:none!important}
</style>
</head>
<body>
<section class="card">
  <h1>VOIN SECURITY</h1>
  <p>Dashboard simulasi. Tidak menerima dana investor.</p>

  <form id="loginForm">
    <label for="pin">PIN / password simulasi</label>
    <input id="pin" type="password" autocomplete="current-password"
      minlength="12" maxlength="128" required>
    <button id="loginButton" type="submit">Buka Dashboard</button>
  </form>

  <div id="dashboard" hidden>
    <h2>Login berhasil</h2>
    <p>Backend autentikasi sudah merespons.</p>
    <p>Saldo dan nonce: belum tersambung ke database lama.</p>
    <p>Transfer dan asisten belum diaktifkan pada versi pemulihan ini.
    Tidak ada saldo pengganti yang dibuat.</p>
    <button id="logout" class="secondary">Keluar</button>
  </div>

  <p id="message" role="status" aria-live="polite"></p>
</section>
<script>
const form = document.getElementById("loginForm");
const button = document.getElementById("loginButton");
const message = document.getElementById("message");
const dashboard = document.getElementById("dashboard");
const pinInput = document.getElementById("pin");

form.addEventListener("submit", async function(event) {
  event.preventDefault();
  button.disabled = true;
  message.textContent = "Memeriksa login...";

  try {
    const response = await fetch("/api/login", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({pin: pinInput.value})
    });
    const data = await response.json();

    if (!response.ok || !data.success) {
      throw new Error(data.message || "Login gagal.");
    }

    sessionStorage.setItem("voin_repair_token", data.token);
    pinInput.value = "";
    form.hidden = true;
    dashboard.hidden = false;
    message.textContent = "";
  } catch (error) {
    message.textContent = error.message || "Tidak dapat menghubungi backend.";
  } finally {
    button.disabled = false;
  }
});

document.getElementById("logout").addEventListener("click", function() {
  sessionStorage.removeItem("voin_repair_token");
  dashboard.hidden = true;
  form.hidden = false;
  pinInput.value = "";
  message.textContent = "Sudah keluar.";
});
</script>
</body>
</html>`;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/" || url.pathname === "/index.html") {
      return new Response(HTML, {
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
          "X-Content-Type-Options": "nosniff",
          "Content-Security-Policy":
            "default-src 'none'; script-src 'unsafe-inline'; " +
            "style-src 'unsafe-inline'; connect-src 'self'; " +
            "form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
        }
      });
    }

    if (url.pathname === "/api/health") {
      return json({
        success: true,
        mode: "simulation",
        transfersEnabled: false
      });
    }

    if (!url.pathname.startsWith("/api/")) {
      return new Response("Not found", {status: 404});
    }

    if (
      !env.ADMIN_PIN || env.ADMIN_PIN.length < 12 ||
      !env.JWT_SECRET || env.JWT_SECRET.length < 32
    ) {
      return json({
        success: false,
        message: "Secret backend belum diatur."
      }, 503);
    }

    if (url.pathname === "/api/login") {
      if (request.method !== "POST") {
        return json({success:false, message:"Gunakan POST."}, 405);
      }

      if (!env.LOGIN_LIMITER) {
        return json({
          success:false,
          message:"Pembatas percobaan login belum tersedia."
        }, 503);
      }

      const ip = request.headers.get("CF-Connecting-IP");
      if (!ip) {
        return json({success:false, message:"Koneksi tidak valid."}, 503);
      }

      const limit = await env.LOGIN_LIMITER.limit({key:"login:" + ip});
      if (!limit.success) {
        return json({
          success:false,
          message:"Terlalu banyak percobaan. Tunggu sebelum mencoba lagi."
        }, 429);
      }

      const origin = request.headers.get("Origin");
      if (origin && origin !== url.origin) {
        return json({success:false, message:"Origin ditolak."}, 403);
      }

      if (!(request.headers.get("Content-Type") || "")
        .includes("application/json")) {
        return json({success:false, message:"Gunakan JSON."}, 415);
      }

      const raw = await request.text();
      if (raw.length > 1024) {
        return json({success:false, message:"Permintaan terlalu besar."}, 413);
      }

      let body;
      try {
        body = JSON.parse(raw);
      } catch {
        return json({success:false, message:"JSON tidak valid."}, 400);
      }

      if (
        typeof body.pin !== "string" ||
        body.pin.length > 128 ||
        !await equalSecret(body.pin, env.ADMIN_PIN)
      ) {
        return json({success:false, message:"PIN salah."}, 401);
      }

      return json({
        success:true,
        token:await issueToken(env.JWT_SECRET, url.origin)
      });
    }

    if (!await authenticated(request, env)) {
      return json({success:false, message:"Silakan login."}, 401);
    }

    return json({
      success:false,
      message:"Login pulih; database, transfer, dan asisten lama belum disambungkan."
    }, 503);
  }
};

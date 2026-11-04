// Edge Function "api": unico punto di accesso dell'app.
//
// Secrets richiesti (Supabase → Edge Functions → Secrets):
//   APP_TOKEN           token condiviso con l'app (header "x-app-token")
//   OPENROUTER_API_KEY  chiave API di OpenRouter
//   OPENROUTER_MODEL    (opzionale) modello vision, default google/gemini-2.5-flash
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY sono forniti automaticamente.
//
// Rotte (prefisso /functions/v1/api):
//   GET    /categories
//   POST   /categories            {name, color?}
//   PATCH  /categories/:id        {name?, color?, sort_order?}
//   DELETE /categories/:id
//   POST   /scan                  {image_base64, mime_type?}
//   GET    /receipts?from=&to=&limit=&offset=
//   GET    /receipts/:id
//   PATCH  /receipts/:id          {merchant?, purchased_at?, total?, currency?, notes?}
//   DELETE /receipts/:id
//   PATCH  /items/:id             {category_id?, description?, total?, quantity?, unit_price?}
//   GET    /stats?from=&to=       totali per categoria

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const DEFAULT_MODEL = "google/gemini-2.5-flash";
const MAX_IMAGE_B64 = 12 * 1024 * 1024; // ~9 MB di immagine

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const x = enc.encode(a);
  const y = enc.encode(b);
  let diff = x.length ^ y.length;
  const len = Math.max(x.length, y.length);
  for (let i = 0; i < len; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

function num(v: unknown, digits = 2): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(String(v).replace(",", "."));
  if (!Number.isFinite(n)) return null;
  const f = 10 ** digits;
  return Math.round(n * f) / f;
}

function pick<T extends Record<string, unknown>>(src: T, keys: string[]) {
  const out: Record<string, unknown> = {};
  for (const k of keys) if (k in src) out[k] = src[k];
  return out;
}

async function body(req: Request): Promise<Record<string, unknown>> {
  try {
    const b = await req.json();
    if (b && typeof b === "object" && !Array.isArray(b)) return b;
  } catch (_) { /* fallthrough */ }
  throw new HttpError(400, "Body JSON non valido");
}

function check<T>(res: { data: T; error: { message: string } | null }): T {
  if (res.error) throw new HttpError(500, res.error.message);
  return res.data;
}

// ---------------------------------------------------------------- OCR / AI

async function analyzeReceipt(imageB64: string, mime: string, categories: string[]) {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) throw new HttpError(503, "OPENROUTER_API_KEY non configurata");
  const model = Deno.env.get("OPENROUTER_MODEL") || DEFAULT_MODEL;

  const schema = {
    type: "object",
    additionalProperties: false,
    required: ["is_receipt", "merchant", "purchased_at", "total", "currency", "payment_method", "items"],
    properties: {
      is_receipt: { type: "boolean", description: "false se l'immagine non è uno scontrino/ricevuta" },
      merchant: { type: ["string", "null"], description: "Nome dell'esercente" },
      purchased_at: { type: ["string", "null"], description: "Data e ora d'acquisto ISO 8601, es. 2026-11-04T18:30:00" },
      total: { type: "number", description: "Totale pagato (TOTALE COMPLESSIVO)" },
      currency: { type: "string", description: "Codice ISO 4217, es. EUR" },
      payment_method: { type: ["string", "null"], description: "contanti, carta, bancomat, ..." },
      items: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["description", "quantity", "unit_price", "total", "category"],
          properties: {
            description: { type: "string" },
            quantity: { type: ["number", "null"] },
            unit_price: { type: ["number", "null"] },
            total: { type: "number", description: "Importo della riga; negativo per sconti" },
            category: { type: "string", enum: categories },
          },
        },
      },
    },
  };

  const prompt = [
    "Sei un sistema OCR per scontrini (spesso italiani).",
    "Estrai esercente, data/ora, totale complessivo, valuta, metodo di pagamento e TUTTE le righe articolo.",
    "Per ogni riga indica descrizione leggibile, quantità, prezzo unitario, importo totale della riga",
    `e assegna una categoria scegliendo SOLO tra: ${categories.join(", ")}.`,
    "Sconti e abbuoni vanno come righe con importo negativo, nella categoria dell'articolo scontato se evidente, altrimenti 'Altro'.",
    "Ignora righe di IVA, subtotali, resto e totali: non sono articoli.",
    "Usa il punto come separatore decimale. Se un dato non è leggibile usa null.",
    "Rispondi solo con il JSON richiesto.",
  ].join(" ");

  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "X-Title": "Scontrini",
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      // Chiede ai provider di non conservare/usare i dati per training.
      provider: { data_collection: "deny" },
      response_format: {
        type: "json_schema",
        json_schema: { name: "receipt", strict: true, schema },
      },
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: `data:${mime};base64,${imageB64}` } },
          ],
        },
      ],
    }),
  });

  if (!res.ok) {
    const txt = await res.text();
    console.error("OpenRouter error", res.status, txt.slice(0, 500));
    throw new HttpError(502, `Errore OpenRouter (${res.status})`);
  }
  const data = await res.json();
  let content: string = data?.choices?.[0]?.message?.content ?? "";
  content = content.trim().replace(/^```(?:json)?\s*/i, "").replace(/```$/, "").trim();
  try {
    return { model: data?.model ?? model, parsed: JSON.parse(content) };
  } catch (_) {
    console.error("Risposta AI non JSON", content.slice(0, 500));
    throw new HttpError(502, "Risposta del modello non interpretabile");
  }
}

async function scan(req: Request) {
  const b = await body(req);
  const image = String(b.image_base64 ?? "");
  const mime = String(b.mime_type ?? "image/jpeg");
  if (!image) throw new HttpError(400, "image_base64 mancante");
  if (image.length > MAX_IMAGE_B64) throw new HttpError(413, "Immagine troppo grande");
  if (!/^image\/(jpeg|png|webp|heic|heif)$/.test(mime)) throw new HttpError(400, "mime_type non supportato");

  const cats = check(await db.from("categories").select("id,name").order("sort_order"));
  const names = cats.map((c) => c.name);
  const byName = new Map(cats.map((c) => [c.name.toLowerCase(), c.id]));
  const fallback = byName.get("altro") ?? null;

  const { model, parsed } = await analyzeReceipt(image, mime, names);
  if (parsed.is_receipt === false) throw new HttpError(422, "L'immagine non sembra uno scontrino");

  const items = Array.isArray(parsed.items) ? parsed.items : [];
  const itemsSum = items.reduce((s: number, it: any) => s + (num(it.total) ?? 0), 0);
  const total = num(parsed.total) ?? num(itemsSum) ?? 0;

  let purchasedAt: string | null = null;
  if (parsed.purchased_at) {
    const d = new Date(parsed.purchased_at);
    if (!isNaN(d.getTime())) purchasedAt = d.toISOString();
  }

  const receipt = check(
    await db.from("receipts").insert({
      merchant: parsed.merchant ?? null,
      purchased_at: purchasedAt ?? new Date().toISOString(),
      total,
      currency: (parsed.currency || "EUR").toString().toUpperCase().slice(0, 3),
      payment_method: parsed.payment_method ?? null,
      ai_model: model,
      ai_raw: parsed,
    }).select().single(),
  );

  if (items.length) {
    const rows = items.map((it: any, i: number) => ({
      receipt_id: receipt.id,
      position: i,
      description: String(it.description ?? "").slice(0, 300) || "(senza descrizione)",
      quantity: num(it.quantity, 3),
      unit_price: num(it.unit_price),
      total: num(it.total) ?? 0,
      category_id: byName.get(String(it.category ?? "").toLowerCase()) ?? fallback,
    }));
    const ins = await db.from("receipt_items").insert(rows);
    if (ins.error) {
      await db.from("receipts").delete().eq("id", receipt.id);
      throw new HttpError(500, ins.error.message);
    }
  }
  return json(await getReceipt(receipt.id), 201);
}

// ---------------------------------------------------------------- CRUD

async function getReceipt(id: string) {
  const r = await db.from("receipts")
    .select("id,merchant,purchased_at,total,currency,payment_method,notes,ai_model,created_at," +
      "items:receipt_items(id,position,description,quantity,unit_price,total,category_id)")
    .eq("id", id)
    .order("position", { referencedTable: "receipt_items" })
    .maybeSingle();
  const data = check(r);
  if (!data) throw new HttpError(404, "Scontrino non trovato");
  return data;
}

function range(url: URL) {
  return { from: url.searchParams.get("from"), to: url.searchParams.get("to") };
}

async function route(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*?\/api(?=\/|$)/, "").replace(/\/+$/, "") || "/";
  const seg = path.split("/").filter(Boolean);
  const m = req.method;

  if (m === "GET" && path === "/health") return json({ ok: true });

  // categorie
  if (seg[0] === "categories") {
    if (seg.length === 1 && m === "GET") {
      return json(check(await db.from("categories").select("id,name,color,sort_order").order("sort_order")));
    }
    if (seg.length === 1 && m === "POST") {
      const b = await body(req);
      const name = String(b.name ?? "").trim();
      if (!name) throw new HttpError(400, "name mancante");
      return json(check(await db.from("categories").insert({
        name, color: String(b.color ?? "#607D8B"), sort_order: Number(b.sort_order ?? 500),
      }).select().single()), 201);
    }
    if (seg.length === 2 && m === "PATCH") {
      const b = pick(await body(req), ["name", "color", "sort_order"]);
      return json(check(await db.from("categories").update(b).eq("id", seg[1]).select().single()));
    }
    if (seg.length === 2 && m === "DELETE") {
      check(await db.from("categories").delete().eq("id", seg[1]));
      return json({ ok: true });
    }
  }

  if (seg[0] === "scan" && m === "POST") return await scan(req);

  // scontrini
  if (seg[0] === "receipts") {
    if (seg.length === 1 && m === "GET") {
      const { from, to } = range(url);
      const limit = Math.min(Number(url.searchParams.get("limit") ?? 100), 500);
      const offset = Number(url.searchParams.get("offset") ?? 0);
      let q = db.from("receipts")
        .select("id,merchant,purchased_at,total,currency,payment_method,created_at,items:receipt_items(count)")
        .order("purchased_at", { ascending: false })
        .range(offset, offset + limit - 1);
      if (from) q = q.gte("purchased_at", from);
      if (to) q = q.lt("purchased_at", to);
      return json(check(await q));
    }
    if (seg.length === 2 && m === "GET") return json(await getReceipt(seg[1]));
    if (seg.length === 2 && m === "PATCH") {
      const b = pick(await body(req), ["merchant", "purchased_at", "total", "currency", "notes", "payment_method"]);
      if ("total" in b) b.total = num(b.total) ?? 0;
      check(await db.from("receipts").update(b).eq("id", seg[1]));
      return json(await getReceipt(seg[1]));
    }
    if (seg.length === 2 && m === "DELETE") {
      check(await db.from("receipts").delete().eq("id", seg[1]));
      return json({ ok: true });
    }
  }

  // righe
  if (seg[0] === "items" && seg.length === 2 && m === "PATCH") {
    const b = pick(await body(req), ["category_id", "description", "total", "quantity", "unit_price"]);
    if ("total" in b) b.total = num(b.total) ?? 0;
    if ("unit_price" in b) b.unit_price = num(b.unit_price);
    if ("quantity" in b) b.quantity = num(b.quantity, 3);
    return json(check(await db.from("receipt_items").update(b).eq("id", seg[1]).select().single()));
  }

  // statistiche per categoria
  if (seg[0] === "stats" && m === "GET") {
    const { from, to } = range(url);
    let q = db.from("receipt_items").select("total,category_id,receipts!inner(purchased_at)");
    if (from) q = q.gte("receipts.purchased_at", from);
    if (to) q = q.lt("receipts.purchased_at", to);
    const rows = check(await q) as { total: number; category_id: number | null }[];
    const map = new Map<number | null, number>();
    for (const r of rows) map.set(r.category_id, (map.get(r.category_id) ?? 0) + Number(r.total));
    return json([...map.entries()].map(([category_id, total]) => ({ category_id, total: num(total) })));
  }

  throw new HttpError(404, "Rotta non trovata");
}

Deno.serve(async (req) => {
  try {
    const expected = Deno.env.get("APP_TOKEN");
    if (!expected || expected.length < 24) throw new HttpError(503, "APP_TOKEN non configurato sul server");
    const got = req.headers.get("x-app-token") ?? "";
    if (!timingSafeEqual(got, expected)) throw new HttpError(401, "Token non valido");
    return await route(req);
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error(e);
    return json({ error: "Errore interno" }, 500);
  }
});

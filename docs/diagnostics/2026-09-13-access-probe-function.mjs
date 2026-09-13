// DIAGNOSTIC ONLY, on a temporary Netlify site that is deleted after the test.
// One access path per call (?t=label), so each call stays well inside the function time limit.
// The project's honest user agent; nothing disguises the client or attempts the challenge.
// Archives are never downloaded: a 4-byte range request, aborted if the server ignores it.
const UA = "Mozilla/5.0 (Project Hammer downstream analysis; +https://github.com/MhBaigtw/DE-Grocery-Price-tool)";
const TARGETS = {
  "jf-stamp":      ["https://jacobfilipp.com/hammerdata/hammer-lastupdated.txt", null],
  "ph-stamp":      ["https://projecthammer.org/hammerdata/hammer-lastupdated.txt", null],
  "www-jf-stamp":  ["https://www.jacobfilipp.com/hammerdata/hammer-lastupdated.txt", null],
  "http-jf-stamp": ["http://jacobfilipp.com/hammerdata/hammer-lastupdated.txt", null],
  "jf-sqlite-zip": ["https://jacobfilipp.com/hammerdata/hammer-3-compressed.zip", "0-3"],
  "ph-sqlite-zip": ["https://projecthammer.org/hammerdata/hammer-3-compressed.zip", "0-3"],
  "jf-csv-zip":    ["https://jacobfilipp.com/hammerdata/hammer-5-csv.zip", "0-3"],
  "jf-svg":        ["https://jacobfilipp.com/hammerdata/hammer-6-product-plot.svg", null],
  "ph-home":       ["https://projecthammer.org/", null],
  "jf-home":       ["https://jacobfilipp.com/hammer/", null],
};

export default async (req) => {
  const t = new URL(req.url).searchParams.get("t");
  if (t === "ip") {
    const ip = await fetch("https://api.ipify.org").then(r => r.text()).catch(e => "error " + e.message);
    return Response.json({ip, region: process.env.AWS_REGION || null});
  }
  const target = TARGETS[t];
  if (!target) return Response.json({error: "unknown target"}, {status: 400});
  const [url, range] = target;
  const headers = {"User-Agent": UA};
  if (range) headers["Range"] = "bytes=" + range;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const r = await fetch(url, {headers, redirect: "manual", signal: ctrl.signal});
    const len = Number(r.headers.get("content-length") || 0);
    let cls = "OTHER", bytes = 0;
    if (r.status === 200 && len > 1048576) {
      ctrl.abort();
      cls = "TOO-LARGE(range ignored; aborted before body)";
    } else {
      const buf = Buffer.from(await r.arrayBuffer());
      bytes = buf.length;
      const text = buf.toString("latin1");
      if (text.includes("request is being verified")) cls = "CHALLENGE";
      else if (text.startsWith("PK")) cls = "ZIP-HEADER";
      else if (/^\d{4}-\d{2}-\d{2} [\d:.]+ \(Eastern Time\)/.test(text)) cls = "STAMP";
      else if (/<svg/i.test(text)) cls = "SVG";
      else if (/<html/i.test(text)) cls = "HTML-PAGE";
    }
    return Response.json({t, status: r.status, bytes, type: r.headers.get("content-type"),
      location: r.headers.get("location"), server: r.headers.get("server"), cls,
      region: process.env.AWS_REGION || null});
  } catch (e) {
    return Response.json({t, error: e.name + ": " + e.message, region: process.env.AWS_REGION || null});
  } finally {
    clearTimeout(timer);
  }
};

export const config = { path: "/probe" };

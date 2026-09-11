/* Measure the tool on a mid-range phone profile: real numbers, not an impression.
 *
 * WHY THIS EXISTS. Phase 4 §3 measured phone *width* and found the layout holds at 380px.
 * That says nothing about whether the page is usable there. The extract is ~7.5 MB of JSON
 * and a mid-range phone parses it on a far slower core than the machine that built it, so
 * "it looks fine on a laptop at 380px wide" is exactly the kind of assumption this project
 * is supposed to refuse to publish.
 *
 * WHAT IT EMULATES (Chrome DevTools Protocol, the same machinery DevTools' own device mode
 * uses, so the throttling is real rather than a guess):
 *   - 380 x 780 CSS px, deviceScaleFactor 2, mobile viewport
 *   - CPU throttled 4x, the multiplier Lighthouse uses to stand in for a mid-tier phone
 *   - Slow 4G: 1.6 Mbit/s down, 750 kbit/s up, 150 ms RTT
 *   - cold cache, disabled for every request
 *
 * WHAT IT REPORTS:
 *   - first contentful paint
 *   - time to interactive, defined for this page as the moment the coverage panel is
 *     populated, which is when products.json has been parsed and the search box will
 *     actually answer. That is the first moment the tool is usable, not the first moment
 *     something is on screen.
 *   - the split between network and CPU, because the fix differs: shipping less is the
 *     answer to one, shipping it differently is the answer to the other.
 *   - the cost of a search, and the cost of the first history click, which pulls the whole
 *     history file.
 *
 * Usage: node scripts/measure_phone.js [url] [--runs N] [--cpu 4] [--no-throttle]
 */
"use strict";
const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const ARGS = process.argv.slice(2);
const URL_ = ARGS.find(a => a.startsWith("http")) || "http://127.0.0.1:8901/tool/";
const argVal = (flag, dflt) => {
  const i = ARGS.indexOf(flag);
  return i === -1 ? dflt : Number(ARGS[i + 1]);
};
const RUNS = argVal("--runs", 3);
const CPU = ARGS.includes("--no-throttle") ? 1 : argVal("--cpu", 4);
const THROTTLE_NET = !ARGS.includes("--no-throttle");

const CHROME = [
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
  "/usr/bin/google-chrome", "/usr/bin/chromium",
].find(p => fs.existsSync(p));
if (!CHROME) { console.error("No Chrome found."); process.exit(2); }

const sleep = ms => new Promise(r => setTimeout(r, ms));

// ---- a minimal CDP client over Node's built-in WebSocket --------------------------------
class CDP {
  constructor(ws) { this.ws = ws; this.id = 0; this.pending = new Map(); this.sessions = new Map();
    ws.addEventListener("message", e => {
      const m = JSON.parse(e.data);
      if (m.id && this.pending.has(m.id)) {
        const { resolve, reject } = this.pending.get(m.id); this.pending.delete(m.id);
        m.error ? reject(new Error(m.error.message)) : resolve(m.result);
      }
    });
  }
  send(method, params = {}, sessionId) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
  }
}

// Installed before any page script runs, so nothing is missed and the shipped page is not
// modified to be measurable.
const PROBE = `
window.__m = { fcp: null, lcp: null, interactive: null, firstPaint: null };
try {
  new PerformanceObserver(list => {
    for (const e of list.getEntries()) {
      if (e.name === "first-contentful-paint") window.__m.fcp = e.startTime;
      if (e.name === "first-paint") window.__m.firstPaint = e.startTime;
    }
  }).observe({ type: "paint", buffered: true });
  new PerformanceObserver(list => {
    const es = list.getEntries();
    if (es.length) window.__m.lcp = es[es.length - 1].startTime;
  }).observe({ type: "largest-contentful-paint", buffered: true });
} catch (e) {}
// Interactive: the coverage panel's "Loading the current figures..." placeholder is gone,
// which happens only after products.json is parsed and renderCover has run.
(function poll() {
  if (window.__m.interactive != null) return;
  const el = document.getElementById("covload");
  const body = document.getElementById("covbody");
  if (body && body.innerHTML && !el) { window.__m.interactive = performance.now(); return; }
  requestAnimationFrame(poll);
})();
`;

async function once(run) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "phonemeas-"));
  const port = 9300 + run;
  const chrome = spawn(CHROME, [
    "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
    `--remote-debugging-port=${port}`, `--user-data-dir=${dir}`, "about:blank",
  ], { stdio: "ignore" });

  let version = null;
  for (let i = 0; i < 60 && !version; i++) {
    await sleep(250);
    try { version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json(); } catch {}
  }
  if (!version) { chrome.kill(); throw new Error("Chrome debugging port never came up"); }

  const ws = new WebSocket(version.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener("open", r));
  const cdp = new CDP(ws);

  const { targetId } = await cdp.send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await cdp.send("Target.attachToTarget", { targetId, flatten: true });
  const S = sessionId;

  await cdp.send("Page.enable", {}, S);
  await cdp.send("Network.enable", {}, S);
  await cdp.send("Runtime.enable", {}, S);

  await cdp.send("Emulation.setDeviceMetricsOverride",
    { width: 380, height: 780, deviceScaleFactor: 2, mobile: true }, S);
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: CPU }, S);
  await cdp.send("Network.setCacheDisabled", { cacheDisabled: true }, S);
  if (THROTTLE_NET) {
    await cdp.send("Network.emulateNetworkConditions", {
      offline: false, latency: 150,
      downloadThroughput: (1.6 * 1024 * 1024) / 8,
      uploadThroughput: (750 * 1024) / 8,
    }, S);
  }
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: PROBE }, S);

  await cdp.send("Page.navigate", { url: URL_ }, S);

  const evalJS = async (expr) => {
    const r = await cdp.send("Runtime.evaluate",
      { expression: expr, returnByValue: true, awaitPromise: true }, S);
    return r.result && r.result.value;
  };

  // Wait for interactive, with a ceiling so a hang is reported rather than hidden.
  let m = null;
  for (let i = 0; i < 240; i++) {
    await sleep(250);
    m = await evalJS("JSON.stringify(window.__m || {})").catch(() => null);
    if (m && JSON.parse(m).interactive != null) break;
  }
  m = JSON.parse(m || "{}");

  const res = JSON.parse(await evalJS(`JSON.stringify(
    performance.getEntriesByType("resource").map(r => ({
      name: r.name.split("/").pop(), start: r.startTime, end: r.responseEnd,
      transfer: r.transferSize, decoded: r.decodedBodySize })))`) || "[]");

  // Cost of a search, on the throttled CPU.
  const search = await evalJS(`(() => {
    const q = document.getElementById("q"); if (!q) return null;
    const t0 = performance.now();
    q.value = "milk"; q.dispatchEvent(new Event("input", { bubbles: true }));
    return performance.now() - t0; })()`);

  // Cost of the first history click: this pulls the whole history file.
  const hist = await evalJS(`(async () => {
    const b = document.querySelector("#results button.link"); if (!b) return null;
    const t0 = performance.now();
    b.click();
    for (let i = 0; i < 400; i++) {
      await new Promise(r => setTimeout(r, 50));
      const el = document.querySelector("#results .hist svg");
      if (el) return performance.now() - t0;
    }
    return -1; })()`);

  ws.close(); chrome.kill();
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}
  return { ...m, search, hist, res };
}

const ms = v => (v == null ? "n/a" : (v / 1000).toFixed(2) + " s");

(async () => {
  console.log(`url        : ${URL_}`);
  console.log(`profile    : 380x780 mobile, CPU ${CPU}x, ` +
              (THROTTLE_NET ? "Slow 4G (1.6 Mbit/s, 150 ms RTT)" : "no network throttling") +
              ", cold cache");
  console.log(`runs       : ${RUNS}\n`);

  const all = [];
  for (let i = 0; i < RUNS; i++) {
    process.stdout.write(`  run ${i + 1} ... `);
    try { const r = await once(i); all.push(r); console.log(`interactive ${ms(r.interactive)}`); }
    catch (e) { console.log("FAILED: " + e.message); }
  }
  if (!all.length) { console.log("\nNo run completed."); process.exit(1); }

  const med = k => {
    const v = all.map(r => r[k]).filter(x => typeof x === "number" && x >= 0).sort((a, b) => a - b);
    return v.length ? v[Math.floor(v.length / 2)] : null;
  };
  const products = all[0].res.find(r => r.name === "products.json");
  const history = all.map(r => r.res.find(x => x.name === "history.json")).find(Boolean);

  console.log("\n--- medians of " + all.length + " runs ---");
  console.log(`first contentful paint : ${ms(med("fcp"))}`);
  console.log(`largest contentful paint: ${ms(med("lcp"))}`);
  console.log(`INTERACTIVE (usable)   : ${ms(med("interactive"))}`);
  console.log(`search keystroke       : ${med("search") == null ? "n/a" : med("search").toFixed(0) + " ms"}`);
  console.log(`first history click    : ${ms(med("hist"))}`);
  if (products) {
    console.log(`\nproducts.json          : ${(products.transfer / 1024).toFixed(0)} KB over the wire, ` +
                `${(products.decoded / 1048576).toFixed(2)} MB decoded`);
    console.log(`  download window      : ${ms(products.start)} -> ${ms(products.end)}`);
    const parse = med("interactive") - products.end;
    console.log(`  after download, CPU  : ${parse > 0 ? (parse / 1000).toFixed(2) + " s" : "n/a"}` +
                "   (parse + index + first render)");
  }
  console.log(history ? `history.json           : fetched (${(history.transfer / 1048576).toFixed(2)} MB over the wire)`
                      : `history.json           : NOT fetched on first paint`);
})();

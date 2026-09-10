/* Renders every product in the extract through the tool's own card functions and asserts
 * the honesty rules hold on the OUTPUT, not just on the input.
 *
 * WHY THIS EXISTS. The four Section 2 constraints are enforced in the extract, but the
 * interface can still betray them at render time: by printing a bare "cheapest", by showing
 * a 200-day-old price with no warning, by dropping a chain that has no recent price, or by
 * leaking a pooled figure. Those are output properties and only an output check catches
 * them. The page's script is loaded from index.html itself rather than copied, so this
 * cannot drift from what ships.
 *
 * Run: node scripts/test_tool_render.js
 */
"use strict";
const fs = require("fs"), path = require("path"), vm = require("vm");

const ROOT = path.join(__dirname, "..");
const html = fs.readFileSync(path.join(ROOT, "tool/index.html"), "utf8");
const meta = JSON.parse(fs.readFileSync(path.join(ROOT, "tool/data/meta.json"), "utf8"));
const products = JSON.parse(fs.readFileSync(path.join(ROOT, "tool/data/products.json"), "utf8"));

// Pull the page's real script out of the page. No copy, no drift.
const src = html.match(/<script>([\s\S]*?)<\/script>/)[1];

// Minimal DOM so the script can boot without a browser.
const nodes = {};
const stub = () => ({ innerHTML: "", textContent: "", dataset: {},
                      addEventListener(){}, remove(){}, style:{} });
const sandbox = {
  document: {
    querySelector: s => (nodes[s] = nodes[s] || stub()),
    getElementById: s => (nodes["#" + s] = nodes["#" + s] || stub())
  },
  fetch: () => Promise.reject(new Error("boot fetch disabled; data injected directly")),
  Promise, Math, Number, String, Object, Array, Date, JSON, console,
  setTimeout, isNaN
};
sandbox.__M = meta;
sandbox.__P = products;
vm.createContext(sandbox);
vm.runInContext(src, sandbox);
// Inject the real data instead of fetching it, and do the same per-product preparation
// the page's boot step does, so the search index exists.
vm.runInContext(
  "META = __M; PRODUCTS = __P;" +
  "for (const x of PRODUCTS) {" +
  "  x._s = ((x.name||'') + ' ' + (x.brand||'') + ' ' + (x.size||'')).toLowerCase();" +
  "}", sandbox);

const card = sandbox.card;
let fail = 0, checked = 0;
const bad = (g, msg) => { fail++; if (fail <= 12) console.log("  FAIL " + g + ": " + msg); };

const counts = {0:0, 1:0, 2:0, 3:0};
for (const p of products) {
  const html = card(p);
  checked++;
  const n = p.comparison.n_compared;
  counts[Math.min(3, n)]++;

  // 1. Every chain in the extract appears in the rendered card. Brief 3.2: a chain with no
  //    recent price is shown as "no recent price", never silently dropped.
  for (const o of p.offers) {
    if (!o.chain_label) bad(p.gtin14, "offer has no chain_label: " + o.chain);
    if (!html.includes(o.chain_label))
      bad(p.gtin14, "chain missing from output: " + o.chain);
  }
  // No raw vendor code may reach the reader. "SaveOnFoods" is a key, not a shop name.
  if (/SaveOnFoods/.test(html)) bad(p.gtin14, "raw vendor code rendered");
  // "A and B and C" is not English.
  if (/ and .* and /.test(p.comparison.claim))
    bad(p.gtin14, "claim joins names with repeated 'and': " + p.comparison.claim);

  // 2. staleness_exceeds_measured renders as a warning, never as an absence.
  for (const o of p.offers) {
    if (o.staleness_exceeds_measured) {
      if (!html.includes("not been measured"))
        bad(p.gtin14, o.chain + " is " + o.days_behind + "d old but no warning rendered");
      if (!html.includes(o.days_behind + " days old"))
        bad(p.gtin14, o.chain + " warning omits the age");
    }
    // and a measured figure must never be printed for an unmeasured offer
    if (o.staleness_exceeds_measured && o.staleness_pct != null)
      bad(p.gtin14, o.chain + " carries a figure it should not have");
  }

  // 3. No unqualified "cheapest" verdict where fewer than two chains were compared.
  if (n < 2) {
    if (/cheapest here/.test(html))
      bad(p.gtin14, "marked a cheapest with only " + n + " comparable");
    if (!/nothing to compare|Nothing to compare/i.test(html))
      bad(p.gtin14, "state " + n + " does not say there is nothing to compare");
  }
  if (n === 1 && !html.includes("does not mean"))
    bad(p.gtin14, "one-chain card does not defuse the cheapest reading");

  // 4. Every rendered price carries its observed date and its basis.
  for (const o of p.offers) {
    if (!html.includes(o.observed_date)) bad(p.gtin14, "missing observed_date for " + o.chain);
  }
  if (!html.includes(">" + p.basis + "<")) bad(p.gtin14, "basis tag missing");
}

// 5. No pooled staleness figure exists to leak. meta must carry staleness only per chain.
const metaFlat = JSON.stringify(meta);
if (!meta.chains || !meta.chains.every(c => Array.isArray(c.staleness)))
  bad("meta", "chains do not each carry their own staleness curve");
for (const k of Object.keys(meta))
  if (/stale/i.test(k)) bad("meta", "top-level staleness key present: " + k);

// 6. The landing state names the coverage before any search happens.
sandbox.renderCover({total: products.length, n0: counts[0], n1: counts[1],
                     n2: counts[2], n3: counts[3]});
const cover = nodes["#covbody"].innerHTML;
for (const need of ["national brands", "Toronto", "pickup", "cannot be compared",
                    "not possible", meta.extract_date]) {
  if (!cover.includes(need)) bad("cover", "landing state omits: " + need);
}
// The always-visible strip is STATIC HTML, not something the script writes. That is the
// point: the licence's attribution and the scope disclosures must not depend on a script
// having run. So they are asserted against the page source, which is a stronger check than
// asserting against whatever the script happened to render.
const strip = (html.match(/<div class="strip">[\s\S]*?<\/div><\/div>/) || [""])[0];
if (!strip) bad("strip", "no always-visible disclosure strip in the page source");
for (const need of ["ProjectHammer.org", "no basket", "no store ranking",
                    "national brands only", "Toronto"])
  if (!strip.includes(need)) bad("strip", "static strip omits: " + need);
// And the landing panel must state the scope before any data arrives, for the same reason.
const coverStatic = (html.match(/<div id="covbody"[\s\S]*?<\/div>/) || [""])[0];
for (const need of ["national-brand", "Store brands cannot be compared", "Toronto",
                    "not always possible"])
  if (!coverStatic.includes(need)) bad("cover", "static landing state omits: " + need);

console.log("products rendered : " + checked);
console.log("  3 chains        : " + counts[3]);
console.log("  2 chains        : " + counts[2]);
console.log("  1 chain         : " + counts[1] + "   (renders as 'nothing to compare')");
console.log("  0 chains        : " + counts[0] + "   (renders as 'nothing to compare')");
console.log("failures          : " + fail);
if (fail) { console.log("\nFAIL - the interface breaks a rule the extract enforces."); process.exit(1); }
console.log("\nOK - every product renders with its chains, dates, basis and staleness warnings.");

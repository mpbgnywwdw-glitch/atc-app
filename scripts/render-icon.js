// Renders Resources/AppIcon.svg to Resources/AppIcon.png (1024×1024, transparent corners).
// Usage: node scripts/render-icon.js [output.png]   (needs Playwright with Chromium)
const { chromium } = require("playwright");
const fs = require("node:fs");
const path = require("node:path");

(async () => {
  const root = path.join(__dirname, "..");
  const svg = fs.readFileSync(path.join(root, "Resources/AppIcon.svg"), "utf8");
  const out = process.argv[2] || path.join(root, "Resources/AppIcon.png");
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await page.locator("svg").screenshot({ path: out, omitBackground: true });
  await browser.close();
  console.log(`Wrote ${out}`);
})();

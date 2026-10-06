// Render an HTML file to PDF with headless Chromium (Playwright).
// usage: node render.js in.html out.pdf
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
(async () => {
  const [html, pdf] = process.argv.slice(2);
  // Always the same browser build, so that every document is laid out identically
  // (the full Chromium and the headless shell print with different metrics).
  const exe = process.env.CHROMIUM_PATH ||
    '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
  const browser = await chromium.launch(fs.existsSync(exe) ? { executablePath: exe, timeout: 180000 } : { timeout: 180000 });
  console.error('browser:', fs.existsSync(exe) ? exe : 'playwright default');
  const page = await browser.newPage();
  page.on('pageerror', e => console.error('pageerror:', e.message));
  page.on('console', m => { if (m.type() === 'error') console.error('console:', m.text()); });
  // Lay the page out at the printable width (A4 minus the margins below = 168 mm = 635 CSS px)
  // and report every element wider than that: Chromium would otherwise shrink the whole
  // document to fit the widest element, which silently changes the font size.
  await page.setViewportSize({ width: 635, height: 900 });
  await page.emulateMedia({ media: 'print' });
  await page.goto('file://' + path.resolve(html), { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(800);
  const wide = await page.evaluate(() => {
    const limit = document.documentElement.clientWidth + 1;
    const out = [];
    for (const el of document.querySelectorAll('.katex-display, table, pre, figure, img, p, li')) {
      const r = el.getBoundingClientRect();
      const sw = el.scrollWidth;
      if (r.right > limit || sw > limit) {
        out.push(el.tagName + (el.className ? '.' + String(el.className).split(' ')[0] : '') +
          ' right=' + Math.round(r.right) + ' scroll=' + sw + ' :: ' + (el.textContent || '').trim().slice(0, 90).replace(/\s+/g, ' '));
      }
    }
    return out;
  });
  if (wide.length) { console.error('OVERFLOW (' + wide.length + '):'); wide.forEach(w => console.error('  ' + w)); }
  else console.error('no overflow');
  const nerr = await page.evaluate(() => document.querySelectorAll('.katex-error').length);
  if (nerr > 0) console.error('katex errors:', nerr);
  await page.pdf({
    path: pdf, format: 'A4', printBackground: true,
    margin: { top: '20mm', bottom: '20mm', left: '21mm', right: '21mm' },
    displayHeaderFooter: true,
    headerTemplate: '<span></span>',
    footerTemplate: '<div style="font-size:9px; width:100%; text-align:center; font-family: Liberation Serif, serif; color:#333;"><span class="pageNumber"></span></div>'
  });
  await browser.close();
  console.log('wrote', pdf);
})();

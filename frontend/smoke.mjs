import { chromium } from 'playwright'

const baseUrl = process.env.CONTINUITY_URL ?? 'http://127.0.0.1:4173'
const browser = await chromium.launch({ headless: true })
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } })
const errors = []
page.on('console', (message) => {
  if (message.type() === 'error') errors.push(message.text())
})
page.on('pageerror', (error) => errors.push(error.message))

try {
  await page.goto(baseUrl, { waitUntil: 'networkidle' })
  await page.getByRole('heading', { name: /Private application state should survive/i }).waitFor()
  await page.getByRole('button', { name: /VERIFY LIVE COSTON2 STATE/i }).click()
  await page.waitForFunction(() => {
    const text = document.querySelector('[role="status"]')?.textContent ?? ''
    return text.includes('LIVE STATE VERIFIED') || text.includes('LIVE CHECK NEEDS REVIEW')
  }, { timeout: 20000 })
  const liveStatus = await page.locator('[role="status"]').innerText()
  if (process.env.REQUIRE_STATE_SERVICE === '1') {
    if (!liveStatus.includes('indexed state service')) throw new Error(`expected indexed state service, got: ${liveStatus}`)
  }
  await page.getByRole('button', { name: /OPEN VERIFIED RECOVERY/i }).click()
  await page.waitForFunction(() => window.scrollY > 0, { timeout: 2000 })
  await page.getByRole('button', { name: /INSPECT STALE REJECTION/i }).click()
  await page.getByRole('heading', { name: /Stale restore/i }).waitFor()
  await page.getByRole('button', { name: /Close evidence/i }).click()

  const favicon = await page.request.get(new URL('/favicon.svg', baseUrl).href)
  if (!favicon.ok()) throw new Error(`favicon request failed with ${favicon.status()}`)
  if (errors.length) throw new Error(`browser console errors: ${errors.join(' | ')}`)
  console.log(`frontend smoke passed: ${baseUrl}`)
} finally {
  await browser.close()
}

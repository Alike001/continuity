#!/usr/bin/env node
import { timingSafeEqual } from 'node:crypto'
import { createServer } from 'node:http'
import { execFile } from 'node:child_process'
import { mkdir, readFile, readdir, rename, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { promisify } from 'node:util'

const execFileAsync = promisify(execFile)

export const DEFAULTS = {
  port: Number(process.env.CONTINUITY_ORCHESTRATOR_PORT ?? 8791),
  dataDir: process.env.CONTINUITY_ORCHESTRATOR_DATA_DIR ?? '.fcc-work/orchestrator',
  operatorToken: process.env.CONTINUITY_OPERATOR_TOKEN ?? '',
  controller: process.env.CONTINUITY_CONTROLLER ?? '0x50D2871f491EC42F2a4fB5198308Dcf9A5c532fC',
  rpcUrl: process.env.CONTINUITY_RPC_URL ?? 'https://coston2-api.flare.network/ext/bc/C/rpc',
  privateKey: process.env.CONTINUITY_EXECUTOR_PRIVATE_KEY ?? '',
  execute: process.env.CONTINUITY_ORCHESTRATOR_EXECUTE === '1' && process.env.CONTINUITY_EXECUTION_CONFIRMATION === 'I_UNDERSTAND',
  snapshotStoreUrl: process.env.CONTINUITY_SNAPSHOT_STORE_URL ?? '',
  reconcileMs: Number(process.env.CONTINUITY_ORCHESTRATOR_RECONCILE_MS ?? 15000),
}

const hashPattern = /^0x[0-9a-fA-F]{64}$/
const hexPattern = /^0x(?:[0-9a-fA-F]{2})*$/

function assertJob(input) {
  if (!input || typeof input !== 'object') throw new Error('JSON object required')
  if (!hashPattern.test(input.actionId)) throw new Error('actionId must be a 32-byte 0x-prefixed hash')
  if (!hexPattern.test(input.resultData) || input.resultData === '0x') throw new Error('resultData must be non-empty hex bytes')
  if (!hexPattern.test(input.signature) || input.signature === '0x') throw new Error('signature must be non-empty hex bytes')
  if (typeof input.submissionTag !== 'string' || input.submissionTag.length > 64) throw new Error('submissionTag must be at most 64 characters')
  if (!Number.isInteger(input.status) || ![0, 1].includes(input.status)) throw new Error('status must be 0 or 1')
  if (input.ciphertextDigest !== undefined && !hashPattern.test(input.ciphertextDigest)) throw new Error('ciphertextDigest must be a 32-byte hash')
  return { actionId: input.actionId.toLowerCase(), resultData: input.resultData, submissionTag: input.submissionTag, status: input.status, signature: input.signature, ciphertextDigest: input.ciphertextDigest?.toLowerCase() ?? null }
}

function jobPath(dataDir, actionId) { return join(dataDir, 'jobs', `${actionId.slice(2)}.json`) }

async function writeJob(path, job) {
  await mkdir(dirname(path), { recursive: true })
  const temp = `${path}.tmp`
  await writeFile(temp, `${JSON.stringify(job, null, 2)}\n`, { mode: 0o600 })
  await rename(temp, path)
}

export function createCastSender(config = DEFAULTS) {
  return async (job) => {
    if (!config.privateKey) throw new Error('executor key is not configured')
    const args = [config.controller, 'commitSnapshot(bytes,bytes32,string,uint8,bytes)', job.resultData, job.actionId, job.submissionTag, String(job.status), job.signature, '--rpc-url', config.rpcUrl, '--private-key', config.privateKey, '--json']
    const { stdout } = await execFileAsync(process.env.CAST_BIN ?? 'cast', ['send', ...args], { maxBuffer: 2 * 1024 * 1024 })
    const receipt = JSON.parse(stdout)
    return { txHash: receipt.transactionHash ?? receipt.transaction_hash ?? receipt.hash, receipt }
  }
}

export function createCastReceiptReader(config = DEFAULTS) {
  return async (txHash) => {
    try {
      const { stdout } = await execFileAsync(process.env.CAST_BIN ?? 'cast', ['receipt', txHash, '--rpc-url', config.rpcUrl, '--json'], { maxBuffer: 512 * 1024 })
      const receipt = JSON.parse(stdout)
      return { status: receipt.status }
    } catch {
      return null
    }
  }
}

async function defaultSnapshotChecker(config, digest) {
  if (!config.snapshotStoreUrl) throw new Error('snapshot store URL is required for execution')
  const response = await fetch(`${config.snapshotStoreUrl.replace(/\/$/, '')}/snapshots/${digest}`, { signal: AbortSignal.timeout(5000) })
  if (!response.ok) throw new Error(`snapshot store returned HTTP ${response.status}`)
}

export function createOrchestrator({ config = DEFAULTS, sender = createCastSender(config), receiptReader = createCastReceiptReader(config), snapshotChecker = (digest) => defaultSnapshotChecker(config, digest) } = {}) {
  const jobs = new Map()
  const load = async () => {
    try {
      for (const file of await readdir(join(config.dataDir, 'jobs'))) {
        if (file.endsWith('.json')) {
          const job = JSON.parse(await readFile(join(config.dataDir, 'jobs', file), 'utf8'))
          jobs.set(job.actionId, job)
        }
      }
    } catch { /* empty queue on first run */ }
  }
  const persist = (job) => writeJob(jobPath(config.dataDir, job.actionId), job)
  const enqueue = async (input) => {
    const payload = assertJob(input)
    const existing = jobs.get(payload.actionId)
    if (existing) {
      const same = existing.resultData === payload.resultData && existing.signature === payload.signature
      if (!same) throw Object.assign(new Error('actionId already has a different payload'), { statusCode: 409 })
      return existing
    }
    if (config.execute) {
      if (!payload.ciphertextDigest) throw new Error('ciphertextDigest is required for execution')
      await snapshotChecker(payload.ciphertextDigest)
    }
    const job = { ...payload, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), state: config.execute ? 'queued' : 'dry_run', txHash: null, error: null }
    jobs.set(job.actionId, job)
    await persist(job)
    if (config.execute) await run(job.actionId)
    return jobs.get(job.actionId)
  }
  const run = async (actionId) => {
    const job = jobs.get(actionId)
    if (!job) throw Object.assign(new Error('job not found'), { statusCode: 404 })
    if (job.state === 'succeeded') return job
    if (!config.execute) return job
    job.state = 'submitting'; job.error = null; job.updatedAt = new Date().toISOString(); await persist(job)
    try {
      const result = await sender(job)
      if (!result?.txHash) throw new Error('sender returned no transaction hash')
      if (result.receipt?.status !== undefined && !['0x1', '1', 1, true].includes(result.receipt.status)) throw new Error('transaction receipt reported failure')
      job.state = 'submitted'; job.txHash = result.txHash; job.receipt = result.receipt ?? null; job.updatedAt = new Date().toISOString(); await persist(job)
    } catch (cause) {
      job.state = 'failed'; job.error = cause instanceof Error ? cause.message : String(cause); job.updatedAt = new Date().toISOString(); await persist(job)
    }
    return job
  }
  const reconcile = async (actionId) => {
    const job = jobs.get(actionId)
    if (!job || job.state !== 'submitted' || !job.txHash) return job
    const receipt = await receiptReader(job.txHash)
    if (!receipt || receipt.status === undefined) return job
    job.receipt = receipt; job.updatedAt = new Date().toISOString()
    if (['0x1', '1', 1, true].includes(receipt.status)) {
      job.state = 'succeeded'; job.error = null
    } else {
      job.state = 'failed'; job.error = 'transaction receipt reported failure'
    }
    await persist(job)
    return job
  }
  const reconcileSubmitted = async () => { for (const job of jobs.values()) await reconcile(job.actionId) }
  return { load, enqueue, run, reconcile, reconcileSubmitted, get: (actionId) => jobs.get(actionId) ?? null, list: () => [...jobs.values()], config }
}

async function body(request) {
  const chunks = []
  let size = 0
  for await (const chunk of request) { size += chunk.length; if (size > 2 * 1024 * 1024) throw new Error('request body too large'); chunks.push(chunk) }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'))
}

function authorized(request, token) {
  const expected = Buffer.from(`Bearer ${token ?? ''}`)
  const actual = Buffer.from(request.headers.authorization ?? '')
  return Boolean(token) && expected.length === actual.length && timingSafeEqual(expected, actual)
}

export async function startOrchestrator({ orchestrator, port = DEFAULTS.port } = {}) {
  const server = createServer(async (request, response) => {
    response.setHeader('content-type', 'application/json; charset=utf-8')
    if (request.url === '/health' && request.method === 'GET') {
      response.end(JSON.stringify({ ok: true, execute: orchestrator.config.execute, jobs: orchestrator.list().length }))
      return
    }
    if (!authorized(request, orchestrator.config.operatorToken)) { response.statusCode = 401; response.end(JSON.stringify({ error: 'operator authorization required' })); return }
    try {
      if (request.url === '/jobs/commit-snapshot' && request.method === 'POST') {
        const job = await orchestrator.enqueue(await body(request))
        response.statusCode = job.state === 'failed' ? 502 : 202
        response.end(JSON.stringify(job))
        return
      }
      const match = request.url?.match(/^\/jobs\/(0x[0-9a-fA-F]{64})(\/run)?$/)
      if (match && request.method === 'GET') { const job = orchestrator.get(match[1].toLowerCase()); if (!job) { response.statusCode = 404; response.end(JSON.stringify({ error: 'job not found' })); return } response.end(JSON.stringify(job)); return }
      if (match && match[2] && request.method === 'POST') { response.end(JSON.stringify(await orchestrator.run(match[1].toLowerCase()))); return }
      response.statusCode = 404
      response.end(JSON.stringify({ error: 'not found' }))
    } catch (cause) {
      response.statusCode = cause.statusCode ?? 400
      response.end(JSON.stringify({ error: cause instanceof Error ? cause.message : String(cause) }))
    }
  })
  const timer = setInterval(() => orchestrator.reconcileSubmitted(), orchestrator.config.reconcileMs ?? 15000)
  timer.unref()
  server.on('close', () => clearInterval(timer))
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)))
}

if (import.meta.url === `file://${process.argv[1]}`) {
  if (!DEFAULTS.operatorToken) throw new Error('CONTINUITY_OPERATOR_TOKEN is required')
  const orchestrator = createOrchestrator()
  await orchestrator.load()
  await orchestrator.reconcileSubmitted()
  const server = await startOrchestrator({ orchestrator })
  console.log(`Continuity orchestrator listening on http://127.0.0.1:${DEFAULTS.port}`)
  console.log(`Execution enabled: ${DEFAULTS.execute}`)
  process.on('SIGINT', () => server.close(() => process.exit(0)))
}

import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createOrchestrator, startOrchestrator } from './orchestrator.mjs'

const payload = {
  actionId: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  resultData: '0x1234', submissionTag: 'threshold', status: 1,
  signature: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  ciphertextDigest: '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
}

test('orchestrator is durable and idempotent in dry-run mode', async () => {
  const dataDir = await mkdtemp(join(tmpdir(), 'continuity-orchestrator-'))
  const orchestrator = createOrchestrator({ config: { dataDir, operatorToken: 'secret', execute: false } })
  const first = await orchestrator.enqueue(payload)
  const second = await orchestrator.enqueue(payload)
  assert.equal(first.state, 'dry_run')
  assert.equal(second.actionId, first.actionId)
  assert.deepEqual(JSON.parse(await readFile(join(dataDir, 'jobs', `${payload.actionId.slice(2)}.json`), 'utf8')).actionId, payload.actionId)
  await rm(dataDir, { recursive: true, force: true })
})

test('orchestrator executes through an injected sender and exposes auth-protected job API', async () => {
  const dataDir = await mkdtemp(join(tmpdir(), 'continuity-orchestrator-'))
  let sent = 0
  const orchestrator = createOrchestrator({
    config: { dataDir, operatorToken: 'secret', execute: true },
    sender: async () => { sent += 1; return { txHash: '0x' + 'c'.repeat(64), receipt: { status: '0x1' } } },
    snapshotChecker: async () => {},
    receiptReader: async () => ({ status: '0x1' }),
  })
  const server = await startOrchestrator({ orchestrator, port: 0 })
  const url = `http://127.0.0.1:${server.address().port}`
  const unauthorized = await fetch(`${url}/jobs/commit-snapshot`, { method: 'POST', body: JSON.stringify(payload) })
  assert.equal(unauthorized.status, 401)
  const response = await fetch(`${url}/jobs/commit-snapshot`, { method: 'POST', headers: { authorization: 'Bearer secret', 'content-type': 'application/json' }, body: JSON.stringify(payload) })
  assert.equal(response.status, 202)
  const job = await response.json()
  assert.equal(job.state, 'submitted')
  assert.equal(sent, 1)
  await orchestrator.reconcile(payload.actionId)
  assert.equal(orchestrator.get(payload.actionId).state, 'succeeded')
  server.close()
  await rm(dataDir, { recursive: true, force: true })
})

test('orchestrator reconciles a submitted job after restart', async () => {
  const dataDir = await mkdtemp(join(tmpdir(), 'continuity-orchestrator-'))
  const config = { dataDir, operatorToken: 'secret', execute: true }
  const first = createOrchestrator({ config, snapshotChecker: async () => {}, sender: async () => ({ txHash: '0x' + 'e'.repeat(64) }) })
  await first.enqueue(payload)
  const restarted = createOrchestrator({ config, receiptReader: async () => ({ status: '0x1' }) })
  await restarted.load()
  await restarted.reconcileSubmitted()
  assert.equal(restarted.get(payload.actionId).state, 'succeeded')
  await rm(dataDir, { recursive: true, force: true })
})

test('orchestrator redacts executor keys from persisted failures', async () => {
  const dataDir = await mkdtemp(join(tmpdir(), 'continuity-orchestrator-'))
  const privateKey = 'private-executor-key'
  const orchestrator = createOrchestrator({
    config: { dataDir, operatorToken: 'secret', execute: true, privateKey },
    snapshotChecker: async () => {},
    sender: async () => { throw new Error(`cast failed with ${privateKey}`) },
  })
  const job = await orchestrator.enqueue(payload)
  assert.equal(job.state, 'failed')
  assert.equal(job.error.includes(privateKey), false)
  await rm(dataDir, { recursive: true, force: true })
})

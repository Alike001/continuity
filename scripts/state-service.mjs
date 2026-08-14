#!/usr/bin/env node
import { createServer } from 'node:http'
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'

export const DEFAULTS = {
  rpcUrl: process.env.CONTINUITY_RPC_URL ?? 'https://coston2-api.flare.network/ext/bc/C/rpc',
  controller: process.env.CONTINUITY_CONTROLLER ?? '0x50D2871f491EC42F2a4fB5198308Dcf9A5c532fC',
  manager: process.env.CONTINUITY_MANAGER ?? '0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE',
  cachePath: process.env.CONTINUITY_CACHE_PATH ?? '.fcc-work/indexer-state.json',
  eventsPath: process.env.CONTINUITY_EVENTS_PATH ?? '.fcc-work/indexer-events.json',
  fromBlock: process.env.CONTINUITY_FROM_BLOCK ?? '',
  lookbackBlocks: Number(process.env.CONTINUITY_LOOKBACK_BLOCKS ?? 10000),
  port: Number(process.env.CONTINUITY_PORT ?? 8787),
  pollMs: Number(process.env.CONTINUITY_POLL_MS ?? 15000),
}

const selector = {
  teeManager: '0xf665e5e7', latestEpoch: '0x9cb118bf', latestStateRoot: '0x991beafd', activeTee: '0x4fa11f55',
  recoveryTee: '0x116fdfc5', pendingSnapshotAction: '0x446723cd', pendingRecoveryAction: '0xfe52860b',
  recoveryArmed: '0x2807230a', getTeeMachineStatus: '0x25e30221',
}

const eventTopic = {
  SnapshotRequested: '0xedbc79e4eb3bba2739d41a8b10cbdbea29ef9c7aa8329710a7ffde5f11a76b3c',
  SnapshotCommitted: '0x333e2014e6dacd7c5cc740e6ffaaba73782b1a0f767a3dff4c4918bd123bdbec',
  RecoveryRequested: '0xe7fb37d2f1adfa87a7cff3658bdee5d3a41e1e9d305ec47ed2b55c7dd7b21f2a',
  RecoveryArmed: '0x1b9be30b2cc86c0426bf70bb14dacbbfdcb2810d6fde543a18ee193fab273efd',
  RecoveryActivated: '0x2723c0a345b5f2b3e394d13914aa55dfcff33fdca533dc5aec5afa24d640d20a',
  SnapshotFailed: '0xb3147f467a8130fa23be5447cfd1403030f3531a9248107ff9565250a048fed7',
  RecoveryFailed: '0x62af832c7853e1a07ab30c9cfd5321d6c29940e9aa29bf792d320bce9ea53a5f',
}

function decodeWord(value) { return value.slice(-64) }
function decodeAddress(value) { return `0x${value.slice(-40)}` }
function addressArg(value) { return value.toLowerCase().replace(/^0x/, '').padStart(64, '0') }

export async function readLiveState(rpc, config = DEFAULTS) {
  const callController = (data) => rpc('eth_call', [{ to: config.controller, data }, 'latest'])
  const [chainId, blockNumber, code, manager, epoch, root, active, recovery, pendingSnapshot, pendingRecovery, armed] = await Promise.all([
    rpc('eth_chainId', []), rpc('eth_blockNumber', []), rpc('eth_getCode', [config.controller, 'latest']), callController(selector.teeManager),
    callController(selector.latestEpoch), callController(selector.latestStateRoot), callController(selector.activeTee), callController(selector.recoveryTee),
    callController(selector.pendingSnapshotAction), callController(selector.pendingRecoveryAction), callController(selector.recoveryArmed),
  ])
  const activeTee = decodeAddress(active)
  const recoveryTee = decodeAddress(recovery)
  const managerAddress = decodeAddress(manager)
  const callManager = (data) => rpc('eth_call', [{ to: managerAddress, data }, 'latest'])
  const [activeStatus, recoveryStatus] = await Promise.all([
    callManager(`${selector.getTeeMachineStatus}${addressArg(activeTee)}`),
    callManager(`${selector.getTeeMachineStatus}${addressArg(recoveryTee)}`),
  ])
  return {
    source: 'coston2-rpc', observedAt: new Date().toISOString(), blockNumber,
    chainId: Number.parseInt(chainId, 16), controller: config.controller, manager: managerAddress,
    controllerCode: code !== '0x', epoch: Number.parseInt(decodeWord(epoch), 16), stateRoot: root,
    activeTee, recoveryTee, pendingSnapshotAction: pendingSnapshot, pendingRecoveryAction: pendingRecovery,
    recoveryArmed: Number.parseInt(decodeWord(armed), 16) !== 0,
    machineStatus: { active: Number.parseInt(decodeWord(activeStatus), 16), recovery: Number.parseInt(decodeWord(recoveryStatus), 16) },
  }
}

function dataWords(data) {
  const clean = data.replace(/^0x/, '')
  const words = []
  for (let index = 0; index + 64 <= clean.length; index += 64) words.push(`0x${clean.slice(index, index + 64)}`)
  return words
}

function topicAddress(value) { return decodeAddress(value) }
function topicUint(value) { return Number.parseInt(decodeWord(value), 16) }

export async function readEvents(rpc, config = DEFAULTS, fromBlock, toBlock) {
  const start = Number.parseInt(fromBlock, 16)
  const end = Number.parseInt(toBlock, 16)
  const logs = []
  for (let cursor = start; cursor <= end; cursor += 30) {
    const chunkEnd = Math.min(cursor + 29, end)
    const chunk = await rpc('eth_getLogs', [{ address: config.controller, fromBlock: `0x${cursor.toString(16)}`, toBlock: `0x${chunkEnd.toString(16)}` }])
    logs.push(...chunk)
  }
  return logs.map((log) => {
    const name = Object.entries(eventTopic).find(([, topic]) => topic.toLowerCase() === log.topics[0].toLowerCase())?.[0] ?? 'Unknown'
    const words = dataWords(log.data)
    const topics = log.topics
    let args = {}
    if (name === 'SnapshotRequested') args = { actionId: topics[1], nonce: topicUint(topics[2]), epoch: topicUint(topics[3]), sourceTee: topicAddress(words[0]), recoveryTee: topicAddress(words[1]), parentRoot: words[2] }
    if (name === 'SnapshotCommitted') args = { actionId: topics[1], epoch: topicUint(topics[2]), stateRoot: topics[3], parentRoot: words[0], ciphertextDigest: words[1], sourceTee: topicAddress(words[2]), recoveryTee: topicAddress(words[3]) }
    if (name === 'RecoveryRequested') args = { actionId: topics[1], recoveryTee: topicAddress(topics[2]), epoch: topicUint(topics[3]), stateRoot: words[0], ciphertextDigest: words[1] }
    if (name === 'RecoveryArmed') args = { actionId: topics[1], recoveryTee: topicAddress(topics[2]), epoch: topicUint(words[0]), stateRoot: words[1] }
    if (name === 'RecoveryActivated') args = { previousTee: topicAddress(topics[1]), activeTee: topicAddress(topics[2]), epoch: topicUint(words[0]), stateRoot: words[1] }
    if (name === 'SnapshotFailed') args = { actionId: topics[1], sourceTee: topicAddress(topics[2]), nonce: topicUint(topics[3]) }
    if (name === 'RecoveryFailed') args = { actionId: topics[1], recoveryTee: topicAddress(topics[2]), epoch: topicUint(topics[3]) }
    return { name, blockNumber: log.blockNumber, transactionHash: log.transactionHash, logIndex: log.logIndex, args }
  }).filter((event) => event.name !== 'Unknown')
}

export function createRpc(rpcUrl = DEFAULTS.rpcUrl) {
  let queue = Promise.resolve()
  const request = async (method, params) => {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const response = await fetch(rpcUrl, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: Date.now(), method, params }) })
      if (response.status === 429 && attempt < 2) {
        await new Promise((resolve) => setTimeout(resolve, 400 * (attempt + 1)))
        continue
      }
      if (!response.ok) throw new Error(`RPC HTTP ${response.status}`)
      const body = await response.json()
      if (body.error) throw new Error(body.error.message || 'RPC rejected the request')
      return body.result
    }
    throw new Error('RPC retry loop ended unexpectedly')
  }
  return (method, params) => {
    const next = queue.then(() => request(method, params))
    queue = next.catch(() => undefined)
    return next
  }
}

export function createStateStore({ rpc, config = DEFAULTS, cachePath = config.cachePath, eventsPath = config.eventsPath } = {}) {
  let state = null
  let events = []
  let indexedThrough = null
  let error = null
  let refreshing = false
  return {
    get() { return { state, events, indexedThrough, error, refreshing } },
    async load() {
      try { state = JSON.parse(await readFile(cachePath, 'utf8')); state.cached = true } catch { /* first run has no cache */ }
      try { const cachedEvents = JSON.parse(await readFile(eventsPath, 'utf8')); events = cachedEvents.events ?? []; indexedThrough = cachedEvents.indexedThrough ?? null } catch { /* first run has no event cache */ }
      return state
    },
    async refresh() {
      if (refreshing) return state
      refreshing = true
      try {
        const next = await readLiveState(rpc, config)
        const tempPath = `${cachePath}.tmp`
        await mkdir(dirname(cachePath), { recursive: true })
        await writeFile(tempPath, `${JSON.stringify(next, null, 2)}\n`, 'utf8')
        await rename(tempPath, cachePath)
        state = next
        const latestBlock = Number.parseInt(next.blockNumber, 16)
        const startBlock = indexedThrough ? indexedThrough + 1 : config.fromBlock ? Number.parseInt(config.fromBlock, 16) : Math.max(0, latestBlock - config.lookbackBlocks)
        if (startBlock <= latestBlock) {
          const newEvents = await readEvents(rpc, config, `0x${startBlock.toString(16)}`, next.blockNumber)
          const seen = new Set(events.map((event) => `${event.transactionHash}:${event.logIndex}`))
          events = [...events, ...newEvents.filter((event) => !seen.has(`${event.transactionHash}:${event.logIndex}`))].sort((a, b) => Number.parseInt(a.blockNumber, 16) - Number.parseInt(b.blockNumber, 16))
          indexedThrough = latestBlock
          const eventsTempPath = `${eventsPath}.tmp`
          await writeFile(eventsTempPath, `${JSON.stringify({ indexedThrough, events }, null, 2)}\n`, 'utf8')
          await rename(eventsTempPath, eventsPath)
        }
        error = null
      } catch (cause) {
        error = cause instanceof Error ? cause.message : String(cause)
      } finally { refreshing = false }
      return state
    },
  }
}

export function startServer({ store, port = DEFAULTS.port, pollMs = DEFAULTS.pollMs } = {}) {
  const server = createServer(async (request, response) => {
    response.setHeader('access-control-allow-origin', '*')
    response.setHeader('content-type', 'application/json; charset=utf-8')
    if (request.url === '/health') {
      const current = store.get()
      response.end(JSON.stringify({ ok: Boolean(current.state), stale: Boolean(current.error), error: current.error }))
      return
    }
    if (request.url === '/api/state') {
      const current = store.get()
      response.end(JSON.stringify({ state: current.state, stale: Boolean(current.error), error: current.error, refreshing: current.refreshing }))
      return
    }
    if (request.url === '/api/events') {
      const current = store.get()
      response.end(JSON.stringify({ events: current.events, indexedThrough: current.indexedThrough, stale: Boolean(current.error), error: current.error, refreshing: current.refreshing }))
      return
    }
    response.statusCode = 404
    response.end(JSON.stringify({ error: 'not found' }))
  })
  const timer = setInterval(() => store.refresh(), pollMs)
  timer.unref()
  server.on('close', () => clearInterval(timer))
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)))
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const config = DEFAULTS
  const store = createStateStore({ rpc: createRpc(config.rpcUrl), config, cachePath: config.cachePath, eventsPath: config.eventsPath })
  await store.load()
  await store.refresh()
  const server = await startServer({ store, port: config.port, pollMs: config.pollMs })
  console.log(`Continuity state service listening on http://127.0.0.1:${config.port}`)
  console.log(`RPC source: ${config.rpcUrl}`)
  process.on('SIGINT', () => server.close(() => process.exit(0)))
}

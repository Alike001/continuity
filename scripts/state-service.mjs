#!/usr/bin/env node
import { createServer } from 'node:http'
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'

export const DEFAULTS = {
  rpcUrl: process.env.CONTINUITY_RPC_URL ?? 'https://coston2-api.flare.network/ext/bc/C/rpc',
  controller: process.env.CONTINUITY_CONTROLLER ?? '0x50D2871f491EC42F2a4fB5198308Dcf9A5c532fC',
  manager: process.env.CONTINUITY_MANAGER ?? '0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE',
  cachePath: process.env.CONTINUITY_CACHE_PATH ?? '.fcc-work/indexer-state.json',
  port: Number(process.env.CONTINUITY_PORT ?? 8787),
  pollMs: Number(process.env.CONTINUITY_POLL_MS ?? 15000),
}

const selector = {
  teeManager: '0xf665e5e7', latestEpoch: '0x9cb118bf', latestStateRoot: '0x991beafd', activeTee: '0x4fa11f55',
  recoveryTee: '0x116fdfc5', pendingSnapshotAction: '0x446723cd', pendingRecoveryAction: '0xfe52860b',
  recoveryArmed: '0x2807230a', getTeeMachineStatus: '0x25e30221',
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

export function createRpc(rpcUrl = DEFAULTS.rpcUrl) {
  return async (method, params) => {
    const response = await fetch(rpcUrl, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: Date.now(), method, params }) })
    if (!response.ok) throw new Error(`RPC HTTP ${response.status}`)
    const body = await response.json()
    if (body.error) throw new Error(body.error.message || 'RPC rejected the request')
    return body.result
  }
}

export function createStateStore({ rpc, cachePath = DEFAULTS.cachePath } = {}) {
  let state = null
  let error = null
  let refreshing = false
  return {
    get() { return { state, error, refreshing } },
    async load() {
      try { state = JSON.parse(await readFile(cachePath, 'utf8')); state.cached = true } catch { /* first run has no cache */ }
      return state
    },
    async refresh() {
      if (refreshing) return state
      refreshing = true
      try {
        const next = await readLiveState(rpc)
        const tempPath = `${cachePath}.tmp`
        await mkdir(dirname(cachePath), { recursive: true })
        await writeFile(tempPath, `${JSON.stringify(next, null, 2)}\n`, 'utf8')
        await rename(tempPath, cachePath)
        state = next
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
  const store = createStateStore({ rpc: createRpc(config.rpcUrl), cachePath: config.cachePath })
  await store.load()
  await store.refresh()
  const server = await startServer({ store, port: config.port, pollMs: config.pollMs })
  console.log(`Continuity state service listening on http://127.0.0.1:${config.port}`)
  console.log(`RPC source: ${config.rpcUrl}`)
  process.on('SIGINT', () => server.close(() => process.exit(0)))
}

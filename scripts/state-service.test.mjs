import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createStateStore, readEvents, startServer } from './state-service.mjs'

const controller = '0x50D2871f491EC42F2a4fB5198308Dcf9A5c532fC'
const manager = '0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE'
const active = '0x693535e87de176f4019bb790e45bd85c27192b3a'
const recovery = '0xe1f73e51c4b8ddbef6131f4bd3839c85cff9b3c6'
const root = '0xf0ad19af3ddec5b11da7ce52edae3500b90ad258465fdb3efb3374521ef9b379'
const word = (value) => `0x${value.replace(/^0x/, '').padStart(64, '0')}`
const addressWord = (value) => word(value)

function fakeRpc(method, params) {
  if (method === 'eth_getLogs') return Promise.resolve([])
  if (method === 'eth_chainId') return Promise.resolve('0x72')
  if (method === 'eth_blockNumber') return Promise.resolve('0x1234')
  if (method === 'eth_getCode') return Promise.resolve('0x6000')
  const data = params[0].data
  const calls = new Map([
    ['0xf665e5e7', addressWord(manager)], ['0x9cb118bf', word('2')], ['0x991beafd', root], ['0x4fa11f55', addressWord(active)],
    ['0x116fdfc5', addressWord(recovery)], ['0x446723cd', word('0')], ['0xfe52860b', word('0')], ['0x2807230a', word('0')],
  ])
  if (data.startsWith('0x25e30221')) return Promise.resolve(word('2'))
  return Promise.resolve(calls.get(data) ?? calls.get(data.slice(0, 10)))
}

test('state service reads and caches verified Coston2 state', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'continuity-state-'))
  const cachePath = join(directory, 'state.json')
  const store = createStateStore({ rpc: fakeRpc, cachePath })
  await store.refresh()
  const current = store.get()
  assert.equal(current.state.chainId, 114)
  assert.equal(current.state.epoch, 2)
  assert.equal(current.state.stateRoot, root)
  assert.equal(current.state.machineStatus.active, 2)
  assert.equal(JSON.parse(await readFile(cachePath, 'utf8')).controller, controller)
  await rm(directory, { recursive: true, force: true })
})

test('state service exposes health and cached state endpoints', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'continuity-state-'))
  const store = createStateStore({ rpc: fakeRpc, cachePath: join(directory, 'state.json') })
  await store.refresh()
  const server = await startServer({ store, port: 0, pollMs: 60_000 })
  const port = server.address().port
  const health = await (await fetch(`http://127.0.0.1:${port}/health`)).json()
  const response = await (await fetch(`http://127.0.0.1:${port}/api/state`)).json()
  assert.equal(health.ok, true)
  assert.equal(response.state.epoch, 2)
  server.close()
  await rm(directory, { recursive: true, force: true })
})

test('event indexer decodes committed lineage events', async () => {
  const action = word('a'.repeat(64))
  const epoch = word('2')
  const stateRoot = word('b'.repeat(64))
  const parentRoot = word('c'.repeat(64))
  const digest = word('d'.repeat(64))
  const log = {
    blockNumber: '0x20', logIndex: '0x1', transactionHash: '0xtx',
    topics: ['0x333e2014e6dacd7c5cc740e6ffaaba73782b1a0f767a3dff4c4918bd123bdbec', action, epoch, stateRoot],
    data: `${parentRoot.slice(2)}${digest.slice(2)}${addressWord(active).slice(2)}${addressWord(recovery).slice(2)}`,
  }
  const events = await readEvents(async () => [log], { controller }, '0x20', '0x20')
  assert.deepEqual(events[0].args, { actionId: action, epoch: 2, stateRoot, parentRoot, ciphertextDigest: digest, sourceTee: active, recoveryTee: recovery })
})

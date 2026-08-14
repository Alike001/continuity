import { StrictMode, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const evidence = {
  rpcUrl: 'https://coston2-api.flare.network/ext/bc/C/rpc',
  stateServiceUrl: import.meta.env.VITE_STATE_SERVICE_URL ?? 'http://127.0.0.1:8787',
  controller: '0x50D2871f491EC42F2a4fB5198308Dcf9A5c532fC',
  snapshotRequestTx: '0xa6336fdc8d80b6465ec02e1b3cbbe5826a34164f0806b34c1dae37be8d60ebd3',
  snapshotCommitTx: '0xe911f8884151c62d2dc8f2a0dacc3057191a32c6bc60b6d21962f1e401f59a51',
  recoveryRequestTx: '0x74244ecfe77d76bb1adba2c4d264932691c4e2ce8890afcc9c4b86f2ccd53c3c',
  activationTx: '0xfd10d1e98cadd4448264a682503142eb1fe87ce31741d7d583a72821570d12e6',
  continuationCommitTx: '0x2b829d7688596bfe7fcfb2cf38355afe421834a29433e47253bc8cb19c5432c3',
  epoch3SnapshotCommitTx: '0x9fd3d2567d4346fea0591b774316625c65212815161160f48d75905c83de141a',
  terminalErrorRequestTx: '0xf297b23bfbf2c4071dc5823c02d10ed93c01ced85b5fceb73e20d5c93d21cdbb',
  terminalErrorClearTx: '0x1b5c70376e7dc9b1887c0ef479a47f7571a21c6322da45ea25229a63ec6ba94b',
  root: '0xb31b7f24e96aa72c1dc92aa31a61f32f9d2d73dcebf09414bb4f953d186e629e',
  epoch: '03',
  extension: '66240',
  appId: '0x569f078a46d54c8228d4a986d2c421f1504a6456bb83d125982b0bfeb5d90b8c',
  primary: '0xe1f73e51c4b8ddbef6131f4bd3839c85cff9b3c6',
  recovery: '0x693535e87de176f4019bb790e45bd85c27192b3a',
  active: '0x693535e87de176f4019bb790e45bd85c27192b3a',
  recoveryFinal: '0xe1f73e51c4b8ddbef6131f4bd3839c85cff9b3c6',
}

const stages = [
  ['01', 'ANCHOR', 'Coston2', 'The registry is the source of truth.'],
  ['02', 'SNAPSHOT', 'Epoch 01', 'Primary TEE signed the sealed journal.'],
  ['03', 'IDENTITY', 'Approved code', 'App and code hash remain bound.'],
  ['04', 'HISTORY', 'Root accepted', 'The last committed state is recoverable.'],
  ['05', 'RESTORE', 'Recovery TEE', 'Encrypted state was restored into the standby.'],
  ['06', 'CONFIRM', 'Activation', 'Fresh availability proof completed the handoff.'],
  ['07', 'CONTINUE', 'Epoch 03 committed', 'The recovered journal accepted a new encrypted entry.'],
]

function App() {
  const [runState, setRunState] = useState('complete')
  const [activeStage, setActiveStage] = useState(7)
  const [inspector, setInspector] = useState(null)
  const [rejection, setRejection] = useState(null)
  const [liveCheck, setLiveCheck] = useState({ state: 'idle', message: '' })

  const openRecordedRecovery = () => {
    setRunState('complete')
    setActiveStage(7)
  }

  const inspectRejection = (kind) => {
    setRejection(kind)
    setInspector(kind === 'stale' ? 'stale' : 'fork')
  }

  const verifyLive = async () => {
    setLiveCheck({ state: 'loading', message: 'Reading controller and FCC manager state…' })
    try {
      let checks
      let source
      try {
        const serviceSnapshot = await readServiceSnapshot()
        checks = checksFromState(serviceSnapshot.state)
        source = `indexed state service, ${serviceSnapshot.events.length} controller events indexed`
      } catch {
        checks = await readLiveState()
        source = 'direct Coston2 RPC fallback'
      }
      const failed = checks.filter((check) => !check.ok)
      setLiveCheck({
        state: failed.length ? 'fail' : 'pass',
        message: failed.length ? failed.map((check) => check.label).join(', ') : `Coston2 state matches the recorded epoch-03 acceptance via ${source}.`,
      })
    } catch (error) {
      setLiveCheck({ state: 'fail', message: error instanceof Error ? error.message : 'Live verification failed.' })
    }
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="wordmark" href="#top" aria-label="Continuity home">CONTINUITY<span className="wordmark-mark">/</span></a>
        <div className="topbar-meta"><span className="env-dot" /> COSTON2 <span className="meta-separator">/</span> SIMULATED TEE <span className="meta-separator">/</span> RECORDED EVIDENCE</div>
        <button className="text-button" onClick={() => setInspector('summary')}>OPEN EVIDENCE <span aria-hidden="true">↗</span></button>
      </header>

      <main id="top">
        <section className="intro section-rule">
          <div className="eyebrow">FCC / STATEFUL EXTENSION RECOVERY</div>
          <div className="environment-line"><span className="env-dot" /> COSTON2 <span>/</span> SIMULATED TEE <span>/</span> RECORDED REAL EVIDENCE <button className="disclosure-button" onClick={() => setInspector('disclosure')}>WHAT THIS PROVES ↗</button></div>
          <h1>Private application state should survive the enclave that created it.</h1>
          <p className="lede">Continuity restores the latest verified state from a failed Confidential Compute machine to an approved replacement, with every handoff anchored on Flare.</p>
        </section>

        <section className="identity-bar section-rule" aria-label="Application identity">
          <IdentityCell label="APPLICATION" value={shorten(evidence.appId)} />
          <IdentityCell label="EXTENSION" value={evidence.extension} />
          <IdentityCell label="PRIMARY TEE" value={shorten(evidence.primary)} status="STOPPED / STANDBY" tone="muted" />
          <IdentityCell label="RECOVERY TEE" value={shorten(evidence.recovery)} status="ACTIVE / VERIFIED" tone="accent" />
        </section>

        <section className="readiness section-rule">
          <div className="readiness-copy">
            <div className="eyebrow">RECOVERY READINESS <span className="live-badge">● RECORDED LIVE EVIDENCE</span></div>
            <h2>{runState === 'complete' ? 'Recovery verified and continued at epoch 03.' : 'The latest state is ready to inspect.'}</h2>
            <p>The primary stopped after its encrypted snapshot was committed. The replacement restored the exact accepted root, became active through a fresh FCC availability proof, and accepted a new journal entry.</p>
          </div>
          <div className="readiness-action">
            <div className="anchor-summary"><div><span className="eyebrow">LATEST ANCHORED STATE</span><strong>EPOCH {evidence.epoch}</strong></div><div className="root-value"><span className="eyebrow">STATE ROOT</span><button className="machine-value" onClick={() => setInspector('raw')}>{shorten(evidence.root)} <span aria-hidden="true">↗</span></button></div></div>
            <button className="primary-action" onClick={openRecordedRecovery} aria-describedby="recorded-note">
              {runState === 'complete' ? 'OPEN VERIFIED RECOVERY' : 'OPEN RECORDED RECOVERY'} <span aria-hidden="true">→</span>
            </button>
            <span id="recorded-note" className="action-note">Recorded Coston2 evidence mode. This control opens the verified run and sends no wallet transaction.</span>
            <button className="secondary-action live-check-button" onClick={verifyLive} disabled={liveCheck.state === 'loading'}>
              {liveCheck.state === 'loading' ? 'VERIFYING COSTON2…' : 'VERIFY LIVE COSTON2 STATE'} <span aria-hidden="true">↗</span>
            </button>
            {liveCheck.state !== 'idle' && <div className={`live-check ${liveCheck.state}`} role="status"><strong>{liveCheck.state === 'pass' ? 'LIVE STATE VERIFIED' : liveCheck.state === 'loading' ? 'LIVE CHECK IN PROGRESS' : 'LIVE CHECK NEEDS REVIEW'}</strong><span>{liveCheck.message}</span></div>}
          </div>
        </section>

        <section className="runbook section-rule">
          <div className="section-heading"><div><div className="eyebrow">THE RUNBOOK</div><h2>One state. One accepted path.</h2></div><span className="mono-caption">EPOCH {evidence.epoch} / ROOT {shorten(evidence.root)}</span></div>
          <div className="ledger" role="list" aria-label="Recorded recovery stages">
            {stages.map(([number, label, value, detail], index) => {
              const isDone = index < activeStage
              const isActive = index === activeStage
              return <button className={`ledger-row ${isActive ? 'is-active' : ''} ${isDone ? 'is-done' : ''}`} key={label} onClick={() => setActiveStage(index)} role="listitem" aria-current={isActive ? 'step' : undefined}>
                <span className="ledger-number">{number}</span><span className="ledger-label">{label}</span><span className="ledger-value">{value}</span><span className="ledger-detail">{isActive || isDone ? detail : 'Awaiting the next verified state.'}</span><span className="ledger-state">{isDone ? 'PASS' : isActive ? 'CURRENT' : '—'}</span>
              </button>
            })}
          </div>
          <div className="continuation-note"><span className="pending-mark">✓</span><span><strong>CONTINUE is verified.</strong> The recovered journal accepted a new encrypted entry and advanced the lineage to epoch 03.</span></div>
        </section>

        <section className="evidence section-rule">
          <div className="section-heading"><div><div className="eyebrow">EVIDENCE INSPECTOR</div><h2>Nothing important is hidden behind the interface.</h2></div><button className="text-button" onClick={() => setInspector('signed')}>INSPECT ALL <span aria-hidden="true">↗</span></button></div>
          <div className="evidence-grid">
            <EvidenceCard label="SIGNED RESULT" value="Primary snapshot" detail="Status 1 · log ok" onClick={() => setInspector('signed')} />
            <EvidenceCard label="CONTRACT" value="Activation" detail={shorten(evidence.activationTx)} onClick={() => setInspector('contract')} />
            <EvidenceCard label="STATE ROOT" value={shorten(evidence.root)} detail="Accepted at epoch 03" onClick={() => setInspector('raw')} />
            <EvidenceCard label="FCC FAILURE" value="Terminal error" detail="Status 0 · cleared" onClick={() => setInspector('terminal')} />
          </div>
        </section>

        <section className="adversarial section-rule">
          <div className="eyebrow">ADVERSARIAL CHECKS</div>
          <div className="adversarial-grid">
            <div><h2>Recovery only succeeds when the history agrees.</h2><p>A real FCC-signed terminal error was cleared without changing the accepted lineage. Stale and competing-branch checks remain deterministic controller-test evidence.</p></div>
            <div className="test-actions"><TestButton label="INSPECT FCC FAILURE" onClick={() => setInspector('terminal')} /><TestButton label="INSPECT STALE REJECTION" onClick={() => inspectRejection('stale')} /><TestButton label="INSPECT FORK REJECTION" onClick={() => inspectRejection('fork')} /></div>
          </div>
          {rejection && <div className="rejection"><span className="rejection-mark">×</span><span><strong>REJECTED IN CONTROLLER TEST</strong> / {rejection === 'stale' ? 'STALE RESTORE' : 'COMPETING BRANCH'}<small>{rejection === 'stale' ? 'Older epoch is rejected before it can replace the accepted root.' : 'A second branch extending the consumed parent is rejected.'} Live receipt pending.</small></span></div>}
        </section>
      </main>

      <footer className="footer"><span>CONTINUITY / FLARE CONFIDENTIAL COMPUTE</span><span>SIMULATED TEE: FCC INTEGRATION VERIFIED. HARDWARE CONFIDENTIALITY IS NOT ACTIVE.</span></footer>

      {inspector && <Inspector tab={inspector} close={() => setInspector(null)} />}
    </div>
  )
}

function shorten(value) { return `${value.slice(0, 10)}…${value.slice(-8)}` }
const selectors = {
  latestEpoch: '0x9cb118bf', latestStateRoot: '0x991beafd', activeTee: '0x4fa11f55', recoveryTee: '0x116fdfc5',
  pendingSnapshotAction: '0x446723cd', pendingRecoveryAction: '0xfe52860b', recoveryArmed: '0x2807230a',
  teeManager: '0xf665e5e7', getTeeMachineStatus: '0x25e30221',
}

async function rpc(method, params) {
  const response = await fetch(evidence.rpcUrl, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: Date.now(), method, params }) })
  if (!response.ok) throw new Error(`Coston2 RPC returned HTTP ${response.status}.`)
  const body = await response.json()
  if (body.error) throw new Error(body.error.message || 'Coston2 RPC rejected the read.')
  return body.result
}

async function callView(selector, args = '') {
  return rpc('eth_call', [{ to: evidence.controller, data: `${selector}${args}` }, 'latest'])
}

async function callAt(to, selector, args = '') {
  return rpc('eth_call', [{ to, data: `${selector}${args}` }, 'latest'])
}

function addressArg(address) { return address.toLowerCase().replace(/^0x/, '').padStart(64, '0') }
function decodeAddress(value) { return `0x${value.slice(-40)}` }
function decodeWord(value) { return value.slice(-64) }

async function readServiceSnapshot() {
  const [stateResponse, eventsResponse] = await Promise.all([fetch(`${evidence.stateServiceUrl}/api/state`), fetch(`${evidence.stateServiceUrl}/api/events`)])
  if (!stateResponse.ok || !eventsResponse.ok) throw new Error(`State service returned HTTP ${stateResponse.ok ? eventsResponse.status : stateResponse.status}.`)
  const [stateBody, eventsBody] = await Promise.all([stateResponse.json(), eventsResponse.json()])
  if (stateBody.stale || eventsBody.stale || !stateBody.state) throw new Error(stateBody.error || eventsBody.error || 'State service has no fresh state.')
  return { state: stateBody.state, events: eventsBody.events ?? [], indexedThrough: eventsBody.indexedThrough }
}

function checksFromState(state) {
  return [
    { label: 'chain ID', ok: state.chainId === 114 },
    { label: 'controller code', ok: state.controllerCode === true },
    { label: 'epoch 03', ok: state.epoch === 3 },
    { label: 'state root', ok: state.stateRoot.toLowerCase() === evidence.root.toLowerCase() },
    { label: 'active TEE', ok: state.activeTee.toLowerCase() === evidence.active.toLowerCase() },
    { label: 'recovery TEE', ok: state.recoveryTee.toLowerCase() === evidence.recoveryFinal.toLowerCase() },
    { label: 'no pending action', ok: /^0x0+$/.test(state.pendingSnapshotAction) && /^0x0+$/.test(state.pendingRecoveryAction) },
    { label: 'recovery unarmed', ok: state.recoveryArmed === false },
    { label: 'FCC machines production', ok: state.machineStatus.active === 2 && state.machineStatus.recovery === 2 },
  ]
}

async function readLiveState() {
  const [chainId, code, manager, epoch, root, active, recovery, pendingSnapshot, pendingRecovery, armed] = await Promise.all([
    rpc('eth_chainId', []), rpc('eth_getCode', [evidence.controller, 'latest']), callView(selectors.teeManager), callView(selectors.latestEpoch), callView(selectors.latestStateRoot),
    callView(selectors.activeTee), callView(selectors.recoveryTee), callView(selectors.pendingSnapshotAction), callView(selectors.pendingRecoveryAction), callView(selectors.recoveryArmed),
  ])
  const activeAddress = decodeAddress(active)
  const recoveryAddress = decodeAddress(recovery)
  const [activeStatus, recoveryStatus] = await Promise.all([callAt(decodeAddress(manager), selectors.getTeeMachineStatus, addressArg(activeAddress)), callAt(decodeAddress(manager), selectors.getTeeMachineStatus, addressArg(recoveryAddress))])
  return [
    { label: 'chain ID', ok: BigInt(chainId) === 114n },
    { label: 'controller code', ok: code !== '0x' },
    { label: 'epoch 03', ok: BigInt(`0x${decodeWord(epoch)}`) === 3n },
    { label: 'state root', ok: root.toLowerCase() === evidence.root.toLowerCase() },
    { label: 'active TEE', ok: activeAddress.toLowerCase() === evidence.active.toLowerCase() },
    { label: 'recovery TEE', ok: recoveryAddress.toLowerCase() === evidence.recoveryFinal.toLowerCase() },
    { label: 'no pending action', ok: BigInt(`0x${decodeWord(pendingSnapshot)}`) === 0n && BigInt(`0x${decodeWord(pendingRecovery)}`) === 0n },
    { label: 'recovery unarmed', ok: BigInt(`0x${decodeWord(armed)}`) === 0n },
    { label: 'FCC machines production', ok: BigInt(`0x${decodeWord(activeStatus)}`) === 2n && BigInt(`0x${decodeWord(recoveryStatus)}`) === 2n },
  ]
}

function IdentityCell({ label, value, status, tone = '' }) { return <div className={`identity-cell ${tone}`}><span>{label}</span><strong>{value}</strong>{status && <small>{status}</small>}</div> }
function EvidenceCard({ label, value, detail, onClick }) { return <button className="evidence-card" onClick={onClick}><span className="eyebrow">{label}</span><strong>{value}</strong><small>{detail} <span aria-hidden="true">↗</span></small></button> }
function TestButton({ label, onClick }) { return <button className="secondary-action" onClick={onClick}>{label} <span aria-hidden="true">↗</span></button> }
function CopyValue({ label, value }) {
  const [copied, setCopied] = useState(false)
  const copy = async () => {
    try { await navigator.clipboard.writeText(value); setCopied(true); setTimeout(() => setCopied(false), 1200) } catch { setCopied(false) }
  }
  return <div className="copy-value"><span className="eyebrow">{label}</span><code>{value}</code><button onClick={copy}>{copied ? 'COPIED' : 'COPY'}</button></div>
}
function Inspector({ tab, close }) {
  const [selectedTab, setSelectedTab] = useState(tab)
  const content = {
    summary: ['SUMMARY', 'A recorded Coston2 acceptance path', 'Snapshot commit, exact encrypted recovery, fresh availability, activation, epoch-03 continuation, and a signed terminal FCC failure completed against the final controller.'],
    signed: ['SIGNED RESULT', 'Primary snapshot / status 1', 'The primary TEE returned a real FCC-signed result. The extension accepted it before the controller committed epoch 01 and the replacement later continued at epoch 03.'],
    contract: ['CONTRACT', 'Activation and continuation', 'The recovery TEE became active after the controller accepted its restored root and a fresh production availability proof. A new encrypted entry then committed at epoch 03.'],
    raw: ['RAW', 'Accepted state root', 'Full public identifiers for the recorded run. Ciphertext remains encrypted and is not shown in the browser.'],
    stale: ['REJECTION', 'Stale restore / deterministic test', 'The controller rejects an older epoch before it can replace the accepted state root. This remains local controller-test evidence until a live Coston2 receipt is captured.'],
    fork: ['REJECTION', 'Competing branch / deterministic test', 'The controller rejects a second state root extending an already-consumed parent. This remains local controller-test evidence until a live Coston2 receipt is captured.'],
    terminal: ['FCC FAILURE', 'Terminal error / status 0', 'The active recovery proxy returned a real FCC-signed error after a non-decryptable snapshot payload. The controller cleared the pending action with failSnapshot, and the accepted lineage remained unchanged.'],
    disclosure: ['DISCLOSURE', 'What simulated TEE proves', 'This environment proves the FCC registration, signed-result, state-verifier, and recovery protocol path. Hardware-backed confidentiality is not active.'],
  }[selectedTab]
  return <div className="inspector-backdrop" onClick={close}><aside className="inspector" onClick={(event) => event.stopPropagation()} aria-label="Evidence inspector"><div className="inspector-head"><span className="eyebrow">EVIDENCE / {content[0]}</span><button className="close-button" onClick={close} aria-label="Close evidence">×</button></div><div className="inspector-tabs" role="tablist">{['summary', 'signed', 'contract', 'terminal', 'raw'].map((name) => <button key={name} role="tab" aria-selected={selectedTab === name} className={selectedTab === name ? 'selected' : ''} onClick={() => setSelectedTab(name)}>{name.toUpperCase()}</button>)}</div><h2>{content[1]}</h2><p>{content[2]}</p>{selectedTab === 'raw' && <div className="raw-values"><CopyValue label="STATE ROOT" value={evidence.root} /><CopyValue label="SNAPSHOT COMMIT TX" value={evidence.snapshotCommitTx} /><CopyValue label="ACTIVATION TX" value={evidence.activationTx} /><CopyValue label="CONTINUATION TX" value={evidence.continuationCommitTx} /><CopyValue label="APPLICATION ID" value={evidence.appId} /><CopyValue label="PRIMARY TEE" value={evidence.primary} /><CopyValue label="RECOVERY TEE" value={evidence.recovery} /></div>}{selectedTab === 'contract' && <div className="raw-values"><CopyValue label="SNAPSHOT COMMIT TX" value={evidence.snapshotCommitTx} /><CopyValue label="RECOVERY REQUEST TX" value={evidence.recoveryRequestTx} /><CopyValue label="ACTIVATION TX" value={evidence.activationTx} /><CopyValue label="CONTINUATION TX" value={evidence.continuationCommitTx} /></div>}{selectedTab === 'terminal' && <div className="raw-values"><CopyValue label="ERROR REQUEST TX" value={evidence.terminalErrorRequestTx} /><CopyValue label="FAIL SNAPSHOT TX" value={evidence.terminalErrorClearTx} /><CopyValue label="STATE ROOT" value={evidence.root} /></div>}<div className="inspector-rule" /><div className="inspector-foot"><span>FLARE COSTON2</span><span>RECORDED REAL EVIDENCE</span></div></aside></div>
}

createRoot(document.getElementById('root')).render(<StrictMode><App /></StrictMode>)

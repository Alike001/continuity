import { StrictMode, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const evidence = {
  snapshotRequestTx: '0x66acef23627bf02472ec7047312531bb77f93c4e69ec2a30ff1b3c94806a40eb',
  snapshotCommitTx: '0x727de8eef0845f557011e7893438ae428af196922bd2af98bd56a26749f4f839',
  recoveryRequestTx: '0x6203db57ff65de973916daad0821c56c245dff65d8d9858d6c7ca50180fa8c86',
  activationTx: '0xb40a59a408aa31afeab5258679cb74d6c5cb7363da1abfe3690264e205c94e6d',
  root: '0x9019e8a3a81f8c704b03a95eeed7d5c6f87f8ca02822f54d986afaa8dd7b0acd',
  epoch: '01',
  extension: '66228',
  appId: '0x569f078a46d54c8228d4a986d2c421f1504a6456bb83d125982b0bfeb5d90b8c',
  primary: '0xb3ea8645b8f935cf5b46681871e563c50d09dc23',
  recovery: '0xad64e2257b1d1a949c1a0cba421a15797be46bf3',
}

const stages = [
  ['01', 'ANCHOR', 'Coston2', 'The registry is the source of truth.'],
  ['02', 'SNAPSHOT', 'Epoch 01', 'Primary TEE signed the sealed journal.'],
  ['03', 'IDENTITY', 'Approved code', 'App and code hash remain bound.'],
  ['04', 'HISTORY', 'Root accepted', 'The last committed state is recoverable.'],
  ['05', 'RESTORE', 'Recovery TEE', 'Encrypted state was restored into the standby.'],
  ['06', 'CONFIRM', 'Activation', 'Fresh availability proof completed the handoff.'],
  ['07', 'CONTINUE', 'Pending live proof', 'Epoch 02 continuation still needs live Coston2 evidence.'],
]

function App() {
  const [runState, setRunState] = useState('recorded')
  const [activeStage, setActiveStage] = useState(6)
  const [inspector, setInspector] = useState(null)
  const [rejection, setRejection] = useState(null)

  const openRecordedRecovery = () => {
    setRunState('complete')
    setActiveStage(6)
  }

  const inspectRejection = (kind) => {
    setRejection(kind)
    setInspector(kind === 'stale' ? 'stale' : 'fork')
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
            <h2>{runState === 'complete' ? 'Recovery verified at epoch 01.' : 'The latest state is ready to inspect.'}</h2>
            <p>The primary stopped after its encrypted snapshot was committed. The replacement restored the exact accepted root and became active through a fresh FCC availability proof.</p>
          </div>
          <div className="readiness-action">
            <div className="anchor-summary"><div><span className="eyebrow">LATEST ANCHORED STATE</span><strong>EPOCH {evidence.epoch}</strong></div><div className="root-value"><span className="eyebrow">STATE ROOT</span><button className="machine-value" onClick={() => setInspector('raw')}>{shorten(evidence.root)} <span aria-hidden="true">↗</span></button></div></div>
            <button className="primary-action" onClick={openRecordedRecovery} aria-describedby="recorded-note">
              {runState === 'complete' ? 'OPEN VERIFIED RECOVERY' : 'OPEN RECORDED RECOVERY'} <span aria-hidden="true">→</span>
            </button>
            <span id="recorded-note" className="action-note">Recorded Coston2 evidence mode. This control opens the verified run and sends no wallet transaction.</span>
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
          <div className="continuation-note"><span className="pending-mark">○</span><span><strong>CONTINUE remains pending.</strong> The next private journal entry must be committed at epoch 02 before this record can claim full continuity.</span></div>
        </section>

        <section className="evidence section-rule">
          <div className="section-heading"><div><div className="eyebrow">EVIDENCE INSPECTOR</div><h2>Nothing important is hidden behind the interface.</h2></div><button className="text-button" onClick={() => setInspector('signed')}>INSPECT ALL <span aria-hidden="true">↗</span></button></div>
          <div className="evidence-grid">
            <EvidenceCard label="SIGNED RESULT" value="Primary snapshot" detail="Status 1 · log ok" onClick={() => setInspector('signed')} />
            <EvidenceCard label="CONTRACT" value="Activation" detail={shorten(evidence.activationTx)} onClick={() => setInspector('contract')} />
            <EvidenceCard label="STATE ROOT" value={shorten(evidence.root)} detail="Accepted at epoch 01" onClick={() => setInspector('raw')} />
          </div>
        </section>

        <section className="adversarial section-rule">
          <div className="eyebrow">ADVERSARIAL CHECKS</div>
          <div className="adversarial-grid">
            <div><h2>Recovery only succeeds when the history agrees.</h2><p>Live Coston2 rejection receipts are still pending. The controls below open deterministic controller-test evidence without presenting it as a live transaction.</p></div>
            <div className="test-actions"><TestButton label="INSPECT STALE REJECTION" onClick={() => inspectRejection('stale')} /><TestButton label="INSPECT FORK REJECTION" onClick={() => inspectRejection('fork')} /></div>
          </div>
          {rejection && <div className="rejection"><span className="rejection-mark">×</span><span><strong>REJECTED IN CONTROLLER TEST</strong> / {rejection === 'stale' ? 'STALE RESTORE' : 'COMPETING BRANCH'}<small>{rejection === 'stale' ? 'Older epoch is rejected before it can replace the accepted root.' : 'A second branch extending the consumed parent is rejected.'} Live Coston2 receipt pending.</small></span></div>}
        </section>
      </main>

      <footer className="footer"><span>CONTINUITY / FLARE CONFIDENTIAL COMPUTE</span><span>SIMULATED TEE: FCC INTEGRATION VERIFIED. HARDWARE CONFIDENTIALITY IS NOT ACTIVE.</span></footer>

      {inspector && <Inspector tab={inspector} close={() => setInspector(null)} />}
    </div>
  )
}

function shorten(value) { return `${value.slice(0, 10)}…${value.slice(-8)}` }
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
    summary: ['SUMMARY', 'A recorded Coston2 acceptance path', 'Snapshot commit, exact encrypted recovery, fresh availability, and activation completed against the deployed controller. Continuation and live adversarial receipts remain open.'],
    signed: ['SIGNED RESULT', 'Primary snapshot / status 1', 'The primary TEE returned a real FCC-signed result. The extension accepted it before the controller committed epoch 01.'],
    contract: ['CONTRACT', 'Activation transaction', 'The recovery TEE became active after the controller accepted its restored root and a fresh production availability proof.'],
    raw: ['RAW', 'Accepted state root', 'Full public identifiers for the recorded run. Ciphertext remains encrypted and is not shown in the browser.'],
    stale: ['REJECTION', 'Stale restore / deterministic test', 'The controller rejects an older epoch before it can replace the accepted state root. This is local Foundry evidence until a live Coston2 receipt is captured.'],
    fork: ['REJECTION', 'Competing branch / deterministic test', 'The controller rejects a second state root extending an already-consumed parent. This is local Foundry evidence until a live Coston2 receipt is captured.'],
    disclosure: ['DISCLOSURE', 'What simulated TEE proves', 'This environment proves the FCC registration, signed-result, state-verifier, and recovery protocol path. Hardware-backed confidentiality is not active.'],
  }[selectedTab]
  return <div className="inspector-backdrop" onClick={close}><aside className="inspector" onClick={(event) => event.stopPropagation()} aria-label="Evidence inspector"><div className="inspector-head"><span className="eyebrow">EVIDENCE / {content[0]}</span><button className="close-button" onClick={close} aria-label="Close evidence">×</button></div><div className="inspector-tabs" role="tablist">{['summary', 'signed', 'contract', 'raw'].map((name) => <button key={name} role="tab" aria-selected={selectedTab === name} className={selectedTab === name ? 'selected' : ''} onClick={() => setSelectedTab(name)}>{name.toUpperCase()}</button>)}</div><h2>{content[1]}</h2><p>{content[2]}</p>{selectedTab === 'raw' && <div className="raw-values"><CopyValue label="STATE ROOT" value={evidence.root} /><CopyValue label="SNAPSHOT COMMIT TX" value={evidence.snapshotCommitTx} /><CopyValue label="ACTIVATION TX" value={evidence.activationTx} /><CopyValue label="APPLICATION ID" value={evidence.appId} /><CopyValue label="PRIMARY TEE" value={evidence.primary} /><CopyValue label="RECOVERY TEE" value={evidence.recovery} /></div>}{selectedTab === 'contract' && <div className="raw-values"><CopyValue label="SNAPSHOT COMMIT TX" value={evidence.snapshotCommitTx} /><CopyValue label="RECOVERY REQUEST TX" value={evidence.recoveryRequestTx} /><CopyValue label="ACTIVATION TX" value={evidence.activationTx} /></div>}<div className="inspector-rule" /><div className="inspector-foot"><span>FLARE COSTON2</span><span>RECORDED REAL EVIDENCE</span></div></aside></div>
}

createRoot(document.getElementById('root')).render(<StrictMode><App /></StrictMode>)

import { StrictMode, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const liveEvidence = {
  snapshotTx: '0x727de8...f4f839',
  recoveryTx: '0x6203db...0fa8c86',
  activationTx: '0xb40a59...5c94e6d',
  root: '0x9019e8a3...dd7b0acd',
  epoch: '01',
  extension: '66228',
  appId: '0x569f078a...5d90b8c',
  primary: '0xb3ea8645...d09dc23',
  recovery: '0xad64e225...7be46bf3',
}

const stages = [
  ['01', 'ANCHOR', 'Coston2', 'The registry is the source of truth.'],
  ['02', 'SNAPSHOT', 'Epoch 01', 'Primary TEE signed the sealed journal.'],
  ['03', 'IDENTITY', 'Approved code', 'App and code hash remain bound.'],
  ['04', 'HISTORY', 'Root accepted', 'The last committed state is recoverable.'],
  ['05', 'RESTORE', 'Recovery TEE', 'Encrypted state is restored into the standby.'],
  ['06', 'CONFIRM', 'Activation', 'Fresh availability proof completed the handoff.'],
  ['07', 'CONTINUE', 'Ready', 'The application can continue from epoch 01.'],
]

function App() {
  const [runState, setRunState] = useState('ready')
  const [activeStage, setActiveStage] = useState(4)
  const [inspector, setInspector] = useState(null)
  const [adversarial, setAdversarial] = useState(null)

  const replayRecovery = () => {
    if (runState === 'running') return
    setRunState('running')
    setActiveStage(4)
    setTimeout(() => setActiveStage(5), 500)
    setTimeout(() => setActiveStage(6), 1000)
    setTimeout(() => {
      setActiveStage(7)
      setRunState('complete')
    }, 1500)
  }

  const runAdversarial = (kind) => {
    setAdversarial({ kind, result: 'REJECTED', detail: kind === 'stale' ? 'Epoch 00 is older than the accepted epoch 01.' : 'Branch root does not match the accepted journal root.' })
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="wordmark" href="#top" aria-label="Continuity home">CONTINUITY<span className="wordmark-mark">/</span></a>
        <div className="topbar-meta"><span className="env-dot" /> COSTON2 <span className="meta-separator">/</span> RECOVERY RUNBOOK</div>
        <button className="text-button" onClick={() => setInspector('summary')}>OPEN EVIDENCE <span aria-hidden="true">↗</span></button>
      </header>

      <main id="top">
        <section className="intro section-rule">
          <div className="eyebrow">FCC / STATEFUL EXTENSION RECOVERY</div>
          <h1>Private application state should survive the enclave that created it.</h1>
          <p className="lede">Continuity moves the latest verified state from a failed Confidential Compute machine to a registered recovery machine, with every handoff anchored on Flare.</p>
        </section>

        <section className="identity-bar section-rule" aria-label="Application identity">
          <IdentityCell label="APPLICATION" value={liveEvidence.appId} />
          <IdentityCell label="EXTENSION" value={liveEvidence.extension} />
          <IdentityCell label="PRIMARY TEE" value={liveEvidence.primary} tone="muted" />
          <IdentityCell label="RECOVERY TEE" value={liveEvidence.recovery} tone="accent" />
        </section>

        <section className="readiness section-rule">
          <div className="readiness-copy">
            <div className="eyebrow">RECOVERY READINESS <span className="live-badge">● RECORDED LIVE EVIDENCE</span></div>
            <h2>{runState === 'complete' ? 'State recovered. Continue from epoch 01.' : 'The primary enclave is no longer the only place your state exists.'}</h2>
            <p>{runState === 'complete' ? 'Recovery activation completed on Coston2. The runbook is ready to inspect.' : 'A sealed snapshot, an exact encrypted payload, and a fresh availability proof form one verifiable recovery path.'}</p>
          </div>
          <div className="readiness-action">
            <button className="primary-action" onClick={replayRecovery} disabled={runState === 'running'}>
              {runState === 'running' ? 'REPLAYING RECOVERY…' : runState === 'complete' ? 'REPLAY AGAIN' : 'RECOVER LATEST STATE'} <span aria-hidden="true">→</span>
            </button>
            <span className="action-note">Local replay of the verified Coston2 run. No wallet or transaction is sent.</span>
          </div>
        </section>

        <section className="runbook section-rule">
          <div className="section-heading"><div><div className="eyebrow">THE RUNBOOK</div><h2>One state. One accepted path.</h2></div><span className="mono-caption">EPOCH {liveEvidence.epoch} / ROOT {liveEvidence.root}</span></div>
          <div className="ledger" role="list">
            {stages.map(([number, label, value, detail], index) => {
              const isDone = runState === 'complete' || index < activeStage - 1
              const isActive = index === activeStage - 1
              return <button className={`ledger-row ${isActive ? 'is-active' : ''} ${isDone ? 'is-done' : ''}`} key={label} onClick={() => setActiveStage(index + 1)} role="listitem">
                <span className="ledger-number">{number}</span><span className="ledger-label">{label}</span><span className="ledger-value">{value}</span><span className="ledger-detail">{isActive || isDone ? detail : 'Waiting for the previous proof.'}</span><span className="ledger-state">{isDone ? 'PASS' : isActive ? 'NOW' : '—'}</span>
              </button>
            })}
          </div>
        </section>

        <section className="evidence section-rule">
          <div className="section-heading"><div><div className="eyebrow">EVIDENCE INSPECTOR</div><h2>Nothing important is hidden behind the interface.</h2></div><button className="text-button" onClick={() => setInspector('signed')}>INSPECT ALL <span aria-hidden="true">↗</span></button></div>
          <div className="evidence-grid">
            <EvidenceCard label="SIGNED RESULT" value="Primary snapshot" detail="Status 1 · log ok" onClick={() => setInspector('signed')} />
            <EvidenceCard label="CONTRACT" value="Activation" detail={liveEvidence.activationTx} onClick={() => setInspector('contract')} />
            <EvidenceCard label="STATE ROOT" value={liveEvidence.root} detail="Accepted at epoch 01" onClick={() => setInspector('raw')} />
          </div>
        </section>

        <section className="adversarial section-rule">
          <div className="eyebrow">ADVERSARIAL CHECKS</div>
          <div className="adversarial-grid">
            <div><h2>Recovery only succeeds when the history agrees.</h2><p>These deterministic controller tests reject the two shortcuts that would make a recovery unsafe.</p></div>
            <div className="test-actions"><TestButton label="ATTEMPT STALE RESTORE" onClick={() => runAdversarial('stale')} /><TestButton label="ATTEMPT COMPETING BRANCH" onClick={() => runAdversarial('fork')} /></div>
          </div>
          {adversarial && <div className="rejection"><span className="rejection-mark">×</span><span><strong>{adversarial.result}</strong> / {adversarial.kind === 'stale' ? 'STALE RESTORE' : 'COMPETING BRANCH'}<small>{adversarial.detail} Deterministic controller test evidence.</small></span></div>}
        </section>
      </main>

      <footer className="footer"><span>CONTINUITY / FLARE CONFIDENTIAL COMPUTE</span><span>SIMULATED TEE DISCLOSURE: PROTOCOL PATH VERIFIED, HARDWARE CONFIDENTIALITY NOT CLAIMED.</span></footer>

      {inspector && <Inspector tab={inspector} close={() => setInspector(null)} />}
    </div>
  )
}

function IdentityCell({ label, value, tone = '' }) { return <div className={`identity-cell ${tone}`}><span>{label}</span><strong>{value}</strong></div> }
function EvidenceCard({ label, value, detail, onClick }) { return <button className="evidence-card" onClick={onClick}><span className="eyebrow">{label}</span><strong>{value}</strong><small>{detail} <span aria-hidden="true">↗</span></small></button> }
function TestButton({ label, onClick }) { return <button className="secondary-action" onClick={onClick}>{label} <span aria-hidden="true">↗</span></button> }
function Inspector({ tab, close }) {
  const content = {
    summary: ['SUMMARY', 'A recorded Coston2 acceptance path', 'Snapshot commit, exact encrypted recovery, fresh availability, and activation all completed against the deployed controller.'],
    signed: ['SIGNED RESULT', 'Primary snapshot / status 1', 'The primary TEE returned a real FCC-signed result. The extension accepted the signed payload before the controller committed epoch 01.'],
    contract: ['CONTRACT', 'Activation transaction', `Coston2 tx ${liveEvidence.activationTx}. Active machine is the recovery TEE. The original primary is retained as standby.`],
    raw: ['RAW', 'Accepted state root', `Epoch ${liveEvidence.epoch}. Root ${liveEvidence.root}. The UI shows shortened hashes only. The full receipts remain in the public repository evidence manifest.`],
  }[tab]
  return <div className="inspector-backdrop" onClick={close}><aside className="inspector" onClick={(e) => e.stopPropagation()}><div className="inspector-head"><span className="eyebrow">EVIDENCE / {content[0]}</span><button className="close-button" onClick={close} aria-label="Close evidence">×</button></div><h2>{content[1]}</h2><p>{content[2]}</p><div className="inspector-rule" /><div className="inspector-foot"><span>FLARE COSTON2</span><span>RECORDED LIVE</span></div></aside></div>
}

createRoot(document.getElementById('root')).render(<StrictMode><App /></StrictMode>)

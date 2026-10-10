import React from 'react'

function App() {
  const terminalText = `
=================================================
    ___ ___  ___ _____ _  _ ___ _____ ___        
   | __/ _ \\| _ \\_   _| \\| |_ _|_   _| __|       
   | _| (_) |   / | | | .\\ \` || |  | | | _|        
   |_| \\___/|_|_\\ |_| |_|\\_|___| |_| |___|       
                                                 
          [ SYSTEM OVERRIDE TERMINAL ]           
=================================================

  [+] SYS.STATE : [ ACTIVE OVERRIDE ENGAGED ]
  [>] OPERATION : Tuning memory subsystems...

  --- TELEMETRY ---------------------------------
  [*] MEM.ALLOC : 4.2 GB AVAILABLE  |  [0x00A7F1B]
  [*] THERM.SNS : 78C           |  [0x0B89C2A]
  [*] BOOST.CYC : 4              |  ENGAGEMENTS
  -----------------------------------------------
  >>> Press [Ctrl+C] to abort operation...`

  return (
    <>
      <main className="hero">
        <div className="container hero-content animate-up">
          <h1 className="hero-title">
            Dominate Every Frame
            <span>OS-GameBooster</span>
          </h1>
          <p className="hero-subtitle">
            A hardware-agnostic terminal utility that automatically tunes system memory, prioritizes CPU/GPU resources, and minimizes DPC latency for maximum competitive gaming performance.
          </p>
          <div className="btn-group">
            <a href="https://github.com/tokunboajayi/OS-GameBooster/releases" className="btn btn-primary" target="_blank" rel="noreferrer">
              Download Latest (v8.0)
            </a>
            <a href="https://github.com/tokunboajayi/OS-GameBooster" className="btn btn-secondary" target="_blank" rel="noreferrer">
              View Source on GitHub
            </a>
          </div>
        </div>
      </main>

      <section className="features container">
        <h2 className="section-title">Why OS-GameBooster?</h2>

        <div className="terminal-window" style={{ marginBottom: '4rem' }}>
          <div className="terminal-header">
            <div className="term-dot r"></div>
            <div className="term-dot y"></div>
            <div className="term-dot g"></div>
          </div>
          <div className="terminal-body">
            {terminalText}
          </div>
        </div>
        <div className="feature-grid">
          <div className="feature-card">
            <div className="feature-icon">⚡</div>
            <h3 className="feature-title">Dynamic Tracking</h3>
            <p className="feature-desc">Pass your game's executable name and let it wait in the background. It will automatically boost the moment you launch.</p>
          </div>
          <div className="feature-card">
            <div className="feature-icon">🧠</div>
            <h3 className="feature-title">ISLC Memory Cleaning</h3>
            <p className="feature-desc">Proactively clears cached standby memory lists during heavy loads to completely eliminate RAM thrashing and micro-stutters.</p>
          </div>
          <div className="feature-card">
            <div className="feature-icon">💻</div>
            <h3 className="feature-title">Hardware-Agnostic</h3>
            <p className="feature-desc">Dynamically detects and optimizes specific hardware queues, supporting Intel Arc, AMD, and Nvidia platforms natively.</p>
          </div>
        </div>
      </section>

      <footer>
        <p className="term-gray">Open Source &bull; MIT License &bull; 2026</p>
      </footer>
    </>
  )
}

export default App

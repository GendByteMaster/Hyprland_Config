import { useMemo, useState } from "react";

type Feature = {
  eyebrow: string;
  title: string;
  description: string;
  accent: string;
};

type Shortcut = {
  keys: string;
  action: string;
  scope: string;
};

const features: Feature[] = [
  {
    eyebrow: "v0.1",
    title: "Num Lock Mouse Mode",
    description:
      "Drive the pointer from the NumPad without losing your normal Super shortcuts. Directional movement, clicks, hold/release and optional HUD feedback stay in the global Hyprland keymap.",
    accent: "Mouse"
  },
  {
    eyebrow: "v0.2",
    title: "System Monitor",
    description:
      "An Omarchy bar integration for CPU, memory, network, GPU and temperature telemetry, with one-click access to btop.",
    accent: "Telemetry"
  },
  {
    eyebrow: "v0.3",
    title: "Project Launcher",
    description:
      "A keyboard-first Quickshell launcher that discovers repositories, ranks projects, detects actions and opens shells, editors, tests and dev workflows from one surface.",
    accent: "Workflow"
  },
  {
    eyebrow: "v0.4",
    title: "Workspace Overview",
    description:
      "Workspace and all-monitor window switching with compositor-backed previews, MRU ordering and a layout built for keyboard navigation.",
    accent: "Windows"
  }
];

const shortcuts: Shortcut[] = [
  { keys: "Alt + Tab", action: "Orbit window switcher", scope: "Orbit / fallback" },
  { keys: "Super + Tab", action: "Workspace Overview", scope: "Core" },
  { keys: "Ctrl + Alt + Tab", action: "Persistent all-monitor switcher", scope: "Core" },
  { keys: "Super + F8", action: "Project Launcher", scope: "Core" },
  { keys: "Super + V", action: "Clipboard Manager", scope: "Omarchy plugin" },
  { keys: "Super + A", action: "Agent Orchestrator", scope: "Omarchy plugin" },
  { keys: "Super + Alt + V", action: "AmneziaVPN", scope: "Optional app" },
  { keys: "Super + Shift + ← / →", action: "Move window between monitors", scope: "Core" },
  { keys: "Ctrl + Super + ← / →", action: "Switch workspace on current monitor", scope: "Core" }
];

const pluginCards = [
  {
    name: "Orbit",
    id: "io.github.rohan-patnaik.window-switcher",
    copy: "Windows-style Alt+Tab, snap layouts and window-mode controls."
  },
  {
    name: "Clipboard Manager",
    id: "io.github.vuhuy.clipboard-manager",
    copy: "Search, preview and reuse Omarchy clipboard history with Super + V."
  },
  {
    name: "Agent Orchestrator",
    id: "meviusisback.agent-orchestr",
    copy: "Live status for local coding agents with quick workspace switching."
  }
];

function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="command">
      <code>{command}</code>
      <button type="button" onClick={copy} aria-label="Copy command">
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}

function App() {
  const year = useMemo(() => new Date().getFullYear(), []);

  return (
    <main>
      <div className="ambient ambient-one" />
      <div className="ambient ambient-two" />

      <header className="topbar shell">
        <a className="brand" href="#top" aria-label="Hyprland Config home">
          <span className="brand-mark">HC</span>
          <span>Hyprland_Config</span>
        </a>

        <nav aria-label="Primary">
          <a href="#features">Features</a>
          <a href="#shortcuts">Hotkeys</a>
          <a href="#plugins">Plugins</a>
          <a href="#install">Install</a>
        </nav>

        <a
          className="button button-ghost"
          href="https://github.com/GendByteMaster/Hyprland_Config"
          target="_blank"
          rel="noreferrer"
        >
          GitHub
        </a>
      </header>

      <section className="hero shell" id="top">
        <div className="hero-copy">
          <div className="pill">
            <span className="pulse" />
            Lua-first · Hyprland · Omarchy
          </div>
          <h1>
            Your desktop,
            <span> wired like a workstation.</span>
          </h1>
          <p>
            Hyprland_Config adds Windows-familiar navigation, NumPad mouse control,
            workspace intelligence, project workflows and optional Omarchy integrations
            without forking your compositor or shell.
          </p>
          <div className="hero-actions">
            <a className="button button-primary" href="#install">
              Install
            </a>
            <a className="button button-secondary" href="#shortcuts">
              Explore hotkeys
            </a>
          </div>

          <div className="hero-stats" aria-label="Project highlights">
            <div>
              <strong>Lua 5.1</strong>
              <span>workstation core</span>
            </div>
            <div>
              <strong>Quickshell</strong>
              <span>interactive surfaces</span>
            </div>
            <div>
              <strong>Optional</strong>
              <span>Omarchy integration</span>
            </div>
          </div>
        </div>

        <div className="terminal-card" aria-label="Terminal installation preview">
          <div className="terminal-bar">
            <span />
            <span />
            <span />
            <em>hyprland-config</em>
          </div>
          <div className="terminal-body">
            <p><b>~</b> git clone Hyprland_Config</p>
            <p><b>~</b> cd Hyprland_Config</p>
            <p><b>~</b> lua5.1 install.lua</p>
            <p className="ok">✓ managed bindings installed</p>
            <p className="ok">✓ workspace UI linked</p>
            <p className="ok">✓ external plugins reconciled</p>
            <p className="ok">✓ verification passed</p>
            <div className="terminal-cursor" />
          </div>
          <div className="terminal-grid" aria-hidden="true">
            <span>ALT</span><span>TAB</span><span>SUPER</span>
            <span>V</span><span>A</span><span>F8</span>
          </div>
        </div>
      </section>

      <section className="section shell" id="features">
        <div className="section-heading">
          <div>
            <p className="kicker">Current stack</p>
            <h2>One layer, several focused tools.</h2>
          </div>
          <p>
            Each feature stays replaceable. Window semantics, project workflow,
            workspace UI and Omarchy integrations are kept as separate modules.
          </p>
        </div>

        <div className="feature-grid">
          {features.map((feature) => (
            <article className="feature-card" key={feature.title}>
              <div className="feature-meta">
                <span>{feature.eyebrow}</span>
                <span>{feature.accent}</span>
              </div>
              <h3>{feature.title}</h3>
              <p>{feature.description}</p>
              <div className="feature-line" />
            </article>
          ))}
        </div>
      </section>

      <section className="section shell" id="shortcuts">
        <div className="section-heading compact-heading">
          <div>
            <p className="kicker">Keyboard map</p>
            <h2>Shortcuts that stay predictable.</h2>
          </div>
        </div>

        <div className="shortcut-panel">
          {shortcuts.map((shortcut) => (
            <div className="shortcut-row" key={shortcut.keys}>
              <kbd>{shortcut.keys}</kbd>
              <span className="shortcut-action">{shortcut.action}</span>
              <span className="shortcut-scope">{shortcut.scope}</span>
            </div>
          ))}
        </div>

        <div className="note">
          <span className="note-icon">i</span>
          <p>
            In Try Omarchy on Windows, the host can intercept Super/Win chords.
            Toggle QEMU raw keyboard grab with <kbd>Ctrl + Alt + G</kbd>.
          </p>
        </div>
      </section>

      <section className="section shell split-section" id="plugins">
        <div className="split-copy">
          <p className="kicker">Omarchy integration</p>
          <h2>Pinned plugins, not floating dependencies.</h2>
          <p>
            Third-party plugins are pinned to exact Git commits, stored under a
            managed source directory and exposed to Omarchy through owned symlinks.
            Existing user-managed paths are never silently replaced.
          </p>
          <CopyCommand command="lua5.1 omarchy-plugins.lua sync" />
        </div>

        <div className="plugin-stack">
          {pluginCards.map((plugin, index) => (
            <article className="plugin-card" key={plugin.name}>
              <span className="plugin-index">0{index + 1}</span>
              <div>
                <h3>{plugin.name}</h3>
                <p>{plugin.copy}</p>
                <code>{plugin.id}</code>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="section shell vpn-section">
        <div>
          <p className="kicker">Optional desktop app</p>
          <h2>AmneziaVPN, verified before install.</h2>
          <p>
            On x86_64 Arch/Omarchy, the installer can fetch the pinned official
            AmneziaVPN release, verify SHA-256, run the unattended installer and
            expose it through <kbd>Super + Alt + V</kbd>.
          </p>
        </div>
        <div className="vpn-spec">
          <span>Version</span><strong>5.0.1.5</strong>
          <span>Source</span><strong>Official GitHub release</strong>
          <span>Launch</span><strong>QT_QPA_PLATFORM=xcb</strong>
        </div>
      </section>

      <section className="section shell install-section" id="install">
        <div className="section-heading compact-heading">
          <div>
            <p className="kicker">Quick start</p>
            <h2>Install, verify, update.</h2>
          </div>
        </div>

        <div className="install-grid">
          <article>
            <span className="step">01</span>
            <h3>Clone</h3>
            <CopyCommand command="git clone https://github.com/GendByteMaster/Hyprland_Config.git ~/Hyprland_Config && cd ~/Hyprland_Config" />
          </article>
          <article>
            <span className="step">02</span>
            <h3>Install</h3>
            <CopyCommand command="lua5.1 install.lua" />
          </article>
          <article>
            <span className="step">03</span>
            <h3>Verify</h3>
            <CopyCommand command="lua5.1 verify.lua" />
          </article>
          <article>
            <span className="step">04</span>
            <h3>Update</h3>
            <CopyCommand command="git pull --ff-only origin master && lua5.1 reinstall.lua" />
          </article>
        </div>
      </section>

      <section className="section shell architecture">
        <div className="section-heading">
          <div>
            <p className="kicker">Architecture</p>
            <h2>Hyprland first. Omarchy optional.</h2>
          </div>
          <p>
            Core behavior lives in Lua modules. Quickshell handles presentation.
            Omarchy-specific pieces are adapters and plugins rather than a hard runtime dependency.
          </p>
        </div>

        <div className="architecture-map">
          <div className="architecture-node node-primary">
            <span>Core</span>
            <strong>Hyprland + Lua</strong>
            <small>bindings · state · dispatchers</small>
          </div>
          <div className="architecture-arrow">→</div>
          <div className="architecture-column">
            <div className="architecture-node">
              <span>UI</span>
              <strong>Quickshell</strong>
              <small>launcher · overview · previews</small>
            </div>
            <div className="architecture-node">
              <span>Optional</span>
              <strong>Omarchy</strong>
              <small>HUD · monitor · external plugins</small>
            </div>
          </div>
        </div>
      </section>

      <footer className="footer shell">
        <div>
          <strong>Hyprland_Config</strong>
          <p>Keyboard-first workstation tooling for Hyprland.</p>
        </div>
        <div className="footer-links">
          <a href="https://github.com/GendByteMaster/Hyprland_Config" target="_blank" rel="noreferrer">
            Repository
          </a>
          <a href="https://github.com/GendByteMaster/Hyprland_Config/issues" target="_blank" rel="noreferrer">
            Issues
          </a>
          <span>© {year}</span>
        </div>
      </footer>
    </main>
  );
}

export default App;

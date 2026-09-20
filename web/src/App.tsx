import { useMemo, useState } from "react";
import type { ComponentType } from "react";
import {
  Activity,
  ArrowRight,
  Bot,
  Boxes,
  Check,
  CheckCircle2,
  Clipboard,
  Copy,
  Cpu,
  ExternalLink,
  GitBranch,
  Github,
  Keyboard,
  Layers,
  LayoutGrid,
  Monitor,
  MousePointer2,
  PackageCheck,
  RefreshCw,
  ShieldCheck,
  Sparkles,
  Terminal,
  Wifi
} from "lucide-react";

type IconType = ComponentType<{
  size?: number | string;
  strokeWidth?: number;
  className?: string;
  "aria-hidden"?: boolean;
}>;

type Feature = {
  eyebrow: string;
  title: string;
  description: string;
  icon: IconType;
};

type Shortcut = {
  keys: string;
  action: string;
  scope: string;
  icon: IconType;
};

type Plugin = {
  name: string;
  id: string;
  description: string;
  icon: IconType;
};

const features: Feature[] = [
  {
    eyebrow: "v0.1 · input",
    title: "Num Lock Mouse Mode",
    description:
      "Turn the NumPad into a full pointer controller without entering a separate submap or sacrificing your normal Super shortcuts.",
    icon: MousePointer2
  },
  {
    eyebrow: "v0.2 · telemetry",
    title: "System Monitor",
    description:
      "A compact Omarchy surface for CPU, memory, network, GPU and temperature telemetry with direct access to btop.",
    icon: Activity
  },
  {
    eyebrow: "v0.3 · workflow",
    title: "Project Launcher",
    description:
      "Discover repositories, rank projects and launch shells, editors, tests or dev workflows from one keyboard-first surface.",
    icon: Terminal
  },
  {
    eyebrow: "v0.4 · workspace",
    title: "Workspace Overview",
    description:
      "Switch between workspaces and windows across monitors using compositor-backed previews and a predictable MRU flow.",
    icon: LayoutGrid
  }
];

const shortcuts: Shortcut[] = [
  { keys: "Alt + Tab", action: "Orbit window switcher", scope: "Orbit / fallback", icon: Layers },
  { keys: "Super + Tab", action: "Workspace Overview", scope: "Core", icon: LayoutGrid },
  { keys: "Ctrl + Alt + Tab", action: "All-monitor switcher", scope: "Core", icon: Monitor },
  { keys: "Super + F8", action: "Project Launcher", scope: "Core", icon: Terminal },
  { keys: "Super + V", action: "Clipboard Manager", scope: "Plugin", icon: Clipboard },
  { keys: "Super + A", action: "Agent Orchestrator", scope: "Plugin", icon: Bot },
  { keys: "Super + Alt + V", action: "AmneziaVPN", scope: "Optional", icon: ShieldCheck },
  { keys: "Super + Shift + ← / →", action: "Move window between monitors", scope: "Core", icon: Monitor }
];

const plugins: Plugin[] = [
  {
    name: "Orbit",
    id: "io.github.rohan-patnaik.window-switcher",
    description: "Windows-style Alt+Tab, snap layouts and mode switching.",
    icon: Layers
  },
  {
    name: "Clipboard Manager",
    id: "io.github.vuhuy.clipboard-manager",
    description: "Search, preview and reuse clipboard history with Super + V.",
    icon: Clipboard
  },
  {
    name: "Agent Orchestrator",
    id: "meviusisback.agent-orchestr",
    description: "See local coding-agent status and move between active workflows.",
    icon: Bot
  }
];

const installSteps = [
  {
    step: "01",
    title: "Clone",
    description: "Get the repository into a predictable workstation path.",
    icon: GitBranch,
    command:
      "git clone https://github.com/GendByteMaster/Hyprland_Config.git ~/Hyprland_Config && cd ~/Hyprland_Config"
  },
  {
    step: "02",
    title: "Install",
    description: "Create managed links, preserve existing config and reconcile optional pieces.",
    icon: PackageCheck,
    command: "lua5.1 install.lua"
  },
  {
    step: "03",
    title: "Verify",
    description: "Validate links, Lua syntax, Quickshell surfaces and Omarchy integration.",
    icon: CheckCircle2,
    command: "lua5.1 verify.lua"
  },
  {
    step: "04",
    title: "Update",
    description: "Fast-forward master and reconcile the current workstation state.",
    icon: RefreshCw,
    command: "git pull --ff-only origin master && lua5.1 reinstall.lua"
  }
];

function ProjectLogo({ compact = false }: { compact?: boolean }) {
  return (
    <span className={compact ? "project-logo project-logo-compact" : "project-logo"}>
      <img src="/logo.svg" alt="" aria-hidden="true" />
    </span>
  );
}

function CopyCommand({
  command,
  compact = false
}: {
  command: string;
  compact?: boolean;
}) {
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
    <div className={compact ? "command command-compact" : "command"}>
      <code title={command}>{command}</code>
      <button
        type="button"
        onClick={copy}
        className={copied ? "copy-button is-copied" : "copy-button"}
        aria-label={copied ? "Command copied" : "Copy command"}
      >
        {copied ? <Check size={15} /> : <Copy size={15} />}
        <span>{copied ? "Copied" : "Copy"}</span>
      </button>
    </div>
  );
}

function SectionHeading({
  eyebrow,
  title,
  copy
}: {
  eyebrow: string;
  title: string;
  copy?: string;
}) {
  return (
    <div className="section-heading">
      <div>
        <p className="kicker">{eyebrow}</p>
        <h2>{title}</h2>
      </div>
      {copy ? <p>{copy}</p> : null}
    </div>
  );
}

function App() {
  const year = useMemo(() => new Date().getFullYear(), []);

  return (
    <main>
      <div className="page-grid" aria-hidden="true" />
      <div className="ambient ambient-one" aria-hidden="true" />
      <div className="ambient ambient-two" aria-hidden="true" />

      <header className="topbar shell">
        <a className="brand" href="#top" aria-label="Hyprland Config home">
          <ProjectLogo compact />
          <span className="brand-copy">
            <strong>Hyprland_Config</strong>
            <small>workstation layer</small>
          </span>
        </a>

        <nav aria-label="Primary">
          <a href="#features">Features</a>
          <a href="#shortcuts">Hotkeys</a>
          <a href="#plugins">Plugins</a>
          <a href="#install">Install</a>
        </nav>

        <a
          className="button button-ghost github-button"
          href="https://github.com/GendByteMaster/Hyprland_Config"
          target="_blank"
          rel="noreferrer"
        >
          <Github size={16} />
          <span>GitHub</span>
          <ExternalLink size={13} className="external-icon" />
        </a>
      </header>

      <section className="hero shell" id="top">
        <div className="hero-copy">
          <div className="pill">
            <span className="pulse" />
            <span>Hyprland 0.55+ · Lua 5.1 · Quickshell</span>
          </div>

          <h1>
            Build your desktop
            <span> around the way you work.</span>
          </h1>

          <p>
            A keyboard-first workstation layer for Hyprland with Windows-familiar
            navigation, NumPad mouse control, project workflows and optional Omarchy
            integrations — without forking your compositor or shell.
          </p>

          <div className="hero-actions">
            <a className="button button-primary" href="#install">
              <Terminal size={16} />
              Quick start
              <ArrowRight size={15} />
            </a>
            <a
              className="button button-secondary"
              href="https://github.com/GendByteMaster/Hyprland_Config"
              target="_blank"
              rel="noreferrer"
            >
              <Github size={16} />
              View source
            </a>
          </div>

          <div className="hero-proof">
            <div>
              <span className="proof-icon"><Keyboard size={17} /></span>
              <div>
                <strong>Keyboard first</strong>
                <small>predictable global bindings</small>
              </div>
            </div>
            <div>
              <span className="proof-icon"><ShieldCheck size={17} /></span>
              <div>
                <strong>Safe ownership</strong>
                <small>backups + managed symlinks</small>
              </div>
            </div>
            <div>
              <span className="proof-icon"><Boxes size={17} /></span>
              <div>
                <strong>Modular</strong>
                <small>Omarchy stays optional</small>
              </div>
            </div>
          </div>
        </div>

        <div className="workspace-preview" aria-label="Hyprland Config workstation preview">
          <div className="preview-toolbar">
            <div className="preview-brand">
              <ProjectLogo compact />
              <span>workspace</span>
            </div>
            <div className="preview-status">
              <span className="status-dot" />
              active
            </div>
          </div>

          <div className="preview-stage">
            <div className="preview-window preview-window-main">
              <div className="window-title">
                <Terminal size={14} />
                <span>Hyprland_Config</span>
                <span className="window-badge">master</span>
              </div>
              <div className="terminal-lines">
                <p><b>~</b> lua5.1 verify.lua</p>
                <p className="ok"><Check size={13} /> managed bindings</p>
                <p className="ok"><Check size={13} /> workspace surfaces</p>
                <p className="ok"><Check size={13} /> plugin ownership</p>
              </div>
            </div>

            <div className="preview-window preview-window-side">
              <div className="side-card-icon"><LayoutGrid size={20} /></div>
              <span>Workspace Overview</span>
              <small>Super + Tab</small>
            </div>

            <div className="preview-window preview-window-mini">
              <div className="mini-metric">
                <Activity size={15} />
                <span>System</span>
              </div>
              <strong>ready</strong>
            </div>
          </div>

          <div className="preview-dock">
            <span><Keyboard size={15} /> Alt + Tab</span>
            <span><Clipboard size={15} /> Super + V</span>
            <span><Terminal size={15} /> Super + F8</span>
          </div>
        </div>
      </section>

      <section className="trust-strip shell" aria-label="Project principles">
        <div>
          <Cpu size={16} />
          <span>Hyprland-first runtime</span>
        </div>
        <div>
          <Wifi size={16} />
          <span>Optional network integrations</span>
        </div>
        <div>
          <ShieldCheck size={16} />
          <span>Exact plugin revisions</span>
        </div>
        <div>
          <Sparkles size={16} />
          <span>Quickshell productivity UI</span>
        </div>
      </section>

      <section className="section shell" id="features">
        <SectionHeading
          eyebrow="Current stack"
          title="Focused tools, one workstation layer."
          copy="Each capability is kept separate so you can evolve window semantics, project workflow, workspace UI and Omarchy integration independently."
        />

        <div className="feature-grid">
          {features.map((feature) => {
            const Icon = feature.icon;
            return (
              <article className="feature-card" key={feature.title}>
                <div className="feature-topline">
                  <span className="feature-icon"><Icon size={20} /></span>
                  <span className="feature-meta">{feature.eyebrow}</span>
                </div>
                <h3>{feature.title}</h3>
                <p>{feature.description}</p>
                <span className="feature-arrow" aria-hidden="true">
                  <ArrowRight size={18} />
                </span>
              </article>
            );
          })}
        </div>
      </section>

      <section className="section shell" id="shortcuts">
        <SectionHeading
          eyebrow="Keyboard map"
          title="Shortcuts that are easy to remember."
          copy="Core bindings stay stable. Optional integrations only claim a key when their target is actually installed."
        />

        <div className="shortcut-panel">
          {shortcuts.map((shortcut) => {
            const Icon = shortcut.icon;
            return (
              <div className="shortcut-row" key={shortcut.keys}>
                <span className="shortcut-icon"><Icon size={17} /></span>
                <kbd>{shortcut.keys}</kbd>
                <span className="shortcut-action">{shortcut.action}</span>
                <span className="shortcut-scope">{shortcut.scope}</span>
              </div>
            );
          })}
        </div>

        <div className="info-card">
          <div className="info-card-icon"><Monitor size={18} /></div>
          <div>
            <strong>Running Try Omarchy on Windows?</strong>
            <p>
              The host can intercept Super/Win chords before Hyprland sees them.
              Toggle QEMU raw keyboard grab with <kbd>Ctrl + Alt + G</kbd>.
            </p>
          </div>
        </div>
      </section>

      <section className="section shell plugin-section" id="plugins">
        <div className="plugin-intro">
          <p className="kicker">Omarchy integration</p>
          <h2>Pinned plugins. Explicit ownership.</h2>
          <p>
            Third-party plugins are pinned to exact Git commits, stored outside the
            Omarchy tree and exposed through owned symlinks. Existing user-managed paths
            are preserved rather than silently replaced.
          </p>

          <div className="plugin-command">
            <span className="command-label">
              <Terminal size={14} />
              Sync managed plugins
            </span>
            <CopyCommand command="lua5.1 omarchy-plugins.lua sync" compact />
          </div>
        </div>

        <div className="plugin-stack">
          {plugins.map((plugin, index) => {
            const Icon = plugin.icon;
            return (
              <article className="plugin-card" key={plugin.name}>
                <div className="plugin-icon"><Icon size={21} /></div>
                <div className="plugin-card-copy">
                  <div className="plugin-title-row">
                    <h3>{plugin.name}</h3>
                    <span>0{index + 1}</span>
                  </div>
                  <p>{plugin.description}</p>
                  <code>{plugin.id}</code>
                </div>
              </article>
            );
          })}
        </div>
      </section>

      <section className="section shell security-section">
        <div className="security-card">
          <div className="security-icon">
            <ShieldCheck size={28} />
          </div>
          <div className="security-copy">
            <p className="kicker">Optional desktop app</p>
            <h2>AmneziaVPN, verified before execution.</h2>
            <p>
              On x86_64 Arch/Omarchy, the installer can fetch the pinned official
              release, validate its SHA-256 and expose it through
              <kbd>Super + Alt + V</kbd>.
            </p>
          </div>
          <dl className="security-spec">
            <div>
              <dt>Version</dt>
              <dd>5.0.1.5</dd>
            </div>
            <div>
              <dt>Source</dt>
              <dd>Official GitHub release</dd>
            </div>
            <div>
              <dt>Wayland</dt>
              <dd>QT_QPA_PLATFORM=xcb</dd>
            </div>
          </dl>
        </div>
      </section>

      <section className="section shell install-section" id="install">
        <SectionHeading
          eyebrow="Quick start"
          title="From clone to verified workstation."
          copy="Every command is copyable. The longer clone/update commands get a full-width code row instead of being truncated inside narrow cards."
        />

        <div className="install-grid">
          {installSteps.map((item) => {
            const Icon = item.icon;
            return (
              <article className="install-card" key={item.step}>
                <div className="install-card-head">
                  <span className="step">{item.step}</span>
                  <span className="install-icon"><Icon size={18} /></span>
                </div>
                <h3>{item.title}</h3>
                <p>{item.description}</p>
                <CopyCommand command={item.command} />
              </article>
            );
          })}
        </div>
      </section>

      <section className="section shell architecture">
        <SectionHeading
          eyebrow="Architecture"
          title="Hyprland first. Omarchy optional."
          copy="Core behavior lives in Lua modules. Quickshell handles presentation. Omarchy-specific pieces remain adapters instead of becoming hard runtime dependencies."
        />

        <div className="architecture-map">
          <article className="architecture-node node-primary">
            <span className="node-icon"><Cpu size={20} /></span>
            <div>
              <span className="node-label">Core</span>
              <strong>Hyprland + Lua</strong>
              <small>bindings · ownership · dispatchers</small>
            </div>
          </article>

          <div className="architecture-connector" aria-hidden="true">
            <span />
            <ArrowRight size={17} />
          </div>

          <div className="architecture-column">
            <article className="architecture-node">
              <span className="node-icon"><Sparkles size={20} /></span>
              <div>
                <span className="node-label">Presentation</span>
                <strong>Quickshell</strong>
                <small>launcher · overview · previews</small>
              </div>
            </article>

            <article className="architecture-node">
              <span className="node-icon"><Boxes size={20} /></span>
              <div>
                <span className="node-label">Optional</span>
                <strong>Omarchy</strong>
                <small>HUD · monitor · managed plugins</small>
              </div>
            </article>
          </div>
        </div>
      </section>

      <section className="cta shell">
        <div className="cta-brand">
          <ProjectLogo />
        </div>
        <div className="cta-copy">
          <p className="kicker">Open source workstation</p>
          <h2>Make Hyprland feel like your desktop.</h2>
          <p>
            Clone the project, verify the setup and keep every optional integration
            under explicit ownership.
          </p>
        </div>
        <a className="button button-primary" href="#install">
          Start installing
          <ArrowRight size={15} />
        </a>
      </section>

      <footer className="footer shell">
        <div className="footer-brand">
          <ProjectLogo compact />
          <div>
            <strong>Hyprland_Config</strong>
            <p>Keyboard-first workstation tooling for Hyprland.</p>
          </div>
        </div>

        <div className="footer-links">
          <a
            href="https://github.com/GendByteMaster/Hyprland_Config"
            target="_blank"
            rel="noreferrer"
          >
            <Github size={14} />
            Repository
          </a>
          <a
            href="https://github.com/GendByteMaster/Hyprland_Config/issues"
            target="_blank"
            rel="noreferrer"
          >
            Issues
          </a>
          <span>© {year}</span>
        </div>
      </footer>
    </main>
  );
}

export default App;

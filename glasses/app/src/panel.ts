/** Phone-side Host setup and Space roster. */

import type { HostSettings, Snapshot } from "./protocol";

const MARKS: Record<string, string> = { blocked: "!", failed: "×", done: "+", working: "›", idle: "–", unknown: "?" };
const CSS = `
  :root { color-scheme: light dark; }
  body { margin:0; padding:14px; font:13px/1.35 ui-sans-serif,system-ui,-apple-system,sans-serif; background:Canvas; color:CanvasText; }
  .top { display:flex; align-items:baseline; justify-content:space-between; gap:12px; margin-bottom:14px; } h1 { font-size:14px; margin:0; font-weight:650; }
  .status { font-size:11px; opacity:.62; white-space:nowrap; } .dot { display:inline-block; width:6px; height:6px; border-radius:50%; background:#999; margin-right:5px; } .dot.on { background:#1a9b49; }
  h2 { font-size:10px; letter-spacing:.08em; text-transform:uppercase; opacity:.52; margin:16px 0 7px; } ul { list-style:none; margin:0; padding:0; display:grid; gap:6px; }
  li { display:grid; grid-template-columns:14px minmax(0,1fr) auto; align-items:center; gap:7px; min-height:31px; padding:6px 8px; border:1px solid color-mix(in srgb,CanvasText 15%,transparent); border-radius:7px; }
  .host { grid-template-columns:8px minmax(0,1fr) auto; } .agent { grid-template-columns:18px 14px minmax(0,1fr) auto; } .agent input { width:auto; margin:0; }
  li.group { display:block; border:0; padding:8px 2px 0; min-height:0; font-size:10px; letter-spacing:.06em; text-transform:uppercase; opacity:.5; } .host button { margin:0; padding:2px 5px; background:transparent; color:inherit; border:0; opacity:.48; font-size:11px; }
  .mark { text-align:center; opacity:.8; } .space { min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-weight:560; } .state { font-size:11px; opacity:.56; } .empty { display:block; border-style:dashed; opacity:.58; font-size:12px; }
  details { margin-top:14px; border-top:1px solid color-mix(in srgb,CanvasText 10%,transparent); padding-top:9px; } summary { cursor:pointer; font-size:12px; font-weight:600; } .help { font-size:11px; opacity:.6; margin:7px 0; }
  label { display:block; font-size:10px; opacity:.55; margin:8px 0 3px; } input { width:100%; box-sizing:border-box; padding:6px 7px; font:inherit; font-size:12px; border:1px solid color-mix(in srgb,CanvasText 20%,transparent); border-radius:6px; background:Canvas; color:inherit; }
  button { margin-top:9px; padding:6px 9px; font:inherit; font-size:12px; font-weight:600; border:0; border-radius:6px; background:#1f6feb; color:#fff; cursor:pointer; }
`;

export interface PanelOptions {
  hosts: HostSettings[];
  onSaveHosts: (hosts: HostSettings[]) => void;
  /** Checked means the Space renders on the lens; unchecked hides it there. */
  onToggleSpace: (id: string, visible: boolean) => void;
}

export class Panel {
  #hosts: HTMLElement; #agents: HTMLElement; #dot: HTMLElement; #label: HTMLElement; #settings: HostSettings[]; #onSaveHosts: PanelOptions["onSaveHosts"]; #onToggleSpace: PanelOptions["onToggleSpace"];

  constructor(root: HTMLElement, options: PanelOptions) {
    const style = document.createElement("style"); style.textContent = CSS; document.head.append(style);
    root.innerHTML = `
      <div class="top"><h1>Herden</h1><div class="status"><span class="dot"></span><span class="label">not connected</span></div></div>
      <h2>Hosts</h2><ul id="hosts"></ul>
      <h2>Spaces on the lens</h2><ul id="agents"><li class="empty">waiting for Herden…</li></ul>
      <details><summary>Add a Host</summary><p class="help">On that machine, run <code>herden glasses enable</code>, then enter its private HUD address and token here.</p>
        <label for="name">Host name</label><input id="name" placeholder="workstation" autocapitalize="off" spellcheck="false">
        <label for="url">HUD URL</label><input id="url" type="url" placeholder="http://host.ts.net:8791" autocapitalize="off" spellcheck="false">
        <label for="token">Token</label><input id="token" type="password" placeholder="shared secret">
        <button id="add">Add Host</button>
      </details>`;
    this.#hosts = root.querySelector<HTMLElement>("#hosts")!; this.#agents = root.querySelector<HTMLElement>("#agents")!; this.#dot = root.querySelector<HTMLElement>(".dot")!; this.#label = root.querySelector<HTMLElement>(".label")!;
    this.#settings = options.hosts; this.#onSaveHosts = options.onSaveHosts; this.#onToggleSpace = options.onToggleSpace; this.#renderHosts(new Set());
    root.querySelector<HTMLButtonElement>("#add")!.addEventListener("click", () => {
      const name = root.querySelector<HTMLInputElement>("#name")!.value.trim(); const baseUrl = root.querySelector<HTMLInputElement>("#url")!.value.trim(); const token = root.querySelector<HTMLInputElement>("#token")!.value.trim();
      if (!name || !baseUrl || !token) return;
      this.#settings = [...this.#settings, { id: crypto.randomUUID(), name, baseUrl, token }];
      this.#onSaveHosts(this.#settings); root.querySelector<HTMLDetailsElement>("details")!.open = false;
    });
  }

  setHosts(hosts: HostSettings[], online: Set<string>): void { this.#settings = hosts; this.#renderHosts(online); }
  setConnection(online: boolean, detail = ""): void { this.#dot.classList.toggle("on", online); this.#label.textContent = online ? `connected${detail}` : "not connected"; }

  #renderHosts(online: Set<string>): void {
    if (this.#settings.length === 0) { this.#hosts.innerHTML = `<li class="empty">add a Herden Host</li>`; return; }
    this.#hosts.replaceChildren(...this.#settings.map((host) => {
      const li = document.createElement("li"); li.className = "host";
      const dot = document.createElement("span"); dot.className = `dot${online.has(host.id) ? " on" : ""}`;
      const name = document.createElement("span"); name.className = "space"; name.textContent = host.name;
      const remove = document.createElement("button"); remove.textContent = "Remove"; remove.addEventListener("click", () => { this.#settings = this.#settings.filter((item) => item.id !== host.id); this.#onSaveHosts(this.#settings); });
      li.append(dot, name, remove); return li;
    }));
  }

  /** Every Space every Host reports, hidden ones included, grouped by Host. */
  render(snapshot: Snapshot, hosts: HostSettings[], online: Set<string>, hidden: Set<string> = new Set()): void {
    this.setHosts(hosts, online); this.setConnection(online.size > 0, ` · ${hosts.length} Host${hosts.length === 1 ? "" : "s"}`);
    if (snapshot.agents.length === 0) { this.#agents.innerHTML = `<li class="empty">no Spaces running</li>`; return; }
    // Merged snapshots are ordered by urgency, not by Host, so collect each
    // Host's Spaces before rendering or a Host header would repeat.
    const groups = new Map<string, typeof snapshot.agents>();
    for (const agent of snapshot.agents) {
      const host = agent.hostName || "Host";
      const bucket = groups.get(host); if (bucket) bucket.push(agent); else groups.set(host, [agent]);
    }
    const rows: HTMLElement[] = [];
    for (const [host, members] of groups) {
      const header = document.createElement("li"); header.className = "group"; header.textContent = host; rows.push(header);
      for (const agent of members) {
      const li = document.createElement("li"); li.className = "agent";
      const choice = document.createElement("input"); choice.type = "checkbox"; choice.checked = !hidden.has(agent.id);
      choice.setAttribute("aria-label", `Show ${agent.space || "Unnamed Space"} on the lens`);
      choice.addEventListener("change", () => this.#onToggleSpace(agent.id, choice.checked));
      const mark = document.createElement("span"); mark.className = "mark"; mark.textContent = MARKS[agent.status] ?? "?";
      const space = document.createElement("span"); space.className = "space"; space.textContent = agent.space || "Unnamed Space";
      const state = document.createElement("span"); state.className = "state"; state.textContent = agent.status;
      li.append(choice, mark, space, state); rows.push(li);
      }
    }
    this.#agents.replaceChildren(...rows);
  }
}

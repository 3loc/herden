/** Herden HUD — a compact, Space-first view across saved private Hosts. */

import {
  CreateStartUpPageContainer, RebuildPageContainer, EvenAppBridge, OsEventTypeList,
  ImageContainerProperty, ImageRawDataUpdate, TextContainerProperty, waitForEvenAppBridge,
} from "@evenrealities/even_hub_sdk";
import { BridgeClient } from "./client";
import { compactOutputLines, outputWindowSize, renderDetail, renderList } from "./hud";
import { Panel } from "./panel";
import { parseHiddenSpaces, serialiseHiddenSpaces, visibleSnapshot } from "./selection";
import { rasterizeTerminalFrame } from "./pixel-font";
import type { Agent, HostSettings, Snapshot } from "./protocol";

const CONTAINER_ID = 1;
const CANVAS = { width: 576, height: 288 };
const IMAGE = { width: 288, height: 144 };
const STORAGE_KEYS = { hosts: "herden.hosts", baseUrl: "herden.baseUrl", token: "herden.token", hiddenSpaces: "herden.hiddenSpaces" };
// Explicit and development-only: never load saved Hosts or contact a real
// endpoint while making public screenshots.
const DEMO = import.meta.env.DEV && new URLSearchParams(location.search).get("demo") === "1";
const DEVELOPMENT_PROXY_HOSTS: HostSettings[] = (() => {
  if (!import.meta.env.DEV || import.meta.env.VITE_HERDEN_HUD_PROXY !== "1") return [];
  try {
    const hosts = JSON.parse(import.meta.env.VITE_HERDEN_HUD_PROXY_HOSTS ?? "[]") as HostSettings[];
    if (hosts.length > 0) return hosts;
  } catch { /* fall back to the single local development proxy */ }
  return [{ id: "development-3loc", name: "3loc", baseUrl: "http://localhost:5173/hud", token: "development-proxy" }];
})();

type View = "list" | "detail";
const state = {
  view: "list" as View, selected: 0, userSelected: false, online: false,
  snapshot: null as Snapshot | null, roster: null as Snapshot | null, hosts: [] as HostSettings[],
  output: [] as string[], outputOffset: 0, phase: 0,
  outputLoading: false, lastText: "", painting: Promise.resolve(),
};
/** Projected `${hostId}:${remoteId}` ids the wearer chose to keep off the lens. */
const hiddenSpaces = new Set<string>();
const sourceSnapshots = new Map<string, Snapshot>();
const onlineHosts = new Set<string>();
const clients = new Map<string, BridgeClient>();
let bridge: EvenAppBridge;
let panel: Panel | null = null;

function selectedAgent(): Agent | null { return state.snapshot?.agents[state.selected] ?? null; }

function imageName(index: number): string { return `herden-pixels-${index + 1}`; }

function page(): { containerTotalNum: number; textObject: TextContainerProperty[]; imageObject: ImageContainerProperty[] } {
  return {
    containerTotalNum: 5,
    // Image containers cannot receive gestures. Keep this transparent text
    // surface solely as the one permitted Even event target.
    textObject: [new TextContainerProperty({
      containerID: CONTAINER_ID, containerName: "herden-controls", xPosition: 0, yPosition: 0,
      width: CANVAS.width, height: CANVAS.height, isEventCapture: 1, paddingLength: 0,
      borderWidth: 0, borderColor: 0, zOrderIndex: 0, content: " ",
    })],
    imageObject: Array.from({ length: 4 }, (_, index) => new ImageContainerProperty({
      containerID: CONTAINER_ID + index + 1, containerName: imageName(index),
      xPosition: (index % 2) * IMAGE.width, yPosition: Math.floor(index / 2) * IMAGE.height,
      width: IMAGE.width, height: IMAGE.height, zOrderIndex: index + 1,
    })),
  };
}
async function upgrade(content: string): Promise<void> {
  const images = rasterizeTerminalFrame(content);
  for (let index = 0; index < images.length; index += 1) {
    const result = await bridge.updateImageRawData(new ImageRawDataUpdate({
      containerID: CONTAINER_ID + index + 1, containerName: imageName(index), imageData: images[index],
    }));
    if (result !== "success") throw new Error(`bitmap tile ${index + 1}: ${result}`);
  }
}

function mergedSnapshot(): Snapshot | null {
  const reports = state.hosts.flatMap((host) => {
    const snapshot = sourceSnapshots.get(host.id);
    return snapshot ? [{ host, snapshot }] : [];
  });
  if (reports.length === 0) return null;
  const agents = reports.flatMap(({ host, snapshot }) => snapshot.agents.map((agent) => ({
    ...agent, id: `${host.id}:${agent.id}`, hostId: host.id, hostName: host.name, remoteId: agent.id,
  })));
  const wake = reports.flatMap(({ host, snapshot }) => snapshot.wake.map((id) => `${host.id}:${id}`));
  return {
    protocol_version: 1, type: "snapshot", revision: Math.max(...reports.map(({ snapshot }) => snapshot.revision)),
    at: Date.now(), inventory_valid: reports.every(({ snapshot }) => snapshot.inventory_valid), stale: reports.some(({ snapshot }) => snapshot.stale),
    controls_allowed: reports.some(({ snapshot }) => snapshot.controls_allowed), agents, wake,
    summary: `${agents.length} Space${agents.length === 1 ? "" : "s"}`,
  };
}

async function paint(): Promise<void> {
  state.painting = state.painting.catch(() => {}).then(async () => {
    const snapshot = state.snapshot; const agent = state.view === "detail" ? selectedAgent() : null;
    const output = state.outputLoading ? ["reading output…"] : state.output;
    const empty = (state.roster?.agents.length ?? 0) > 0 ? "no Spaces selected" : "no agents";
    const content = agent ? renderDetail(agent, output, state.outputOffset, state.online)
      : snapshot ? renderList(snapshot, state.selected, state.online, state.phase, empty) : "connecting…";
    if (content === state.lastText) return;
    await upgrade(content); state.lastText = content;
  });
  await state.painting;
}

function refreshProjection(): void {
  const previousId = selectedAgent()?.id;
  state.roster = mergedSnapshot();
  state.snapshot = state.roster ? visibleSnapshot(state.roster, hiddenSpaces) : null;
  state.online = onlineHosts.size > 0;
  const moved = state.snapshot?.agents.findIndex((agent) => agent.id === previousId) ?? -1;
  state.selected = state.userSelected && moved >= 0 ? moved : 0;
  // The panel keeps showing every Space, including the hidden ones.
  if (panel && state.roster) panel.render(state.roster, state.hosts, onlineHosts, hiddenSpaces);
  else panel?.setHosts(state.hosts, onlineHosts);
  void paint();
}

/** A checkbox in the panel takes effect on the lens without a reconnect. */
async function setSpaceVisible(id: string, visible: boolean): Promise<void> {
  if (visible) hiddenSpaces.delete(id); else hiddenSpaces.add(id);
  refreshProjection();
  await bridge.setLocalStorage(STORAGE_KEYS.hiddenSpaces, serialiseHiddenSpaces(hiddenSpaces));
}

function connect(hosts: HostSettings[]): void {
  for (const client of clients.values()) client.disconnect();
  clients.clear(); sourceSnapshots.clear(); onlineHosts.clear(); state.hosts = hosts;
  for (const host of hosts) {
    const client = new BridgeClient({
      baseUrl: host.baseUrl, token: host.token,
      // Snapshots arrive roughly once a second; they are the flash clock.
      onSnapshot: (snapshot) => { sourceSnapshots.set(host.id, snapshot); state.phase += 1; refreshProjection(); },
      onConnectionChange: (online) => { if (online) onlineHosts.add(host.id); else onlineHosts.delete(host.id); refreshProjection(); },
      onCommandError: (message) => panel?.setConnection(state.online, ` · ${message}`),
    });
    clients.set(host.id, client); client.connect();
  }
  refreshProjection();
}

async function handleSystemEvent(eventType: OsEventTypeList): Promise<void> {
  switch (eventType) {
    case OsEventTypeList.CLICK_EVENT:
      if (state.view === "list" && selectedAgent()) await openSelectedOutput();
      break;
    case OsEventTypeList.DOUBLE_CLICK_EVENT:
      state.view = "list"; state.output = []; state.outputOffset = 0; state.outputLoading = false;
      break;
    case OsEventTypeList.SCROLL_TOP_EVENT:
      if (state.view === "list") { state.userSelected = true; state.selected = Math.max(0, state.selected - 1); }
      else state.outputOffset = Math.max(0, state.outputOffset - 1);
      break;
    case OsEventTypeList.SCROLL_BOTTOM_EVENT:
      if (state.view === "list") { state.userSelected = true; state.selected = Math.min((state.snapshot?.agents.length ?? 1) - 1, state.selected + 1); }
      else state.outputOffset = Math.min(Math.max(0, state.output.length - outputWindowSize()), state.outputOffset + 1);
      break;
    default: return;
  }
  await paint();
}

async function openSelectedOutput(): Promise<void> {
  const agent = selectedAgent();
  if (DEMO && agent) {
    const { demoOutput } = await import("./demo");
    state.view = "detail"; state.output = demoOutput; state.outputOffset = 0;
    await paint();
    return;
  }
  if (!agent?.hostId || !agent.remoteId) return;
  state.view = "detail"; state.output = []; state.outputOffset = 0; state.outputLoading = true;
  await paint();
  try {
    const output = await clients.get(agent.hostId)?.readOutput(agent.remoteId);
    if (!output || state.view !== "detail" || selectedAgent()?.id !== agent.id) return;
    state.output = compactOutputLines(output.text);
    state.outputOffset = Math.max(0, state.output.length - outputWindowSize());
  } catch (error) {
    if (state.view !== "detail" || selectedAgent()?.id !== agent.id) return;
    state.output = [error instanceof Error ? error.message : "Output is unavailable."];
  } finally {
    state.outputLoading = false;
    await paint();
  }
}

async function loadHosts(): Promise<HostSettings[]> {
  // The simulator receives explicit non-secret proxy hosts. Keep real device
  // settings independent in local storage.
  if (DEVELOPMENT_PROXY_HOSTS.length > 0) return DEVELOPMENT_PROXY_HOSTS;
  const [saved, baseUrl, token] = await Promise.all([bridge.getLocalStorage(STORAGE_KEYS.hosts), bridge.getLocalStorage(STORAGE_KEYS.baseUrl), bridge.getLocalStorage(STORAGE_KEYS.token)]);
  try {
    const hosts = JSON.parse(saved) as HostSettings[];
    if (Array.isArray(hosts) && hosts.every((host) => host.id && host.name && host.baseUrl && host.token)) return hosts;
  } catch { /* migrate the original single-Host settings below */ }
  if (baseUrl && token) return [{ id: "migrated-host", name: "Herden Host", baseUrl, token }];
  return [];
}

async function saveHosts(hosts: HostSettings[]): Promise<void> {
  await bridge.setLocalStorage(STORAGE_KEYS.hosts, JSON.stringify(hosts)); connect(hosts);
}

async function main(): Promise<void> {
  bridge = await waitForEvenAppBridge();
  const created = await bridge.createStartUpPageContainer(new CreateStartUpPageContainer(page()));
  if (created !== 0) {
    // Vite can reload the demo webview while the simulator retains its lens
    // page. Rebuild that page so the fresh document also receives gestures.
    const recovered = DEMO && created === 1 && await bridge.rebuildPageContainer(new RebuildPageContainer(page()));
    if (!recovered) throw new Error(`failed to create the HUD page: ${created}`);
  }
  if (DEMO) {
    const { demoSnapshot } = await import("./demo");
    state.snapshot = demoSnapshot; state.online = true;
    const root = document.getElementById("app");
    if (root) {
      root.textContent = "Herden · offline demo. Generic sample Spaces. Scroll to select, click to read, double click to return.";
      root.style.cssText = "padding:24px;font:15px/1.6 system-ui;color:#416d00;background:#f8faf4";
    }
    bridge.onEvenHubEvent((event) => { const input = event.sysEvent ?? event.textEvent; if (input) void handleSystemEvent(input.eventType ?? OsEventTypeList.CLICK_EVENT); });
    await paint();
    return;
  }
  const hosts = await loadHosts();
  for (const id of parseHiddenSpaces(await bridge.getLocalStorage(STORAGE_KEYS.hiddenSpaces))) hiddenSpaces.add(id);
  panel = new Panel(document.getElementById("app")!, {
    hosts, onSaveHosts: (next) => { void saveHosts(next); },
    onToggleSpace: (id, visible) => { void setSpaceVisible(id, visible); },
  });
  connect(hosts);
  bridge.onEvenHubEvent((event) => { const input = event.sysEvent ?? event.textEvent; if (input) void handleSystemEvent(input.eventType ?? OsEventTypeList.CLICK_EVENT); });
  bridge.onDeviceStatusChanged((status) => { if (status.isWearing === false) for (const client of clients.values()) client.disconnect(); else if (status.isConnected()) for (const client of clients.values()) if (!client.online) client.connect(); });
}

void main();

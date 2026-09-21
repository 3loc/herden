/** Herden HUD — a compact, Space-first view across saved private Hosts. */

import { EvenAppBridge, ImuReportPace, OsEventTypeList, waitForEvenAppBridge } from "@evenrealities/even_hub_sdk";
import { HostService } from "./host-service";
import { isHubOverlayEvent, isTerminalHubExit } from "./hub-event-policy";
import { HardwareTrace } from "./hardware-trace";
import type { EvenHubEvent } from "@evenrealities/even_hub_sdk";
import { compactOutputLines, renderDetail, renderList, wrapOutputRows } from "./hud";
import type { GestureDebug } from "./hud";
import { Panel } from "./panel";
import { parseHiddenSpaces, serialiseHiddenSpaces } from "./selection";
import { toPcmBytes } from "./audio";
import { describeCommand, dictationSubmission } from "./commands";
import type { VoiceCommand } from "./commands";
import { transcribe } from "./stt";
import {
  IDLE_VOICE, captureAudio, startListening,
  voiceFailed, voiceFooter, voiceResolved, voiceTranscribing,
} from "./voice";
import type { VoiceState } from "./voice";
import {
  ATTENTION_TICK_MS, IMU_REPORT_PACE_MS, RESTING_TILT, dueForSleep,
  deferIdleSleep, initialAttention, noteActivity,
  observeSleepingTilt, observeTilt, prepareTiltForSleep, sleepAttention, wakeAttention, wakeProven,
} from "./attention";
import type { ImuSample, SleepReason, TiltState } from "./attention";
import { EMPTY_LISTEN, adaptiveSpeechThreshold, feedFrame } from "./listen";
import type { ListenBuffer } from "./listen";
import { HudModel } from "./hud-model";
import { NativeLensView } from "./lens-view";
import { MicrophoneService } from "./microphone-service";
import { OrderedVoiceQueue, processVoiceUtterance } from "./voice-pipeline";
import type { VoiceSession } from "./voice-pipeline";
import type { Agent, HostSettings } from "./protocol";

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
  return [{ id: "development-host", name: "Development Host", baseUrl: "http://localhost:5173/hud", token: "development-proxy" }];
})();

/**
 * Temporary remote hardware telemetry. Never render this high-rate state on
 * the lens: IMU and audio diagnostics previously flooded the display SDK.
 */
const DEVELOPMENT_TELEMETRY = true;
const gesture: GestureDebug = { count: 0, field: "none" };
/**
 * Temporary hardware telemetry. Reading diagnostics off a 64-column lens is
 * slow and error prone, so while development telemetry is on the app posts its own
 * state to the development server every few seconds. Remove with the flag.
 */
const BEACON_URL = import.meta.env.VITE_HERDEN_HUD_BEACON ?? "/debug";
/** Bumped by hand so telemetry proves which build a device is running. */
const BUILD_MARK = "tilt-x-2";
/** Opt-in capture of every IMU/Hub event; never posts audio samples or text. */
const trace = new URLSearchParams(location.search).get("trace") === "1"
  ? new HardwareTrace({ endpoint: BEACON_URL, session: BUILD_MARK }) : null;
/** What the last transcript parsed to, and what happened when it ran. */
const lastCommand = { heard: "", parsed: "", outcome: "" };
const BEACON_MS = 3_000;

/** Small enough to remain visible in the relay's deliberately short log line. */
const renderStats = {
  requested: "none", committed: "none", requests: 0, writes: 0,
  rebuilds: 0, errors: 0, lastError: "",
};
const deviceStats: {
  connect: string; wearing: boolean | null; battery: number | null; charging: boolean | null;
} = { connect: "unknown", wearing: null, battery: null, charging: null };

function beacon(): void {
  const body = JSON.stringify({
    build: BUILD_MARK,
    error: gesture.error,
    tilt: tilt.last, delta: Number(tilt.delta.toFixed(3)), armed: tilt.armed,
    imuSamples: tilt.samples, wakeProven: tilt.proven === true,
    render: renderStats,
    device: deviceStats,
    mic: micOpen, voice: state.voice.phase, attention: state.attention.phase,
    lastSleepReason, pendingUtterances: voiceQueue.pending,
    heard: lastCommand.heard, parsed: lastCommand.parsed, outcome: lastCommand.outcome,
    audioFrames: audioStats.frames, audioBytes: audioStats.bytes,
    prerollBytes: listen.prerollBytes, utteranceBytes: listen.utteranceBytes,
    utteranceOpen: listen.open,
    speechThreshold: Number(adaptiveSpeechThreshold(listen.energy).toFixed(3)),
    view: state.view, selected: state.selected,
    events: gesture.count, lastField: gesture.field, lastType: gesture.eventType,
    transcript: state.voice.transcript,
    spaces: state.snapshot?.agents.length ?? 0,
  });
  void fetch(BEACON_URL, { method: "POST", body, headers: { "content-type": "application/json" } }).catch(() => {});
}

/** Proof of life for the microphone path; reported remotely, never painted. */
const audioStats = { frames: 0, bytes: 0 };

const startedAt = Date.now();
const state = new HudModel(startedAt);
/** Continuous capture for the current lit session; reset whenever it ends. */
let listen: ListenBuffer = EMPTY_LISTEN;
/** Capture intent for the current lit session; hardware transitions are serialised. */
let micOpen = false;
/** Ordered work and invalidation for the current continuous-mic session. */
const voiceQueue = new OrderedVoiceQueue();
type SleepTrigger = SleepReason | "foreground-exit" | "long-press" | "voice-close";
let lastSleepReason: SleepTrigger | "" = "";
/** Rolling head orientation; survives sleep, since it is what ends sleep. */
let tilt: TiltState = RESTING_TILT;
/** Projected `${hostId}:${remoteId}` ids the wearer chose to keep off the lens. */
const hiddenSpaces = new Set<string>();
const hostService = new HostService({
  onChange: refreshProjection,
  onError: (message) => panel?.setConnection(state.online, ` · ${message}`),
});
let bridge: EvenAppBridge;
let bridgeReady = false;
let panel: Panel | null = null;
let lens: NativeLensView | null = null;
let microphone: MicrophoneService;
let unsubscribeHub: (() => void) | null = null;
let unsubscribeDevice: (() => void) | null = null;
let detailRefreshInFlight = false;
function selectedAgent(): Agent | null { return state.selectedAgent(); }

function paint(): void {
  if (state.attention.phase === "asleep") return; // `blankLens` owns a dark lens.
  const snapshot = state.snapshot; const agent = state.view === "detail" ? selectedAgent() : null;
  const output = state.outputLoading ? ["reading output..."] : state.output;
  const empty = (state.roster?.agents.length ?? 0) > 0 ? "no Spaces selected" : "no agents";
  const status = voiceFooter(state.voice, micOpen);
  const content = agent ? renderDetail(agent, output, state.outputOffset, state.online, state.selected + 1, [], status)
    : snapshot ? renderList(snapshot, state.selected, state.online, empty, undefined, [], status) : `connecting...\n${status}`;
  renderStats.requested = "view";
  renderStats.requests += 1;
  lens?.show(content);
}

function refreshProjection(): void {
  state.refresh(hostService.snapshots, hostService.onlineHosts, hiddenSpaces);
  // The panel keeps showing every Space, including the hidden ones.
  if (panel && state.roster) panel.render(state.roster, state.hosts, hostService.onlineHosts, hiddenSpaces);
  else panel?.setHosts(state.hosts, hostService.onlineHosts);
  if (state.view === "list") paint();
}

/** A checkbox in the panel takes effect on the lens without a reconnect. */
async function setSpaceVisible(id: string, visible: boolean): Promise<void> {
  if (visible) hiddenSpaces.delete(id); else hiddenSpaces.add(id);
  refreshProjection();
  await bridge.setLocalStorage(STORAGE_KEYS.hiddenSpaces, serialiseHiddenSpaces(hiddenSpaces));
}

function connect(hosts: HostSettings[]): void {
  state.hosts = hosts;
  hostService.connect(hosts);
}

/**
 * Every field `EvenHubEvent` declares, so a click arriving in an envelope the
 * handler never read appears in remote telemetry instead of being dropped.
 */
function readEnvelope(event: EvenHubEvent): { field: string; eventType?: number; dispatch: boolean } {
  if (event.sysEvent) return { field: "sysEvent", eventType: event.sysEvent.eventType, dispatch: true };
  if (event.textEvent) return { field: "textEvent", eventType: event.textEvent.eventType, dispatch: true };
  if (event.listEvent) return { field: "listEvent", eventType: event.listEvent.eventType, dispatch: true };
  if (event.menuItemClickEvent) return { field: "menuEvent", eventType: OsEventTypeList.CLICK_EVENT, dispatch: true };
  // Handled before this point; kept so the field list stays exhaustive.
  if (event.audioEvent) return { field: "audioEvent", dispatch: false };
  const raw = event.jsonData;
  if (raw) return { field: "jsonData", eventType: OsEventTypeList.fromJson(raw.eventType ?? raw.Event_Type ?? raw.type), dispatch: true };
  return { field: "empty", dispatch: false };
}

function surfaceGestureError(error: unknown): void {
  gesture.error = error instanceof Error ? error.message : String(error);
  if (DEVELOPMENT_TELEMETRY) beacon();
}

function handleHubEvent(event: EvenHubEvent): void {
  // Microphone frames arrive in their thousands: never repaint per frame, and
  // never let one bump the gesture diagnostic's event counter.
  if (event.audioEvent) {
    const pcm = toPcmBytes((event.audioEvent as { audioPcm?: unknown }).audioPcm);
    trace?.audioFrame(pcm.length);
    audioStats.frames += 1;
    audioStats.bytes += pcm.length;
    if (pcm.length === 0 || !micOpen) return;
    const heard = feedFrame(listen, pcm);
    listen = heard.buffer;
    state.voice = captureAudio(state.voice, pcm.length);
    const utterance = heard.utterance;
    if (utterance) voiceQueue.enqueue(utterance, handleUtterance);
    return;
  }
  // IMU reports also arrive several times a second, and are not gestures.
  if (event.sysEvent?.eventType === OsEventTypeList.IMU_DATA_REPORT) {
    void handleImu(event.sysEvent.imuData ?? {}).catch(surfaceGestureError);
    return;
  }
  const envelope = readEnvelope(event);
  gesture.count += 1;
  gesture.field = envelope.field;
  gesture.eventType = envelope.eventType;
  gesture.error = undefined;
  trace?.record("hub", envelope.field, envelope.eventType ?? null);
  const handled = envelope.dispatch
    ? handleSystemEvent(envelope.eventType ?? OsEventTypeList.CLICK_EVENT)
    : Promise.resolve();
  void handled.catch(surfaceGestureError);
}

async function handleSystemEvent(eventType: OsEventTypeList): Promise<void> {
  // An IMU report reaching here arrived in an envelope `handleHubEvent` did
  // not expect. It is not a gesture: it must never defer sleep or wake the
  // lens, or the HUD would stay lit forever on its own sample stream.
  if (eventType === OsEventTypeList.IMU_DATA_REPORT) return;
  // A terminal exit closes capture; foreground enter/exit only describes the
  // Hub's contextual-menu overlay and must not kill the resident session.
  if (isTerminalHubExit(eventType)) {
    await goToSleep("foreground-exit");
    return;
  }
  if (isHubOverlayEvent(eventType)) return;
  // Hub foreground, touch, and scroll events are not head-up gestures. Only
  // the confirmed IMU transition in handleImu may wake a dark lens.
  if (state.attention.phase === "asleep") {
    return;
  }
  noteWearerActivity();
  switch (eventType) {
    case OsEventTypeList.CLICK_EVENT:
      if (state.view === "list" && selectedAgent()) { await openSelectedOutput(); return; }
      return;
    case OsEventTypeList.DOUBLE_CLICK_EVENT:
      showList();
      paint();
      return;
    // Long press is a manual way to close a lit session.
    case OsEventTypeList.LONG_PRESS_EVENT:
      await goToSleep("long-press");
      return;
    case OsEventTypeList.LONG_PRESS_RELEASE_EVENT:
      return;
    case OsEventTypeList.SCROLL_TOP_EVENT:
      state.scroll(-1);
      paint();
      return;
    case OsEventTypeList.SCROLL_BOTTOM_EVENT:
      state.scroll(1);
      paint();
      return;
    default: return;
  }
}

function showList(): void {
  state.showList();
}

function reason(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function noteWearerActivity(): void {
  state.attention = noteActivity(state.attention, Date.now());
}

/** Clear the resident native text container without tearing down the page. */
function blankLens(): void {
  renderStats.requested = "blank";
  renderStats.requests += 1;
  lens?.show("");
}

/**
 * The lens goes dark and the microphone shuts together. Neither operation is
 * allowed to wait for the other SDK path.
 * The app stays resident — never `shutDownPageContainer` — because it is the
 * only thing left that can wake itself on a tilt.
 */
async function goToSleep(reason: SleepTrigger): Promise<void> {
  const { state: next, changed } = sleepAttention(state.attention, Date.now());
  state.attention = next;
  if (!changed) return;
  lastSleepReason = reason;
  tilt = prepareTiltForSleep(tilt);
  trace?.record("sleep", reason, tilt.last?.y ?? null, tilt.baseline, micOpen);
  state.invalidateOutput();
  const stopping = stopMic();
  blankLens();
  await stopping;
}

/** Wake rendering and microphone startup independently on the same tilt. */
async function wakeUp(): Promise<void> {
  const { state: next, changed } = wakeAttention(state.attention, Date.now());
  state.attention = next;
  if (!changed) return;
  trace?.record("wake", tilt.last?.y ?? null, tilt.baseline, tilt.delta);
  // startMic publishes the first lit frame with MIC ON. Painting here as well
  // sent two near-identical SDK updates during every wake.
  await startMic();
}

async function attentionTick(): Promise<void> {
  const due = dueForSleep(state.attention, Date.now(), undefined, undefined, wakeProven(tilt));
  const reason = deferIdleSleep(due, listen.open || voiceQueue.pending > 0);
  if (!reason) return;
  await goToSleep(reason);
}

/**
 * Measured head pitch on the G2's X axis. The IMU stays on while the lens is
 * dark: it is the only thing that can end sleep.
 */
async function handleImu(sample: ImuSample): Promise<void> {
  const observed = state.attention.phase === "asleep"
    ? observeSleepingTilt(tilt, sample)
    : observeTilt(tilt, sample);
  tilt = observed.state;
  trace?.record("imu", sample.x ?? null, sample.y ?? null, sample.z ?? null,
    tilt.baseline, tilt.delta, tilt.armed, state.attention.phase === "awake", observed.wake);
  // `isWearing` is advisory only. Live G2 sessions can report false while the
  // glasses are being worn, so it must never gate the only wake path.
  if (observed.wake && state.attention.phase === "asleep") {
    await wakeUp();
  }
}

/** `ImuReportPace` is the report period in milliseconds on the wire. */
async function enableTilt(): Promise<void> {
  try {
    const enabled = await bridge.imuControl(true, IMU_REPORT_PACE_MS as ImuReportPace);
    trace?.record("imu-on", enabled);
    if (!enabled) {
      gesture.error = "imu reporting refused";
    }
  } catch (error) {
    gesture.error = `imu: ${reason(error)}`;
    trace?.record("imu-error", reason(error).slice(0, 80));
  }
}

function setVoice(next: VoiceState): void {
  state.voice = next;
  paint();
}

/**
 * Closing must never throw and must leave no way back in: a stuck-open mic
 * outlives the app. Every sleep, every foreground exit and every error path
 * goes through here.
 */
async function stopMic(): Promise<void> {
  micOpen = false;
  voiceQueue.stop();
  listen = EMPTY_LISTEN;
  state.voice = IDLE_VOICE;
  try { await microphone.stop(); trace?.record("mic-off"); } catch (error) {
    trace?.record("mic-error", reason(error).slice(0, 80));
    surfaceGestureError(new Error(`mic stop: ${reason(error)}`));
  }
}

/**
 * Open the glasses mic for the whole lit session. Continuous capture is the
 * fix for the lost first syllable: `audioControl(true)` takes time to take
 * effect, so the microphone must already be open — and a pre-roll buffer
 * already filling — before the wearer starts to speak.
 */
async function startMic(): Promise<void> {
  if (micOpen) return;
  voiceQueue.start();
  listen = EMPTY_LISTEN;
  micOpen = true;
  setVoice(startListening(IDLE_VOICE).state);
  try {
    await microphone.start();
    trace?.record("mic-on");
  } catch (error) {
    trace?.record("mic-error", reason(error).slice(0, 80));
    if (!micOpen) return; // A concurrent sleep already owns shutdown.
    await stopMic();
    setVoice(voiceFailed(state.voice, reason(error)));
  }
}

/**
 * One endpointed utterance: transcribe it and run it while capture continues.
 * A segment with no speech in it is never sent — parakeet hallucinates words
 * onto silence.
 */
async function handleUtterance(frames: Uint8Array[], session: VoiceSession): Promise<void> {
  await processVoiceUtterance(frames, {
    session,
    transcribe: (wav, signal) => transcribe(wav, { signal }),
    onTranscribing: () => setVoice(voiceTranscribing(state.voice)),
    onResolved: (text, command) => {
      lastCommand.heard = text;
      lastCommand.parsed = describeCommand(command);
      lastCommand.outcome = command.type === "unknown" ? "ignored" : "running";
      setVoice(voiceResolved(state.voice, text, describeCommand(command)));
    },
    onFailed: (message) => setVoice(voiceFailed(state.voice, message)),
    execute: (command, activeSession) => runVoiceCommand(command, activeSession),
    noteActivity: noteWearerActivity,
  });
}

/**
 * Spoken navigation runs the same transitions as the click gestures, by the
 * position the wearer can read on the lens. Dictation uses one atomic Host
 * command to type and submit when endpointing closes the spoken phrase.
 */
async function runVoiceCommand(command: VoiceCommand, session: VoiceSession): Promise<void> {
  if (!session.isCurrent()) return;
  switch (command.type) {
    case "open": {
      const agents = state.snapshot?.agents ?? [];
      if (!state.selectPosition(command.position)) {
        lastCommand.outcome = `no Space ${command.position} of ${agents.length}`;
        setVoice(voiceFailed(state.voice, `no Space ${command.position} on the lens`));
        return;
      }
      lastCommand.outcome = `opening ${command.position}`;
      await openSelectedOutput(() => session.isCurrent());
      if (!session.isCurrent()) return;
      lastCommand.outcome = `opened ${command.position} view=${state.view}`;
      return;
    }
    case "back":
      showList();
      paint();
      return;
    case "page":
      state.page(command.direction === "up" ? -1 : 1);
      paint();
      return;
    case "close":
      lastCommand.outcome = "closed by voice";
      await goToSleep("voice-close");
      return;
    case "dictate": {
      const agent = state.view === "detail" ? selectedAgent() : null;
      if (!agent?.hostId || !agent.remoteId) {
        lastCommand.outcome = "open a Space first";
        setVoice(voiceFailed(state.voice, "open a Space first"));
        return;
      }
      const delivered = await hostService.sendCommand(agent.hostId, dictationSubmission(agent.remoteId, command.text));
      if (!session.isCurrent()) return;
      lastCommand.outcome = delivered ? "dictation submitted" : "dictation not delivered";
      if (!delivered) setVoice(voiceFailed(state.voice, "dictation not delivered"));
      else void refreshSelectedOutput();
      return;
    }
    case "unknown":
      return;
  }
}

async function openSelectedOutput(resultIsCurrent: () => boolean = () => true): Promise<void> {
  const agent = selectedAgent();
  const request = state.beginOutput();
  const isCurrent = () => request === state.outputRequest && resultIsCurrent() && selectedAgent()?.id === agent?.id;
  if (DEMO && agent) {
    const { demoOutput } = await import("./demo");
    if (!isCurrent()) return;
    state.setOutput(wrapOutputRows(demoOutput));
    state.outputLoading = false;
    paint();
    return;
  }
  if (!agent?.hostId || !agent.remoteId) { state.outputLoading = false; return; }
  try {
    const output = await hostService.readOutput(agent.hostId, agent.remoteId);
    if (!isCurrent()) return;
    state.setOutput(wrapOutputRows(compactOutputLines(output.text)));
  } catch (error) {
    if (!isCurrent()) return;
    // A Host error message can carry newlines; keep it to readable lens rows.
    state.setOutput(wrapOutputRows(compactOutputLines(error instanceof Error ? error.message : "Output is unavailable.")));
  } finally {
    if (request === state.outputRequest) {
      state.outputLoading = false;
      paint();
    }
  }
}

/** Keep a working Agent's newest terminal lines visible without resetting idle. */
async function refreshSelectedOutput(): Promise<void> {
  if (state.attention.phase !== "awake" || state.view !== "detail" || state.outputLoading || detailRefreshInFlight) return;
  const agent = selectedAgent();
  if (!agent?.hostId || !agent.remoteId) return;
  const request = state.outputRequest;
  detailRefreshInFlight = true;
  try {
    const result = await hostService.readOutput(agent.hostId, agent.remoteId);
    if (request !== state.outputRequest || state.view !== "detail" || selectedAgent()?.id !== agent.id) return;
    if (state.updateOutput(wrapOutputRows(compactOutputLines(result.text)))) paint();
  } catch { /* Retain the last readable frame; the next refresh may succeed. */ }
  finally { detailRefreshInFlight = false; }
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

function cleanup(): void {
  unsubscribeHub?.();
  unsubscribeHub = null;
  unsubscribeDevice?.();
  unsubscribeDevice = null;
  voiceQueue.stop();
  micOpen = false;
  hostService.disconnect();
  if (!bridgeReady) return;
  void microphone.stop().catch(() => {});
  void bridge.imuControl(false).catch(() => {});
}

async function main(): Promise<void> {
  bridge = await waitForEvenAppBridge();
  bridgeReady = true;
  trace?.record("bridge-ready");
  microphone = new MicrophoneService(bridge);
  lens = new NativeLensView(bridge, {
    onWrite: () => { renderStats.writes += 1; },
    onRebuild: () => { renderStats.rebuilds += 1; },
    onError: (error) => {
      renderStats.errors += 1;
      renderStats.lastError = reason(error);
      gesture.error = `render: ${renderStats.lastError}`;
      if (DEVELOPMENT_TELEMETRY) beacon();
    },
    onRendered: (content) => {
      renderStats.committed = content.length === 0 ? "blank" : "view";
    },
  });
  await lens.initialize();
  // A development reload can inherit microphone capture from the previous
  // WebView. The normal boot contract is dark and silent until a tilt.
  try { await microphone.stop(); } catch { /* already closed */ }
  if (DEMO) {
    const { demoSnapshot } = await import("./demo");
    state.attention = initialAttention(Date.now());
    state.snapshot = demoSnapshot; state.online = true;
    const root = document.getElementById("app");
    if (root) {
      root.textContent = "Herden · offline demo. Generic sample Spaces. Scroll to select, click to read, double click to return.";
      root.style.cssText = "padding:24px;font:15px/1.6 system-ui;color:#416d00;background:#f8faf4";
    }
    unsubscribeHub = bridge.onEvenHubEvent(handleHubEvent);
    paint();
    return;
  }
  const hosts = await loadHosts();
  for (const id of parseHiddenSpaces(await bridge.getLocalStorage(STORAGE_KEYS.hiddenSpaces))) hiddenSpaces.add(id);
  panel = new Panel(document.getElementById("app")!, {
    hosts, onSaveHosts: (next) => { void saveHosts(next); },
    onToggleSpace: (id, visible) => { void setSpaceVisible(id, visible); },
  });
  connect(hosts);
  unsubscribeHub = bridge.onEvenHubEvent(handleHubEvent);
  trace?.record("hub-subscribed");
  await enableTilt();
  setInterval(() => { void attentionTick(); }, ATTENTION_TICK_MS);
  setInterval(() => { void refreshSelectedOutput(); }, 3_000);
  if (DEVELOPMENT_TELEMETRY) setInterval(beacon, BEACON_MS);
  if (trace) setInterval(() => { trace.audioSummary(); void trace.flush(); }, 1_000);
  unsubscribeDevice = bridge.onDeviceStatusChanged((status) => {
    deviceStats.connect = status.connectType;
    deviceStats.wearing = status.isWearing ?? null;
    deviceStats.battery = status.batteryLevel ?? null;
    deviceStats.charging = status.isCharging ?? null;
    trace?.record("device", status.connectType, status.isWearing ?? null,
      status.batteryLevel ?? null, status.isCharging ?? null);
    if (DEVELOPMENT_TELEMETRY) beacon();
    // Connection status is reliable enough to restore Host links. Wear status
    // is retained for telemetry but is not used for lifecycle decisions.
    if (status.isConnected()) {
      hostService.reconnectOffline();
    }
  });
}

window.addEventListener("beforeunload", cleanup);
void main().catch((error) => {
  const message = `HUD startup failed: ${reason(error)}`;
  gesture.error = message;
  if (DEVELOPMENT_TELEMETRY) beacon();
  const root = document.getElementById("app");
  if (root) root.textContent = `${message}. Check the phone connection, then reopen the app.`;
  cleanup();
});

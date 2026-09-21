import { OsEventTypeList } from "@evenrealities/even_hub_sdk";

/** Contextual-menu foreground events are overlays, not app termination. */
export function isTerminalHubExit(eventType: OsEventTypeList): boolean {
  return eventType === OsEventTypeList.ABNORMAL_EXIT_EVENT
    || eventType === OsEventTypeList.SYSTEM_EXIT_EVENT;
}

export function isHubOverlayEvent(eventType: OsEventTypeList): boolean {
  return eventType === OsEventTypeList.FOREGROUND_ENTER_EVENT
    || eventType === OsEventTypeList.FOREGROUND_EXIT_EVENT;
}

/** Even review requires root double-click to use the system exit dialog. */
export function doubleClickAction(view: "list" | "detail"): "exit" | "back" {
  return view === "list" ? "exit" : "back";
}

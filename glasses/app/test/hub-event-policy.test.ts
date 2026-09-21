import assert from "node:assert/strict";
import { test } from "node:test";
import { OsEventTypeList } from "@evenrealities/even_hub_sdk";
import { doubleClickAction, isHubOverlayEvent, isTerminalHubExit } from "../src/hub-event-policy.ts";

test("contextual-menu foreground events do not terminate a voice session", () => {
  for (const event of [OsEventTypeList.FOREGROUND_ENTER_EVENT, OsEventTypeList.FOREGROUND_EXIT_EVENT]) {
    assert.equal(isHubOverlayEvent(event), true);
    assert.equal(isTerminalHubExit(event), false);
  }
});

test("actual exit events close the voice session", () => {
  for (const event of [OsEventTypeList.ABNORMAL_EXIT_EVENT, OsEventTypeList.SYSTEM_EXIT_EVENT]) {
    assert.equal(isTerminalHubExit(event), true);
    assert.equal(isHubOverlayEvent(event), false);
  }
  assert.equal(isTerminalHubExit(OsEventTypeList.IMU_DATA_REPORT), false);
});

test("double click goes back inside a Space and opens the system exit dialog at root", () => {
  assert.equal(doubleClickAction("detail"), "back");
  assert.equal(doubleClickAction("list"), "exit");
});

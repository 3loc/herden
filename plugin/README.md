# Herden notification extension

This Herden Host extension sends end-to-end encrypted Agent notifications and
Live Activity updates. Pairing is not implemented here: the native Host runtime
owns that flow through `herden pair`.

The Host and QR pairing work without this extension. After public Host releases
are available, you can explicitly request notifications during installation
(Git and npm are required):

```sh
curl -fsSL https://raw.githubusercontent.com/3loc/herden/main/install.sh | HERDEN_INSTALL_NOTIFICATIONS=1 sh
```

To install it separately from a checkout:

```sh
herden plugin link "$(pwd)/plugin"
```

The manifest ID is `herden`. It registers two independent
`pane.agent_status_changed` hooks:

- `src/notify-hook.js` sends Blocked and Done alerts according to each
  device's preferences.
- `src/activity-hook.js` updates or ends the device's Live Activity.

Both hooks re-read current Host state after a debounce. A stale or flapping
event therefore cannot notify on its own. Per-Pane delivery state prevents
duplicate alerts, while HTTP 410 responses prune expired APNs tokens.

## Privacy boundary

Every device has a distinct 32-byte Notification Key. The Host encrypts the
payload with AES-256-GCM before sending it to the relay. The relay receives:

- an APNs device or Live Activity token;
- the sandbox/production environment;
- delivery metadata such as priority and collapse ID;
- an opaque encrypted envelope.

It cannot read the Agent name, status, project, terminal title, or Pane ID.
The iOS notification service extension decrypts and renders alerts on-device.

The envelope keeps the established `HERDR-NOTIFY:1` and `HERDR-ACTIVITY:1`
additional-authenticated-data labels for wire compatibility. The Host plugin
environment also retains upstream `HERDR_PLUGIN_*` names. These are protocol
identifiers, not separate product commands.

## Host files

The iOS app atomically maintains two files in the extension's config directory,
resolved with `herden plugin config-dir herden`:

- `notifications.json` — versioned per-device tokens, keys, preferences, and
  optional Live Activity registrations;
- `notify.json` — relay URL and debounce/retry settings.

The registration format is additive: unknown fields survive app and hook
rewrites. Missing, malformed, foreign-version, or incomplete entries fail
closed and send nothing.

The default relay is `https://herden-apns.austrheim.ca7.fm`. Self-builders can choose
another HTTPS relay in the app settings.

## Develop and test

Node 20 or newer is required for the extension. It has no framework runtime;
`npm ci` installs only development dependencies.

```sh
cd plugin
npm ci
npm test
```

The vectors in `test-vectors/` are consumed by both Node and Swift tests so
encryption, Pairing Code compatibility, and Live Activity payloads cannot drift
between the Host and iOS implementations.

See [ADR 0008](../docs/adr/0008-agent-notifications-via-plugin-hooks-and-push-relay.md) and the
[Live Activity contract](../docs/agents/live-activity-contract.md) for the full
wire and lifecycle design.

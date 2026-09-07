# Privacy Policy

_Last updated: August 22, 2026._

Herden is a native iOS console for the Herden Host. It connects to
machines you control ("Hosts") over SSH. Herden has no user accounts,
advertising, analytics, or tracking. Your SSH credentials, terminal output,
prompts, files, and live agent sessions do not pass through a service operated
by Herden's developer.

Agent Notifications use the limited-purpose Push Relay described below.

## Data stored on your device and Hosts

- **SSH credentials.** The Device Key's private half is generated on your
  device, remains in the iOS Keychain, and never leaves the device. Host
  fingerprints are stored locally. A saved Host password is also stored in the
  Keychain.
- **Notification Keys.** A separate Notification Key is generated on your
  device for each Host. It is stored in the shared Keychain and mirrored in the
  app's shared container so Live Activities can be decrypted while the device
  is locked. The mirror is protected until first unlock and excluded from
  backups. Herden copies the key over SSH to the corresponding Host so the
  notification plugin can encrypt notifications. The Push Relay never receives this
  key.
- **Host list and settings.** Your Hosts and Herden settings are stored locally.
  Each Host stores its own notification registration and delivery preferences.
- **Live agent activity.** Terminal output, prompts, and pane contents travel
  only over the direct SSH connection between your device and your Host. The
  limited notification data described below takes a separate route.

## Agent Notifications and the Push Relay

Agent Notifications can tell you when an agent is blocked or done while Herden
is backgrounded or closed. Apple Push Notification service (APNs) requires an
Apple credential authorized for this app's bundle ID, so the App Store build
uses an open-source push relay hosted by the developer at
`https://herden-apns.austrheim.ca7.fm`.

The relay has no accounts, database, durable queue, retry queue, or message
history. A Host encrypts the notification details with its Notification Key,
then the relay signs and forwards the push request to APNs without receiving
the key needed to decrypt those details.

### Data processed by the Push Relay

For every notification request, the relay processes:

- the Apple push token needed to address your device;
- the encrypted notification envelope (ciphertext);
- the Host's source IP address;
- request timing, frequency, and size; and
- the APNs environment and limited delivery-routing values.

For a Live Activity update, APNs must also receive the following values in
cleartext so iOS can update or end the activity without launching Herden:

- aggregate counts of agents that are working, blocked, or done;
- the update or end event, delivery priority, and event timestamp; and
- when present, stale and dismissal timestamps.

These values describe the activity update but do not identify an individual
agent. Project names, task titles, agent types and names, Host names, pane IDs,
and per-agent details remain inside the encrypted envelope. The relay and APNs
do not receive the Notification Key used to decrypt that envelope.

If a notification cannot be decrypted, Herden shows a generic fallback instead
of displaying unverified content.

### Purpose, retention, and service providers

The 3loc-hosted relay uses this data only to validate requests, limit
abuse, and deliver notifications to APNs. It does not use the data for
advertising, analytics, tracking, profiling, or sale.

The relay code does not write device tokens, notification bodies, ciphertext,
or request history to application-managed durable storage. Source IP addresses
and Apple push tokens are used in volatile, per-instance memory for one-minute
rate-limit windows. This memory is not a durable user record and is discarded
when the relay process is restarted.

The relay is hosted inside the 3loc homelab and is reachable only through its
private Headscale tailnet. Notifications are delivered by Apple APNs, which may
process network and delivery metadata under its published privacy terms. Any
provider processing data on Herden's behalf is required to protect it
consistently with this policy and applicable law. Herden uses providers only
for infrastructure and push delivery.

- [Apple Privacy Policy](https://www.apple.com/legal/privacy/)

## Your choices and deletion

Agent Notifications and Live Activities are optional.

- You can decline or revoke notification and Live Activity permissions in iOS
  Settings.
- Removing a Host's Notification Registration deletes this device's token and
  Notification Key from that Host, then removes the local per-Host Notification
  Key record.
- Removing a Host from Herden deletes its local Host record and any saved Host
  password.

Herden has no account or user-content database, so there is normally no
server-side profile or content for the operator to retrieve or
delete. For a privacy or deletion request, open a content-free issue in the
[project issue tracker](https://github.com/3loc/herden/issues/new)
and ask for a private follow-up channel. Do not put credentials, tokens, Host
details, or other sensitive information in a public issue.

## Custom relay URL

The notification plugin and Herden accept a custom push relay base URL, so you can run
your own relay instead of the 3loc-hosted one. The relay source is public
so its behavior can be inspected.

A custom relay only works with an app you build and sign yourself. It must use
APNs credentials authorized for that app's bundle ID. Only the 3loc-hosted
relay is configured to deliver notifications to this App Store or TestFlight
build.

## Contact

For questions about this policy, use the
[project issue tracker](https://github.com/3loc/herden/issues) and do
not include sensitive information.

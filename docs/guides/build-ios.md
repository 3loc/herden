# Build Herden for iOS

Herden builds on a Mac with Xcode 26 or newer. Install Xcode from the Mac App
Store, open it once, and let it install the iOS platform tools. In Xcode
Settings, confirm an iOS Simulator runtime is installed. The Simulator needs
no paid Apple developer membership.

The full physical-device build includes an App Group shared with the Share
Extension. Use an Apple Developer Program team with that capability. A free
Personal Team is not a supported signing path for the full app. See
[Apple's account and capability guidance](https://developer.apple.com/help/account/basics/about-your-developer-account/).

The Mac builds the app; the Host runs your Agents. These may be different
computers. Tailscale connects the installed iPhone app to the Host and does
not replace Xcode's device-pairing process.

## Run in the simulator

```bash
git clone https://github.com/3loc/herden.git
cd herden
make sim
```

`make sim` builds the `Herden` scheme, boots the `iPhone 17` simulator, installs
`Herden.app`, and launches it. Choose another installed simulator with, for
example, `make sim SIM='iPhone 17 Pro'`.

Run the complete Swift and HerdenSSH test suites with:

```bash
make test
```

## Install on a physical iPhone

In **Xcode → Settings → Apple Accounts**, sign in to the account that owns your
development team. You do not need to sign in as the person who owns the phone.
One authorised team can build onto multiple registered devices.

The committed signing values belong to 3LOC. Before building your own signed
copy, install XcodeGen and replace the following values with identifiers owned
by your Apple developer team:

| File | Setting | Example |
| --- | --- | --- |
| `project.yml` | `DEVELOPMENT_TEAM` | your ten-character Apple team ID |
| `project.yml` | app `PRODUCT_BUNDLE_IDENTIFIER` | `com.example.herden` |
| `project.yml` | Share Extension `PRODUCT_BUNDLE_IDENTIFIER` | `com.example.herden.share` |
| `project.yml` | tests `PRODUCT_BUNDLE_IDENTIFIER` | `com.example.herden.tests` |
| `project.yml` | both application-group entries | `group.com.example.herden` |
| `Sources/Herden/Support/SharedAppStorage.swift` | `appGroup` | the same application group |
| `Sources/HerdenNotificationCore/NotificationKeyStore.swift` | `sharedAccessGroup` | the same application group |

Install XcodeGen with Homebrew, regenerate the project, then connect and trust
the iPhone:

```bash
brew install xcodegen
make generate
open Herden.xcodeproj
```

In Xcode, select both **Herden** and **HerdenShareExtension** in turn. Under
**Signing & Capabilities**, confirm the same Team and automatic signing, and
check that the same App Group is enabled. Resolve any signing error there
before using the command line. Do not remove the App Group to silence a signing
error: sharing Hosts and credentials with the extension depends on it. See
[Apple's App Group setup](https://developer.apple.com/documentation/xcode/configuring-app-groups).

Connect the iPhone by USB. Unlock it, accept **Trust This Computer**, and open
Xcode's device manager (Window → Devices and Simulators, or Manage Devices in
the run destination picker). Allow Xcode to finish preparing the device.

On the phone, enable **Settings → Privacy & Security → Developer Mode**, restart,
and confirm when prompted. If the setting is absent, pair with Xcode first.
See [Apple's Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

Choose the phone as the run destination and press Run once. For subsequent
builds from Terminal:

```sh
make install APP_ID=com.example.herden
```

`APP_ID` must match the app bundle identifier you chose; it tells the launch
command which installed app to open. `make install` selects the first physical
device reported by `devicectl`. For multiple phones, list and select one:

```bash
xcrun devicectl list devices
make install DEVICE=00000000-0000-0000-0000-000000000000 APP_ID=com.example.herden
```

Xcode automatic signing creates or updates the development provisioning
profiles. If a remote SSH shell cannot access the Apple account in the Mac's
login keychain, run the same command from the logged-in Terminal application.

If Xcode stays on “Updating provisioning” and times out, check that both targets
use your team, the device is registered, and the App Group belongs to that team.
Use Xcode's account settings to download manual profiles if requested. Keep
the phone unlocked and complete any account or keychain prompts on the Mac.

## Deploy over Wi-Fi

Complete one USB pairing and successful install first. Put the Mac and iPhone
on the same Wi-Fi, keep Developer Mode enabled, and confirm the phone remains
available in Xcode's device manager after unplugging it. Enable **Connect via
network** if that control is present in your Xcode version. Then use the same
`make install DEVICE=... APP_ID=...` command. See
[Apple's wireless deployment guide](https://help.apple.com/xcode/mac/current/en.lproj/dev3e2f4ee6d.html).

After installation, Herden itself connects over SSH/Tailscale even when the
phone is away from the Mac. Follow [Host pairing](install-host.md#start-and-pair).

## Simulator with your own bundle ID

After changing signing identifiers, also pass `APP_ID` to the Simulator target:

```sh
make sim APP_ID=com.example.herden
```

## Work on the Xcode project

`project.yml` is the source of truth. Run `make generate` after changing target,
signing, package, or source membership settings, and commit the regenerated
`Herden.xcodeproj` with the YAML change.

A focused Swift suite can be run directly on the Mac:

```bash
xcodebuild test \
  -project Herden.xcodeproj \
  -scheme Herden \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:HerdenTests/PairingCodeTests
```

Changes under `Packages/HerdenSSH` use the separate package test plan:

```bash
scripts/run-herdenssh-package-tests.sh \
  'platform=iOS Simulator,name=iPhone 17'
```

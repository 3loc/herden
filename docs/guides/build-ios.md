# Build Herden for iOS

Herden is a native iPhone app. Build it on a Mac with Xcode 26 or newer. The
Mac that builds the app and the Host that runs your coding agents may be
different computers.

## Choose a build route

| Goal | Apple membership | What to run |
| --- | --- | --- |
| Try the interface in Simulator | None | `make sim` |
| Install the complete app on an iPhone | Apple Developer Program team | Configure signing, then run from Xcode once |
| Repeat installs on the same iPhone | Same configured team | `make install` |
| Publish through TestFlight | Maintainer access to App Store Connect | Follow the release guide, not this guide |

A free Personal Team is not a supported path for the complete app. Herden and
its Share Extension use an App Group to share Hosts and credentials, and the
group must belong to the signing team.

## Prepare the Mac

1. Install Xcode from the Mac App Store.
2. Open Xcode once and allow it to install the iOS platform components.
3. In **Xcode → Settings → Platforms**, install an iOS Simulator runtime.
4. Point command-line tools at that Xcode installation when necessary:

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   xcodebuild -version
   ```

5. Clone Herden and inspect the available commands:

   ```sh
   git clone https://github.com/3loc/herden.git
   cd herden
   make help
   ```

The repository contains the generated Xcode project and reviewed native SSH
artifacts. XcodeGen is not required merely to run the committed project.

## Run in Simulator

List the Simulator devices installed on the Mac:

```sh
xcrun simctl list devices available
```

Then build and launch Herden. The default device is `iPhone 17`:

```sh
make sim
```

Choose another installed device by its exact name:

```sh
make sim SIM='iPhone 17 Pro'
```

The Simulator proves the interface and local behaviour. Pairing to a real Host
is intended for a physical iPhone because it depends on the device's network,
camera and Keychain identity.

## Install on a physical iPhone

There are four stages: choose identifiers, regenerate the project, prepare the
phone, then perform the first signed build in Xcode.

### 1. Choose identifiers you own

Pick a reverse-DNS identifier controlled by your Apple development team. This
guide uses `com.example.herden`; replace `example` with your own value.

Use the following related identifiers consistently:

| Purpose | Example |
| --- | --- |
| App | `com.example.herden` |
| Share Extension | `com.example.herden.share` |
| Test bundle | `com.example.herden.tests` |
| App Group | `group.com.example.herden` |

### 2. Configure the project for your Apple team

Install XcodeGen:

```sh
brew install xcodegen
```

Create the ignored local signing file with your ten-character Apple team ID:

```sh
printf 'DEVELOPMENT_TEAM = ABCDE12345\n' > .herden.local.mk
```

Replace `ABCDE12345` with your own team ID. Then edit `project.yml`:

1. Replace the three `PRODUCT_BUNDLE_IDENTIFIER` values with the app, Share
   Extension and test identifiers above.
2. Replace `group.ltd.3loc.herden.shared` in both targets with your App Group.

Then update the two runtime constants to the same App Group:

- `Sources/Herden/Support/SharedAppStorage.swift`: `appGroup`
- `Sources/HerdenNotificationCore/NotificationKeyStore.swift`:
  `sharedAccessGroup`

Regenerate the Xcode project and review the result:

```sh
make generate
git diff -- project.yml Herden.xcodeproj \
  Sources/Herden/Support/SharedAppStorage.swift \
  Sources/HerdenNotificationCore/NotificationKeyStore.swift
```

The local signing file is deliberately ignored so your team ID never enters
repository history. `project.yml` is the source of truth. Do not edit
`Herden.xcodeproj/project.pbxproj` by hand.

### 3. Prepare the iPhone

1. Connect the unlocked iPhone by USB.
2. Accept **Trust This Computer** on the phone.
3. Open **Xcode → Window → Devices and Simulators** and wait until preparation
   finishes.
4. On the phone, enable **Settings → Privacy & Security → Developer Mode**,
   restart it and confirm the setting. If Developer Mode is absent, finish the
   Xcode pairing first.

### 4. Perform the first signed build

Open the project:

```sh
open Herden.xcodeproj
```

In Xcode:

1. Open **Xcode → Settings → Accounts** and sign in to an account authorised
   for the development team.
2. Select the **Herden** target, open **Signing & Capabilities**, choose the
   team and leave automatic signing enabled.
3. Confirm the App Group is present and uses the identifier chosen above.
4. Repeat those checks for **HerdenShareExtension**.
5. Select the connected iPhone as the run destination and press **Run**.

Resolve every signing error before returning to the command line. Do not remove
the App Group to silence an error. The Share Extension depends on it.

Apple's relevant setup references are [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups),
[Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
and [developer accounts and capabilities](https://developer.apple.com/help/account/basics/about-your-developer-account/).

## Repeat a physical-device install

After the first successful Xcode build, list the devices visible to the Mac:

```sh
xcrun devicectl list devices
```

With one physical device connected, this normally suffices:

```sh
make install APP_ID=com.example.herden
```

With several devices, pass the selected device identifier:

```sh
make install \
  DEVICE=00000000-0000-0000-0000-000000000000 \
  APP_ID=com.example.herden
```

`APP_ID` only tells `devicectl` which installed app to launch. It does not
change the bundle identifier produced by the build. Configure that in
`project.yml` first.

If an SSH shell cannot use the Apple account in the Mac's login Keychain, run
the build from the logged-in Terminal application. The repository also includes
`scripts/build-ios-device.command` for opening a build in that GUI session.

## Install over Wi-Fi

Complete one USB install first. Keep the Mac and iPhone on the same Wi-Fi and
enable **Connect via network** for the phone in Xcode's device manager if the
option is shown. Once `xcrun devicectl list devices` sees the unplugged phone,
use the same `make install DEVICE=... APP_ID=...` command.

After installation, Herden connects from the phone to its Host over ordinary
SSH, usually through Tailscale or Headscale. The Mac is no longer in that data
path. Continue with the [Host pairing guide](install-host.md#start-and-pair).

## Run the tests

Run the app and HerdenSSH package suites on an installed `iPhone 17` Simulator:

```sh
make test
```

Choose a focused app suite with `xcodebuild`:

```sh
xcodebuild test \
  -project Herden.xcodeproj \
  -scheme Herden \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:HerdenTests/PairingCodeTests
```

Changes under `Packages/HerdenSSH` use the separate package test plan:

```sh
scripts/run-herdenssh-package-tests.sh \
  'platform=iOS Simulator,name=iPhone 17'
```

Some real-SSH suites require disposable local SSH fixtures. They skip on a
normal Mac when those fixtures are unavailable;
`scripts/run-ci-ios-tests.sh` provisions them for exhaustive local validation.

## Common failures

| Symptom | Fix |
| --- | --- |
| Requested Simulator cannot be found | Run `xcrun simctl list devices available`, then pass an installed name with `SIM='…'`. |
| Xcode selects the command-line tools package | Run `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`. |
| Bundle identifier is unavailable | Choose a unique reverse-DNS identifier owned by your team and regenerate the project. |
| App Group capability fails | Create or select an App Group owned by the same team for both app targets; remove the retired 3LOC compatibility group. |
| Provisioning remains on “Updating” | Keep the phone unlocked, confirm the team and identifiers, then resolve account or Keychain prompts in Xcode. |
| `make install` builds but cannot launch | Pass the exact configured app bundle identifier as `APP_ID`. |
| No physical device is selected | Run `xcrun devicectl list devices` and pass its UUID as `DEVICE`. |

## Contributor project changes

Run `make generate` after changing targets, signing settings, package links or
source membership in `project.yml`. Commit the regenerated `Herden.xcodeproj`
with the YAML change because it is part of the repository's build source.

Maintainers cutting TestFlight or App Store releases must follow
[the release guide](releasing.md). Do not run `make publish` merely to install a
development build.

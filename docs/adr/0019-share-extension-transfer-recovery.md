# Share files through SFTP with durable progress and explicit recovery

The Share Extension receives one document, image or video, lets the user choose
an Agent, stages the file through the existing SFTP transport and inserts its
absolute Host path plus a space. It sends no keys, newline or `agent.prompt`.
The user opens the Agent in Herden, adds any instructions and presses Return.

The extension and app share transfer records and protected source copies in
`group.ltd.3loc.herden.shared`. Atomic JSON records expose progress, destination and
completion to the app. A nonblocking POSIX lock per transfer prevents concurrent
uploaders and stays held across upload and path insertion. Process termination
releases the lock. Recovery never takes ownership from a live extension.

This extends ADR 0006: a Share Extension has no attached terminal stream, so it
uses one text-only `pane.send_input` request to insert the completed path. The
main app's ordinary terminal input remains unchanged. The Host implements this
request as a paste with terminal-mode-aware framing. The request is not an
attachment-recognition acknowledgement from the Agent.

## Failure boundaries

- Before upload completion: retain the local source and allow an explicit retry.
- After upload completion: retain the remote path and retry insertion without
  uploading the file again.
- Before issuing insertion: persist `inserting`. A failed acknowledgement or
  terminated process becomes `uncertain`, never an automatic retry. The user
  opens the Agent to check the prompt and can copy the path if it is missing.
- After acknowledgement: persist `added`. Reopening the app or selecting Open
  Agent performs navigation only. It never repeats the paste.
- Cancellation cooperatively unwinds upload compensation before closing SSH.
  Backgrounding the extension cancels active work. SFTP is not a background
  URLSession transfer, so completion while suspended is not promised.

Completed remote files remain governed by ADR 0005. Local source copies are
removed on successful insertion or when the user dismisses the transfer.
Interrupted and uncertain sources remain available for recovery until dismissed.
Shared source files and records are excluded from backup. Credentials stay in
the existing shared Keychain, never in transfer records.

## Platform evidence

Reviewed 8 September 2026:

- [Apple: Share extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html): custom sharing UI and extension context lifecycle.
- [Apple: common extension scenarios](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html): App Group containers, coordinated access, activation rules and background URLSession transfers.
- [Apple: extension lifecycle](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html): separate processes and limits on launching the containing app.
- [Apple: NSItemProvider file representation](https://developer.apple.com/documentation/foundation/nsitemprovider/loadfilerepresentation(fortypeidentifier:completionhandler:)): copy the provider's temporary file within its completion handler.
- [cordova-plugin-openwith](https://github.com/j3k0/cordova-plugin-openwith/blob/master/src/ios/ShareExtension/ShareViewController.m): comparable App Group file spooling. Herden does not adopt its responder-chain URL-opening workaround or store file bytes in preferences.

Verify through `make test` on the build Mac, then
`make install DEVICE=<physical-device UUID>`.
Exercise sharing from Files, select an Agent, observe progress and reopen Herden.
Confirm that the path remains editable in the Agent prompt until Return.

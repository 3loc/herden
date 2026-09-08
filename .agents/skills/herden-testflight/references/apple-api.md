# Apple API operations

Use `scripts/asc.py` relative to this skill directory. It consumes
`APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and exactly one of
`APP_STORE_CONNECT_PRIVATE_KEY_P8_BASE64` / `APP_STORE_CONNECT_PRIVATE_KEY_PATH`.
Inject these through the maintainer's secret manager. No credentials belong in
request JSON. The helper sends one request, redacts password fields in output,
and exits nonzero on errors; it never retries mutations automatically.

```sh
python3 .agents/skills/herden-testflight/scripts/asc.py \
  '/v1/apps?filter[bundleId]=ltd.3loc.herden&fields[apps]=name,bundleId'

# Write an exact JSON body to a temporary file before a mutation:
python3 .agents/skills/herden-testflight/scripts/asc.py \
  '/v1/betaAppReviewSubmissions' --method POST --body-file /tmp/submission.json
```

Substitute IDs from actual responses into the examples below. Follow pagination
links when selecting from larger lists. Do not hardcode a historical app, group,
tester, or build ID in automation. Verify endpoint/schema changes against
[Apple's API documentation](https://developer.apple.com/documentation/appstoreconnectapi).

## Inspect and submit

1. `GET /v1/builds?filter[app]=APP_ID&sort=-uploadedDate&limit=10&include=buildBetaDetail,betaAppReviewSubmission,preReleaseVersion`
   shows build numbers, versions, processing, expiration and beta states.
   A successful Xcode upload may not appear here immediately. Wait for the selected
   build's `processingState: VALID` and inspect its beta readiness.
2. `GET /v1/apps/APP_ID/betaGroups` lists group names and privacy settings.
   This relationship endpoint rejects `include=builds`; use
   `GET /v1/betaGroups/GROUP_ID/builds` separately. Preserve public-link settings.
   A private external group has `isInternalGroup: false` and
   `publicLinkEnabled: false`; internal groups require App Store Connect users.
3. Read `GET /v1/apps/APP_ID/betaAppReviewDetail` and
   `GET /v1/apps/APP_ID/betaAppLocalizations`. Ensure review instructions and URLs
   match the current Host install guide. Populate `privacyPolicyUrl` with the
   public policy linked from the app; a policy present only in source is not a
   populated TestFlight field. Herden is a client for a separately installed SSH
   Host. Reviewer instructions should explain using the reviewer's own Mac or
   Linux Host, including SSH, the current-shell PATH export, QR expiry, and the
   ordinary-terminal path that needs no coding-provider account. Do not invent
   demo credentials or provision a developer-hosted review server unless requested.
   Keep third-party Agent CLI authentication prerequisites explicit.
   PATCH the individual resource IDs if corrections are necessary.
4. Read `GET /v1/builds/BUILD_ID/betaBuildLocalizations` before writing testing
   notes. Apple can create an `en-US` resource with `whatsNew: null` automatically.
   PATCH that resource rather than POSTing a duplicate locale. Use the current
   testing scope; inspect previous notes before carrying them forward.
5. `POST /v1/betaGroups/GROUP_ID/relationships/builds` associates the build:

   ```json
   {"data":[{"type":"builds","id":"BUILD_ID"}]}
   ```

6. Verify `autoNotifyEnabled` on the build's `buildBetaDetails`; enable it with
   PATCH if automatic distribution is part of the requested rollout. The body
   uses `type: buildBetaDetails`, the detail's ID and
   `attributes: {"autoNotifyEnabled": true}`.
7. `POST /v1/betaAppReviewSubmissions` submits the build:

   ```json
   {"data":{"type":"betaAppReviewSubmissions","relationships":{"build":{"data":{"type":"builds","id":"BUILD_ID"}}}}}
   ```

8. Re-read `GET /v1/builds/BUILD_ID/betaAppReviewSubmission`, the build beta detail
   and group build lists. `WAITING_FOR_REVIEW` / `WAITING_FOR_BETA_REVIEW` confirms
   submission, not approval. If a POST times out, inspect these resources before
   retrying so an uncertain response does not create a duplicate action.

## Replace an outdated submission

Apple allows one build of a version in beta review at a time. A submission can
fail with `422 ENTITY_UNPROCESSABLE.ANOTHER_BUILD_IN_REVIEW`.

When the task is to replace that older build, first validate and upload the new
build, wait for it to become valid, and prepare its notes and group assignments.
Then expire **only the superseded build**:

`PATCH /v1/builds/OLD_BUILD_ID`

```json
{"data":{"type":"builds","id":"OLD_BUILD_ID","attributes":{"expired":true}}}
```

This removes its installability for both internal and external testers. Verified
on 2026-09-08: expiring waiting build 17 released its review slot and submission
of build 18 immediately succeeded. Verify `expired: true` and retry submission
once. If Apple still reports a conflicting review, inspect the actual review
state and report the blocker; do not expire more builds or invent a new marketing
version to bypass it. Preserve the valid uploaded replacement for resumption.

## Requested invitations

- Find the tester by email before creating one:
  `GET /v1/betaTesters?filter[email]=EMAIL&include=betaGroups` (URL-encode the email).
- Add an existing tester with
  `POST /v1/betaGroups/GROUP_ID/relationships/betaTesters`, using a `data` array
  of `{"type":"betaTesters","id":"TESTER_ID"}` objects. For a new tester,
  `POST /v1/betaTesters` with `attributes.email` and a `betaGroups` relationship.
  Use supplied names only. An invite-only external group may be created for a
  requested private beta if none exists; never silently turn a public group private.
- Send or resend through `POST /v1/betaTesterInvitations` with both `app` and
  `betaTester` relationships. A successful tester creation is not proof an email
  was sent. Check membership and invitation state independently.
- `409 STATE_ERROR.TESTER_INVITE.NO_INSTALLABLE_BUILDS` means Apple did **not**
  send the invitation. External testers must wait for review/availability. Do not
  grant them account access just to skip review. Automatic notifications can be
  enabled, but report the observed invitation state, not assumed email delivery.

References: [Submit for beta review](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-betaappreviewsubmissions),
[invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers),
[stop testing a build](https://developer.apple.com/help/app-store-connect/test-a-beta-version/stop-testing-a-build),
[send an invitation](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-betatesterinvitations).

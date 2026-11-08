# Design

## Context

`mobile/ios/fastlane/Fastfile` builds with `CODE_SIGN_STYLE=Automatic` and `-allowProvisioningUpdates`. On a fresh GitHub Mac, the archive step finds no signing identity, so Xcode asks Apple for a new *Apple Development: Created via API* certificate each run. The account allows a fixed number, so the 12th run fails with *Choose a certificate to revoke* and *No profiles for ... were found* (run 42412612660). A read of the App Store Connect API on 2026-11-07 listed one certificate, *Developer ID Application* (a Mac certificate, of no use here), and old `IOS_APP_STORE` profiles `runner` and `share_ext` made for revoked certificates. Both targets use the App Group `group.com.matthewwong525.relayApp`; the app also uses HealthKit.

## Goals / Non-Goals

**Goals:** a build makes no certificate; the saved certificate is the only signing secret added; renewal is one command.

**Non-Goals:** the iPhone device check (simulator, no signing); Android signing; deleting old profiles on Apple's account.

## Decisions

- **Manual signing with a saved Apple Distribution certificate, not fastlane `match`.** `match` keeps certificates in a git repository or a bucket; this repository is public, and a second private store is one more thing to keep. A `.p12` in two GitHub secrets is the same pattern as the Android upload key.
- **Profiles fetched each run with `get_provisioning_profile` (sigh), not saved.** sigh, with the API key and `cert_id` of the saved certificate, reuses a valid profile and makes one only when none is valid. Saved profiles would need a renewal of their own and a third and fourth secret.
- **Signing settings set at build time, not in `project.pbxproj`.** The lane runs `update_code_signing_settings` on the `Runner` and `ShareExtension` targets (Manual, `Apple Distribution`, the team, each target's profile name), then `build_app` with `export_options.provisioningProfiles` mapping both bundle ids. Local Xcode builds keep automatic signing. Global `xcargs` for the profile are not used: they would also hit the Pods targets.
- **The certificate is made by a script on this computer.** `scripts/ios-signing-cert.mjs` reads the ASC key from `.env`, makes a private key and CSR with `openssl` in a temporary folder outside the repository, posts the CSR to `POST /v1/certificates` (`DISTRIBUTION`), builds the `.p12` with a random password, writes `IOS_DIST_CERT_P12` (base64) and `IOS_DIST_CERT_PASSWORD` to `.env` (primary worktree) and to `gh secret set --repo matthewwong525/RelayEverything`, then deletes the folder. It prints the certificate id and expiry only. This follows [secrets](../../../wiki/development/secrets.md): the values never pass through chat. Node is used because this computer has no Ruby.
- **`-allowProvisioningUpdates` is removed.** With it gone, Xcode can not make a certificate even if signing goes wrong; the build fails with a clear error instead.

## Risks / Trade-offs

- [Apple Distribution limit is low (about 3)] → the script lists existing distribution certificates first and stops with a message when the limit is reached, naming the revoke step.
- [The certificate expires in one year] → the expiry goes in `wiki/open-source.md`; sigh then makes new profiles on its own after the renewal.
- [The certificate's private key leaks from secrets] → it can only sign builds for this team; revoke on developer.apple.com and run the script again.
- [Cloud-managed certificates may not show in the API list] → the human revoke step stays in the plan, done only if the first build still says the account is full.

## Migration Plan

Run the script, merge, and watch the next `main` iPhone build. Rollback: revert the Fastfile and workflow; the saved secrets do no harm.

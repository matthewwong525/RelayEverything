## 1. Certificate script

- [x] 1.1 Write `scripts/ios-signing-cert.mjs`: read the ASC key from the primary worktree's `.env`, list Apple Distribution certificates, stop at the limit with the revoke step, make key and CSR with `openssl` in a temp folder, create the certificate through the App Store Connect API, build the `.p12` with a random password, write both values to `.env` and `gh secret set`, delete the folder, print only id and expiry
- [x] 1.2 Write `scripts/ios-signing-cert.test.mjs` for the parts that need no network: the JWT shape, the limit message, and that no value reaches stdout
- [x] 1.3 Run the script on this computer (one Apple Distribution certificate, values only in `.env` and the repository secrets)

## 2. Build signing

- [x] 2.1 In `mobile/ios/fastlane/Fastfile`: `import_certificate` from `IOS_DIST_CERT_P12` into the `setup_ci` keychain; `get_provisioning_profile` for both bundle ids with the saved certificate; `update_code_signing_settings` for `Runner` and `ShareExtension`; `build_app` with manual export options; remove `-allowProvisioningUpdates` and `CODE_SIGN_STYLE=Automatic`
- [x] 2.2 In `.github/workflows/mobile-ios.yml`: add `IOS_DIST_CERT_P12` and `IOS_DIST_CERT_PASSWORD` to `env` and to the gate, with a notice that names the missing secret

## 3. Docs

- [x] 3.1 `.env.example`: the two new variables, blank, with how the script makes them
- [x] 3.2 `mobile/README.md` iPhone line and `wiki/open-source.md` Phone builds: one saved certificate, yearly renewal with the script, and the revoke step for a full account

## 4. Checks

- [x] 4.1 `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs` and the new script test pass
- [ ] 4.2 `/save`, then run Mobile iOS on the branch with `workflow_dispatch` and see it reach TestFlight; if it says the account is full, ask the person to revoke the *Created via API* certificates and run again
- [ ] 4.3 After the run, list Apple's certificates and confirm no new development certificate was made

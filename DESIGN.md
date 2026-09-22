# Nimbo — native macOS design

## Design contract

- Navigation uses `NavigationSplitView`, a selectable sidebar `List`, a standard title bar and system toolbar items. Do not paint a custom material over the sidebar or toolbar.
- Glass is the control layer, not a decoration for each row. Primary actions use native `glassProminent` on macOS 26; secondary row actions keep standard bezels. There are no stacked glass surfaces or simulated blur blobs.
- Bottom actions use `safeAreaBar`, allowing the system to handle the scroll edge.
- Results are opaque, grouped content surfaces. Overview numbers come from actual scans, not a simulated health score. All scan, selection, confirmation, trash and startup-service behavior remains in the existing model/services.
- Search lives in the system toolbar. Settings use a grouped `Form`. Sheets retain system presentation backgrounds.
- Appearance is shared through `appAppearance`. Brand colors have explicit light, dark and increased-contrast variants. The cleanup disclosure respects Reduce Motion; native controls handle system accessibility preferences.
- Keep the existing transparent Nimbo brand artwork. This iteration does not convert the raster app icon into a layered Icon Composer asset.

## Verification

Build both supported architectures:

```sh
NIMBO_ARCHS="arm64 x86_64" ./build.sh
```

Read-only symbol check (run on the target macOS runtime):

```sh
xcrun swiftc -module-cache-path build/ModuleCache Sources/Models.swift Tests/DesignTests.swift -o build/design-tests
build/design-tests
```

Every suite at once, which is also what a release runs as a gate:

```sh
bash scripts/run-tests.sh
```

Individual suites, when iterating on one of them:

```sh
python3 -m unittest discover -s Tests -p 'test_*.py'
bash Tests/release-mode-tests.sh
xcrun swiftc -module-cache-path build/ModuleCache Sources/Models.swift Sources/RemovalDiagnostics.swift Sources/FinderTrashService.swift Sources/UninstallService.swift Tests/UninstallTests.swift -o build/uninstall-tests
build/uninstall-tests
xcrun swiftc -module-cache-path build/ModuleCache Sources/Models.swift Sources/RemovalDiagnostics.swift Sources/FinderTrashService.swift Sources/UninstallService.swift Tests/FinderTrashTests.swift -o build/finder-trash-tests
build/finder-trash-tests
xcrun swiftc -module-cache-path build/ModuleCache Sources/RemovalDiagnostics.swift Tests/RemovalDiagnosticsTests.swift -o build/removal-diagnostics-tests
build/removal-diagnostics-tests
xcrun swiftc -module-cache-path build/ModuleCache Sources/StartupService.swift Tests/StartupTests.swift -o build/startup-tests
build/startup-tests
xcrun swiftc -module-cache-path build/ModuleCache Sources/StartupService.swift Sources/PreferencesMigration.swift Tests/PreferencesMigrationTests.swift -o build/preferences-migration-tests
build/preferences-migration-tests
```

Visual checks must cover both appearances, narrow and enlarged windows, sidebar navigation, expanded cleanup results, toolbar search including no matches, settings and sheets. Never confirm a destructive action or change startup services during visual QA.

2026-09-09: On macOS 26, checked the light/dark overview and Settings, compact and enlarged windows, the application list and no-match search, cleanup disclosure and scroll-edge action bar, developer/large-file/leftover empty states, startup services, and uninstall-sheet cancellation. Regression suites passed (8 appcast tests, release-mode checks, uninstall safeguards, read-only startup scan, 33 literal SF Symbols). User files and startup settings were not changed.

Before release, additionally exercise VoiceOver, Increase Contrast, Reduce Transparency and Reduce Motion on actual system configurations. Compile-time availability guards are not a substitute for a macOS 14/15 runtime test. No new release is published by this design change.

## Apple references

- [Liquid Glass overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Custom Liquid Glass views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

## Overview header and icon consistency

The generated landscape is bundled locally; its [exact prompt and provenance](Assets/nimbo-landscape-header.md) are preserved. `OverviewHeader` is edge-aligned inside the detail scroll view. On macOS 26, `backgroundExtensionEffect()` extends the artwork underneath the sidebar and safe areas; the text overlay is applied afterward so text is never mirrored. Older systems retain the same image without a simulated extension. A dark scrim maintains white-text contrast in both appearances.

Navigation and overview quick actions share `SidebarSection.icon` and category accent metadata. Category symbols use outline, monochrome rendering and a shared `NimboIconBadge`; filled selection/status symbols retain their semantic distinction. Actual installed-app icons and Nimbo's brand artwork stay original.

Reference: [Apple's background-extension sample](https://developer.apple.com/documentation/swiftui/landmarks-applying-a-background-extension-effect).

## Removal obstacles

A refused removal is classified before it is reported, because the three causes need different remedies and only one of them is about privileges.

- `privacy`: TCC refused the operation even though POSIX permits it. Full Disk Access fixes it; administrator rights do not bypass TCC.
- `ownership`: `access(2)` refuses write on the parent directory, or on the item itself when its contents must be removed. Finder's own authenticated move is the remedy.
- `systemProtected`: the item carries `restricted` (SIP), `immutable` or `nounlink`, or sits under a `restricted` parent. No privilege level removes it.
- `undetermined`: a denial that none of the above explains. Reported honestly with its errno rather than guessed.

Presence is checked with `lstat`, not `fileExists`. A denied lookup is indistinguishable from a missing file through `fileExists`, so a blocked item used to be skipped silently and counted as cleaned. Only `ENOENT`/`ENOTDIR` are treated as already gone; any other errno is reported as a failure without attempting the removal.

A `nounlink` parent is deliberately not treated as protecting its contents: `/Applications` carries `SF_NOUNLINK` while admins may still remove entries from it. `lstat` is used so a symlink is judged by itself. Cleanup and uninstall share `RemovalFailure`, so both flows report the same obstacle and both offer the Full Disk Access shortcut only for `privacy`. Classification is diagnosis only: Nimbo requests no elevation, changes no permission and touches no file while classifying.

```sh
xcrun swiftc -module-cache-path build/ModuleCache Sources/RemovalDiagnostics.swift Tests/RemovalDiagnosticsTests.swift -o build/removal-diagnostics-tests
build/removal-diagnostics-tests
```

### Handing an ownership block to Finder

Moving a directory needs write permission on the directory itself, not only on its parent: `rename(2)` rewrites the directory's `..` entry. A `root:wheel 755` application bundle therefore fails with `EACCES` even though `/Applications` is group-writable for admins — which is why half a typical `/Applications` cannot be trashed by its user. This is ownership, not privacy, and Full Disk Access does not change it.

The remedy is Finder, which owns the authenticated move macOS reserves for it. `Dokončit přes Finder` appears only when at least one failure is classified `ownership`, and hands Finder everything still outstanding: the failures plus the related files that were skipped when the application itself was blocked. Finder asks for administrator credentials itself, so **Nimbo ships no privileged helper, runs nothing as root and never sees the password**. Deliberately not a `SMAppService` daemon: under ad-hoc signing an XPC peer cannot be verified, which is the shape of the thirteen CVEs Talos found in CleanMyMac X's helper protocol.

### App Management comes before any of this

macOS 13 refuses to let one application modify another until the user grants **App Management** (`kTCCServiceSystemPolicyAppBundles`). TCC blames the *responsible* process, which for an Apple Event is Nimbo and not Finder, so the handoff does not escape it: the denial reads „Aplikaci „Nimbo" bylo zabráněno v úpravě aplikací na vašem Macu." Uninstalling an application therefore needs two separate things, and neither substitutes for the other:

1. **App Management**, or macOS refuses the move whoever performs it.
2. **The Finder handoff**, or a `root:wheel` bundle still fails on POSIX `EACCES`.

Full Disk Access is a third, unrelated permission and does not cover this. There is no API to read App Management status, so the startup preflight cannot check it honestly — the report says which blocked items are application bundles and offers the settings pane, without claiming to know what TCC decided.

**Ad-hoc builds lose the grant on every rebuild.** TCC identifies an application by its code signature, and an ad-hoc signature has no Team ID and a fresh cdhash after each `./build.sh`, so macOS sees a different application and the permission has to be granted again. Developer ID is what makes the grant stick; `scripts/sign-app.sh` already has that path, it needs a certificate rather than a project change. When testing permission behaviour, grant the permission to the build under test and do not rebuild in between.

Paths are passed to `osascript` as process arguments and never interpolated into the script, so no path can change what the script does. Finder's answer is matched back to the requested URLs: a path Nimbo did not ask about is ignored, and an item Finder does not mention stays a failure — silence is not success. Items already diagnosed keep their diagnosis when Finder fails too. The report keeps its identity across a retry so the sheet is updated rather than dismissed and re-presented.

```sh
xcrun swiftc -module-cache-path build/ModuleCache Sources/Models.swift Sources/RemovalDiagnostics.swift Sources/FinderTrashService.swift Sources/UninstallService.swift Tests/FinderTrashTests.swift -o build/finder-trash-tests
build/finder-trash-tests
```

## Bundle identifier change

Version 1.6 renames the bundle identifier from `local.nimbo.app` to `dev.svtk.nimbo`, together with the move from ad-hoc signing to Developer ID. Preferences are stored in a file named after the identifier, so the rename would reset them. `PreferencesMigration` copies Nimbo's own keys once, on the first launch under the new identifier: `appAppearance` and, more importantly, `disabledLoginItems` — the list Nimbo uses to restore login items the user switched off, which cannot be reconstructed from the system. It never overwrites a value already set under the new identifier and never runs twice, so a later deliberate change stands.

Window frames and Sparkle's own bookkeeping are left behind on purpose. `CFPreferencesCopyAppValue` reads the old domain exactly, where a `UserDefaults` suite would also answer from the global domain.

Both changes land in the same release on purpose: each one resets TCC grants by itself, so doing them together costs one reset instead of two. They also both touch the update path, so a real 1.5 → 1.6 update has to be verified before publishing.

```sh
xcrun swiftc -module-cache-path build/ModuleCache Sources/StartupService.swift Sources/PreferencesMigration.swift Tests/PreferencesMigrationTests.swift -o build/preferences-migration-tests
build/preferences-migration-tests
```

## About window

`O aplikaci Nimbo` replaces the standard About panel (`CommandGroup(replacing: .appInfo)`) and shows the version from `Info.plist` plus the svtk.dev studio link. The studio mark is bundled in `Assets/svtk-mark.png` and copied to Resources by `build.sh`: the window renders offline like the rest of Nimbo and makes no request the user did not ask for. The panel sets `hidesOnDeactivate = false`, because `NSPanel` otherwise disappears as soon as the user switches away. Only the explicit link opens a browser.

## Startup permission preflight

Before initial scans, Nimbo checks read access to its actual root directories and performs a non-prompting System Events automation preflight on background workers. Missing optional SDK/package-manager directories are not permission failures. Denied, not-yet-requested and unknown states remain distinct. A 12-second timeout keeps the app usable; late results cannot overwrite a newer run. Startup shows a details sheet when attention is needed, with explicit Settings/help actions and a continue-with-limitations option. Overview, Privacy and Settings expose the same live results. Returning from system settings triggers a silent refresh, not another unsolicited sheet.

macOS may show Files & Folders consent while opening a protected directory. Only the user's explicit automation button launches System Events and requests automation consent. No permission is granted, ACL changed, administrator prompt requested or unrelated private file inspected by this preflight. A readable root does not prove all descendants are accessible, that deletion will succeed, or that Full Disk Access is enabled. There is no supported global FDA status API: see [Apple DTS guidance](https://developer.apple.com/forums/thread/835851). Actual action errors retain their existing safeguards.

Permission regression tests use injected outcomes and a temporary fixture, never private user directories or live authorization requests:

```sh
xcrun swiftc -module-cache-path build/ModuleCache Sources/PermissionChecks.swift Sources/PermissionController.swift Tests/PermissionTests.swift -o build/permission-tests
build/permission-tests
```

2026-09-09 follow-up verification: universal arm64/x86_64 build and strict deep ad-hoc signature verification passed. Permission tests, 40 category/literal SF Symbols, 8 appcast tests, release-mode checks, uninstall safeguards and the read-only startup scan passed. In the actual app, checked the landscape extension in light/dark appearances and two window sizes, its disappearance beneath the sidebar when scrolling, overview quick-action icons, the automatic startup warning, per-folder disclosure (including denied Trash access), limited continuation and opening the same details from Settings. A slow personal-folder probe correctly became unknown rather than falsely granted. No OS permission was granted and no user files or startup settings were changed. System-consent grant/deny interactions and older macOS runtimes remain manual release checks.

# Nimbo — native macOS design

## Design contract

- Navigation uses `NavigationSplitView`, a selectable sidebar `List`, a standard title bar and system toolbar items. Do not paint a custom material over the sidebar or toolbar.
- Glass is the control layer, not a decoration for each row. Primary actions use native `glassProminent` on macOS 26; secondary row actions keep standard bezels. There are no stacked glass surfaces or simulated blur blobs.
- Bottom actions use `safeAreaBar` on macOS 26, allowing the system to handle the scroll edge. The macOS 14–25 fallback uses `safeAreaInset` and bordered primary controls.
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

Regression checks:

```sh
python3 -m unittest discover -s Tests -p 'test_*.py'
bash Tests/release-mode-tests.sh
xcrun swiftc -module-cache-path build/ModuleCache Sources/Models.swift Sources/UninstallService.swift Tests/UninstallTests.swift -o build/uninstall-tests
build/uninstall-tests
xcrun swiftc -module-cache-path build/ModuleCache Sources/StartupService.swift Tests/StartupTests.swift -o build/startup-tests
build/startup-tests
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

## Startup permission preflight

Before initial scans, Nimbo checks read access to its actual root directories and performs a non-prompting System Events automation preflight on background workers. Missing optional SDK/package-manager directories are not permission failures. Denied, not-yet-requested and unknown states remain distinct. A 12-second timeout keeps the app usable; late results cannot overwrite a newer run. Startup shows a details sheet when attention is needed, with explicit Settings/help actions and a continue-with-limitations option. Overview, Privacy and Settings expose the same live results. Returning from system settings triggers a silent refresh, not another unsolicited sheet.

macOS may show Files & Folders consent while opening a protected directory. Only the user's explicit automation button launches System Events and requests automation consent. No permission is granted, ACL changed, administrator prompt requested or unrelated private file inspected by this preflight. A readable root does not prove all descendants are accessible, that deletion will succeed, or that Full Disk Access is enabled. There is no supported global FDA status API: see [Apple DTS guidance](https://developer.apple.com/forums/thread/835851). Actual action errors retain their existing safeguards.

Permission regression tests use injected outcomes and a temporary fixture, never private user directories or live authorization requests:

```sh
xcrun swiftc -module-cache-path build/ModuleCache Sources/PermissionChecks.swift Sources/PermissionController.swift Tests/PermissionTests.swift -o build/permission-tests
build/permission-tests
```

2026-09-09 follow-up verification: universal arm64/x86_64 build and strict deep ad-hoc signature verification passed. Permission tests, 40 category/literal SF Symbols, 8 appcast tests, release-mode checks, uninstall safeguards and the read-only startup scan passed. In the actual app, checked the landscape extension in light/dark appearances and two window sizes, its disappearance beneath the sidebar when scrolling, overview quick-action icons, the automatic startup warning, per-folder disclosure (including denied Trash access), limited continuation and opening the same details from Settings. A slow personal-folder probe correctly became unknown rather than falsely granted. No OS permission was granted and no user files or startup settings were changed. System-consent grant/deny interactions and older macOS runtimes remain manual release checks.

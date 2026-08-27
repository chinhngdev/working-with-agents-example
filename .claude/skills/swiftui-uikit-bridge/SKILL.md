---
name: swiftui-uikit-bridge
description: Guides interop between SwiftUI and UIKit in hybrid iOS apps, covering UIHostingController, UIViewRepresentable, UIViewControllerRepresentable, Coordinator objects for delegates, and state synchronization between the two frameworks. Use when the user asks to embed SwiftUI in UIKit, embed UIKit in SwiftUI, wrap a UIKit component, fix a SwiftUI/UIKit interop bug, or migrate a screen incrementally between frameworks.
---

# SwiftUI / UIKit Bridge

## Purpose

Most production iOS apps are hybrid — some screens in UIKit, some in SwiftUI, often within the same navigation stack. This skill provides the concrete interop mechanics and the common pitfalls, so migrations and mixed-framework features don't produce subtle state or lifecycle bugs.

## Step 1: Identify the direction of embedding

Ask (or infer from the user's code): which framework hosts which?

- **SwiftUI inside UIKit** → use `UIHostingController`.
- **UIKit inside SwiftUI** → use `UIViewControllerRepresentable` (for view controllers) or `UIViewRepresentable` (for bare `UIView` subclasses like `MKMapView`, `UITextView`, or a custom `CALayer`-backed view).

## Step 2: SwiftUI inside UIKit — `UIHostingController`

```swift
let swiftUIView = ProfileView(viewModel: viewModel)
let hostingController = UIHostingController(rootView: swiftUIView)
navigationController?.pushViewController(hostingController, animated: true)
```

Key points to check:

- **Sizing:** `UIHostingController` sizes itself based on the SwiftUI content. If embedding as a child view controller (not full-screen), set `hostingController.view.translatesAutoresizingMaskIntoConstraints = false` and pin constraints explicitly — a common bug is a hosting controller collapsing to zero size when added as a child without constraints.
- **Passing updated data:** update `hostingController.rootView = ProfileView(viewModel: newViewModel)` to push new data in; don't recreate the hosting controller unless you want to lose SwiftUI's internal state.
- **Safe area:** by default `UIHostingController` respects safe areas; if the parent UIKit view controller also handles safe area insets, you can get double-padding. Check `additionalSafeAreaInsets` on both sides if spacing looks wrong.

## Step 3: UIKit inside SwiftUI — `UIViewControllerRepresentable`

```swift
struct LegacyScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        // Push SwiftUI state changes into the UIKit controller here, if any.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ScannerViewControllerDelegate {
        let parent: LegacyScannerView
        init(_ parent: LegacyScannerView) { self.parent = parent }

        func didScan(code: String) {
            parent.scannedCode = code
        }
    }
}
```

Key points to check:

- **The Coordinator is the delegate bridge.** UIKit APIs that use delegate protocols (scanner callbacks, `UITextFieldDelegate`, `MKMapViewDelegate`) cannot call directly into a SwiftUI `View` struct. The `Coordinator` (an `NSObject` subclass) is the bridge — it conforms to the delegate protocol and forwards events into SwiftUI `@Binding` or a callback closure.
- **`updateUIViewController` fires on every SwiftUI state change** that affects this view — keep it cheap and idempotent. Don't perform side effects (like starting a network call) unconditionally here, or it will re-run more often than expected.
- **For bare views (not controllers)**, use `UIViewRepresentable` instead — same pattern, but implement `makeUIView`/`updateUIView`.

## Step 4: Bidirectional data flow

The hard part is rarely the wrapper — it's keeping state in sync in both directions:

- **UIKit → SwiftUI:** route through the Coordinator's delegate callback into a `@Binding` or an `@Observable` object shared with the SwiftUI side.
- **SwiftUI → UIKit:** route through `updateUIViewController`/`updateUIView`, which SwiftUI calls automatically when the wrapped struct's properties change.
- Avoid maintaining the same piece of state in two places (e.g. both a `@State` var in SwiftUI and a stored property in the UIKit controller) — pick one source of truth and have the other side mirror it.

## Step 5: Navigation interop

When both frameworks share one navigation stack:

- Pushing a `UIHostingController` onto a `UINavigationController` works like any other view controller — `navigationController?.pushViewController(hostingController, animated: true)`.
- For SwiftUI-native navigation (`NavigationStack`) wrapping UIKit screens, wrap each UIKit screen as a `UIViewControllerRepresentable` and push it as a SwiftUI destination; avoid mixing `UINavigationController` push calls with `NavigationStack` in the same flow, as they will fight over the back button and transition animations.
- If the app is mid-migration, a common pattern is to keep **one** `UINavigationController` as the outer shell and host all SwiftUI screens inside it via `UIHostingController`, deferring a full `NavigationStack` migration until UIKit screens are gone.

## Common errors and fixes

### Hosting controller shows blank/zero-size view
**Cause:** Added as a child view controller without Auto Layout constraints pinning its view.
**Fix:** After `addChild(hostingController)` and `view.addSubview(hostingController.view)`, add explicit constraints (top/leading/trailing/bottom) and call `hostingController.didMove(toParent: self)`.

### SwiftUI view doesn't update when UIKit data changes
**Cause:** Mutating a plain (non-`@Observable`/non-`@Published`) property on an object referenced by the SwiftUI view.
**Fix:** Ensure the shared model is `@Observable` (or the UIKit side sets a `@Published` property on an `ObservableObject`) and that SwiftUI holds it via `@State`, `@ObservedObject`, or `@Bindable` as appropriate for the Swift/SwiftUI version in use.

### Delegate callback never fires after wrapping in `UIViewControllerRepresentable`
**Cause:** Forgot to set `vc.delegate = context.coordinator` in `makeUIViewController`, or the Coordinator wasn't retained (rare, since SwiftUI retains it, but check `makeCoordinator` is actually implemented).
**Fix:** Verify the delegate assignment line exists and that `Coordinator` conforms to the exact delegate protocol required.

### Double safe-area padding or double navigation bar
**Cause:** Both the UIKit parent and the embedded `UIHostingController`/SwiftUI view are applying their own top inset or navigation bar.
**Fix:** Decide which layer owns the navigation bar and safe area; typically the outer UIKit `UINavigationController` owns it, and the SwiftUI content should ignore or account for it via `.toolbar(.hidden)` or reading `safeAreaInsets` rather than re-adding padding.

## Example

**User says:** "I need to show a SwiftUI settings screen from our existing UIKit tab bar controller."

**Actions:**
1. Wrap the SwiftUI `SettingsView` in a `UIHostingController(rootView: SettingsView(viewModel: ...))`.
2. Set it as one of the `UITabBarController`'s view controllers via `viewControllers = [..., hostingController]`.
3. Set `hostingController.tabBarItem` to configure the tab's icon/title (this is plain UIKit, unaffected by the SwiftUI content).
4. If `SettingsView` needs to trigger a UIKit-only flow (e.g. present a legacy `MFMailComposeViewController`), pass a closure into `SettingsView` that the UIKit tab bar controller implements, rather than importing UIKit APIs directly into the SwiftUI view.

**Result:** A SwiftUI screen integrated cleanly into the existing UIKit tab bar without duplicating navigation state.

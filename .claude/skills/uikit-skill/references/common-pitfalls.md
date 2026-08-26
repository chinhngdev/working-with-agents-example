# Common UIKit/AppKit pitfalls and how to avoid them

### Strong delegate property
A strong reference back to the owning object creates a retain cycle — neither side ever deallocates.
```swift
// ❌ Wrong — strong reference cycle: view controller owns the component,
// component strongly owns the delegate pointing back at the view controller
protocol PickerDelegate: AnyObject {
    func picker(_ picker: Picker, didSelect item: Item)
}
final class Picker {
    var delegate: PickerDelegate?
}

// ✅ Right — weak delegate breaks the cycle
final class Picker {
    weak var delegate: PickerDelegate?
}
```
**Avoid:** always declare delegate properties `weak var delegate: SomeDelegate?` with an `AnyObject`-constrained protocol — a delegate is a callback pointer, not an ownership relationship.

### Missing `[weak self]` in an escaping closure
A view controller storing a closure that captures `self` strongly creates a cycle: the closure lives in a property on `self`, and the closure holds `self` alive.
```swift
// ❌ Wrong — self captured strongly in a closure self also owns
final class ProfileViewController: UIViewController {
    var onSave: (() -> Void)?
    func configure() {
        onSave = {
            self.save() // strong capture, retain cycle via self.onSave
        }
    }
}

// ✅ Right — weak capture breaks the cycle
final class ProfileViewController: UIViewController {
    var onSave: (() -> Void)?
    func configure() {
        onSave = { [weak self] in
            self?.save()
        }
    }
}
```
**Avoid:** any closure a view controller/view stores as a property, or passes to a completion handler/animation block that outlives the current call, needs `[weak self]` unless you've deliberately decided the closure's lifetime is short and self-owned.

### Forgetting `translatesAutoresizingMaskIntoConstraints = false`
Without this, UIKit/AppKit auto-generates frame-based constraints from the view's current frame, which conflict with (and silently defeat) your programmatic constraints.
```swift
// ❌ Wrong — constraints appear to do nothing, or produce "unsatisfiable constraints" logs
let label = UILabel()
view.addSubview(label)
NSLayoutConstraint.activate([
    label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
])

// ✅ Right
let label = UILabel()
label.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(label)
NSLayoutConstraint.activate([
    label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
])
```
**Avoid:** set `translatesAutoresizingMaskIntoConstraints = false` immediately after creating any view you intend to constrain programmatically, before adding constraints.

### Manual index-based table/collection view updates drifting from data
Hand-tracked `insertRows`/`deleteRows` calls have to exactly match the real change in the backing array — any drift crashes.
```swift
// ❌ Wrong — if `items` and the update call disagree even slightly, this crashes:
// "Invalid update: invalid number of rows in section 0"
items.remove(at: index)
tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
// ...later, another code path also mutates `items` without a matching tableView call

// ✅ Right — diffable data source computes and applies the diff safely
var snapshot = dataSource.snapshot()
snapshot.deleteItems([itemToRemove])
dataSource.apply(snapshot, animatingDifferences: true)
```
**Avoid:** use `UITableViewDiffableDataSource`/`UICollectionViewDiffableDataSource` (or their AppKit equivalents) and apply snapshots instead of manually calling `insertRows`/`deleteRows`/`reloadData` in multiple places that can fall out of sync with the actual data.

### Not resetting per-cell async state in `prepareForReuse()`
A recycled cell keeps whatever image/content the previous item set until the new async load finishes — causing a visible flash of the wrong content while scrolling.
```swift
// ❌ Wrong — no cleanup; fast scrolling shows stale images from recycled cells
final class PhotoCell: UICollectionViewCell {
    @IBOutlet var imageView: UIImageView!
    func configure(url: URL) {
        ImageLoader.shared.load(url) { [weak self] image in
            self?.imageView.image = image
        }
    }
}

// ✅ Right — cancel the in-flight load and clear stale content on reuse
final class PhotoCell: UICollectionViewCell {
    @IBOutlet var imageView: UIImageView!
    private var loadTask: Task<Void, Never>?

    func configure(url: URL) {
        loadTask = Task { [weak self] in
            let image = await ImageLoader.shared.load(url)
            self?.imageView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        imageView.image = nil
    }
}
```
**Avoid:** any cell that kicks off async work (image loading, network fetch) must cancel that work and reset the affected UI state in `prepareForReuse()`, so a slow response from a previous configuration can't land on a cell now showing different data.

### Layout/subview mutation inside `draw(_:)` or unguarded `layoutSubviews()`
`draw(_:)` should only draw; changing constraints or adding subviews there (or triggering another layout pass inside `layoutSubviews()` by reading geometry you just invalidated) causes redundant layout/draw cycles and can hitch scrolling.
```swift
// ❌ Wrong — mutates layout during a draw pass
override func draw(_ rect: CGRect) {
    addSubview(badgeView) // triggers another layout pass mid-draw
    super.draw(rect)
}

// ✅ Right — subview/constraint setup happens once, outside draw
override func layoutSubviews() {
    super.layoutSubviews()
    // pure geometry reads here; no new constraints/subviews added on every pass
}
private func setUpBadge() { // called once, e.g. from init
    addSubview(badgeView)
}
```
**Avoid:** treat `draw(_:)` as read-only rendering. Do one-time subview/constraint setup in `init`/`viewDidLoad`, and keep `layoutSubviews()`/`layout()` limited to geometry that must react to size changes — not adding new views or constraints on every call.

### Business/networking logic living directly in the view controller
"Massive View Controller": the class owns URLSession calls, JSON parsing, and UI at once — untestable without standing up the whole view hierarchy.
```swift
// ❌ Wrong — networking, parsing, and UI all coupled in the view controller
final class FeedViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        URLSession.shared.dataTask(with: feedURL) { data, _, _ in
            guard let data, let items = try? JSONDecoder().decode([Item].self, from: data) else { return }
            DispatchQueue.main.async {
                self.items = items
                self.tableView.reloadData()
            }
        }.resume()
    }
}

// ✅ Right — logic extracted to a testable, injectable view model
@MainActor
final class FeedViewModel {
    private let service: FeedServicing
    private(set) var items: [Item] = []
    init(service: FeedServicing) { self.service = service }
    func load() async throws { items = try await service.fetchItems() }
}

final class FeedViewController: UIViewController {
    private let viewModel: FeedViewModel
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            try await viewModel.load()
            tableView.reloadData()
        }
    }
}
```
**Avoid:** extract networking/parsing/business decisions into a view model or service the view controller merely calls and observes — see [[apple-testing]] for testing that layer directly, without instantiating the view controller.

### Forgetting to remove NotificationCenter/KVO observers
An observer registered on an object that outlives the observer (or vice versa) either leaks or crashes when the notification fires against a deallocated target.
```swift
// ❌ Wrong — token from block-based addObserver is never removed
final class BannerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.addObserver(forName: .userDidLogin, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }
}

// ✅ Right — store and remove the token
final class BannerView: UIView {
    private var loginObserver: NSObjectProtocol?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard loginObserver == nil, window != nil else { return }
        loginObserver = NotificationCenter.default.addObserver(forName: .userDidLogin, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }
    deinit {
        if let loginObserver { NotificationCenter.default.removeObserver(loginObserver) }
    }
}
```
**Avoid:** store the token returned by block-based `addObserver(forName:...)` and remove it in `deinit` (or the matching lifecycle teardown) — block-based observers are not automatically removed on deallocation the way old `#selector`-based `NSObject` observers are.

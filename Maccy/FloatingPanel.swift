import SwiftUI

/// An NSPanel subclass that implements floating panel traits.
class FloatingPanel<Content: View>: NSPanel {
  @Binding var isPresented: Bool

  init(
    view: () -> Content,
    contentRect: NSRect,
    backing: NSWindow.BackingStoreType = .buffered,
    defer flag: Bool = false,
    isPresented: Binding<Bool>
  ) {
    /// Initialize the binding variable by assigning the whole value via an underscore
    self._isPresented = isPresented

    /// Init the window as usual
    super
      .init(
        contentRect: contentRect,
        styleMask: [.nonactivatingPanel, .titled, .resizable, .closable, .fullSizeContentView],
        backing: backing,
        defer: flag)

    /// Allow the panel to be on top of other windows
    isFloatingPanel = true
    level = .floating

    /// Allow the pannel to be overlaid in a fullscreen space
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    //    collectionBehavior.insert(.fullScreenAuxiliary)
    //    collectionBehavior.insert(.canJoinAllSpaces)

    /// Don't show a window title, even if it's set
    titleVisibility = .hidden
    titlebarAppearsTransparent = true

    /// Since there is no title bar make the window moveable by dragging on the background
    isMovableByWindowBackground = true

    /// Hide when unfocused
    hidesOnDeactivate = true

    /// Hide all traffic light buttons
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    /// Sets animations accordingly
    animationBehavior = .utilityWindow

    /// Set the content view.
    /// The safe area is ignored because the title bar still interferes with the geometry
    contentView = NSHostingView(
      rootView: view()
        .ignoresSafeArea()
        //        .environment(\.floatingPanel, self))
    )

    //    becomesKeyOnlyIfNeeded = false
    //    worksWhenModal = true
  }

  /// Close automatically when out of focus, e.g. outside click
  override func resignMain() {
    super.resignMain()
    close()
  }

  /// Close and toggle presentation, so that it matches the current state of the panel
  override func close() {
    super.close()
    isPresented = false
  }

  /// `canBecomeKey` and `canBecomeMain` are both required so that text inputs inside the panel can receive focus
  override var canBecomeKey: Bool {
    return true
  }

  override var canBecomeMain: Bool {
    return true
  }
}

//public struct Floating<Content> : Scene where Content : View {
//  @MainActor public var body: some Scene { get }
//
//  public init(_ title: Text, id: String, @ViewBuilder content: () -> Content) {
//
//  }
//
//  public typealias Body = Scene
//}

extension View {
  /** Present a ``FloatingPanel`` in SwiftUI fashion
     - Parameter isPresented: A boolean binding that keeps track of the panel's presentation state
     - Parameter contentRect: The initial content frame of the window
     - Parameter content: The displayed content
     **/
  func floatingPanel<Content: View>(
    isPresented: Binding<Bool>,
    contentRect: CGRect = CGRect(x: 0, y: 0, width: 624, height: 512),
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    self.modifier(
      FloatingPanelModifier(isPresented: isPresented, contentRect: contentRect, view: content))
  }
}

/// Add a  ``FloatingPanel`` to a view hierarchy
private struct FloatingPanelModifier<PanelContent: View>: ViewModifier {
  /// Determines wheter the panel should be presented or not
  @Binding var isPresented: Bool

  /// Determines the starting size of the panel
  var contentRect: CGRect = CGRect(x: 0, y: 0, width: 624, height: 512)

  /// Holds the panel content's view closure
  @ViewBuilder let view: () -> PanelContent

  /// Stores the panel instance with the same generic type as the view closure
  @State var panel: FloatingPanel<PanelContent>?

  func body(content: Content) -> some View {
    content
      .onAppear {
        /// When the view appears, create, center and present the panel if ordered
        panel = FloatingPanel(view: view, contentRect: contentRect, isPresented: $isPresented)
        panel?.center()
        if isPresented {
          present()
        }
      }
      .onDisappear {
        /// When the view disappears, close and kill the panel
        panel?.close()
        panel = nil
      }
      .onChange(of: isPresented) { value in
        /// On change of the presentation state, make the panel react accordingly
        if value {
          present()
        } else {
          panel?.close()
        }
      }
  }

  /// Present the panel and make it the key window
  func present() {
    panel?.orderFrontRegardless()
    panel?.makeKey()
    panel?.makeMain()
  }
}

struct UpdateSizeAction {
  typealias Action = (_ size: CGSize) -> Void

  let action: Action

  func callAsFunction(size: CGSize) {
    action(size)
  }
}

private struct UpdateSizeKey: EnvironmentKey {
  static var defaultValue: UpdateSizeAction?
}

extension EnvironmentValues {
  var updateSize: UpdateSizeAction? {
    get { self[UpdateSizeKey.self] }
    set { self[UpdateSizeKey.self] = newValue }
  }
}

extension View {
  /// Adds an action to perform when a child view reports that it has resized.
  /// - Parameter action: The action to perform.
  func onSizeUpdate(_ action: @escaping (_ size: CGSize) -> Void) -> some View {
    let action = UpdateSizeAction { size in
      action(size)
    }

    return environment(\.updateSize, action)
  }
}

/// A view modifier that reads the size of its content and posts a notification when
/// the size changes.
///
/// When the parent of the view affected by this modifier updates its size, `RootViewModifier`
/// expands the view to fill the available space, aligning its content to the top. When the window
/// the view is contained in changes scene phase, the current phase is provided through the
/// `scenePhase` environment key.
///
/// When applied, the affected view ignores all safe areas so as to fill the space usually occupied
/// by the title bar.
struct RootViewModifier: ViewModifier {
  @Environment(\.updateSize) private var updateSize

  @State private var scenePhase: ScenePhase = .background

  let windowTitle: String

  func body(content: Content) -> some View {
    content
      .environment(\.scenePhase, scenePhase)
      .edgesIgnoringSafeArea(.all)
      .background(
        GeometryReader { geometry in
          Color.clear
            .onAppear {
              updateSize?(size: geometry.size)
            }
            .onChange(of: geometry.size) { newValue in
              updateSize?(size: geometry.size)
            }
        }
      )
      .fixedSize()
      .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
        notification in
        guard let window = notification.object as? NSWindow, window.title == windowTitle,
          scenePhase != .active
        else {
          return
        }

        scenePhase = .active
      }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
        notification in
        guard let window = notification.object as? NSWindow, window.title == windowTitle,
          scenePhase != .background
        else {
          return
        }

        scenePhase = .background
      }
  }
}

final class FluidMenuBarExtraWindow<Content: View>: NSPanel {
  private let content: () -> Content

  private lazy var visualEffectView: NSVisualEffectView = {
    let view = NSVisualEffectView()
    view.blendingMode = .behindWindow
    view.state = .active
    view.material = .popover
    view.translatesAutoresizingMaskIntoConstraints = true
    return view
  }()

  private var rootView: some View {
    content()
      .modifier(RootViewModifier(windowTitle: title))
      .onSizeUpdate { [weak self] size in
        self?.contentSizeDidUpdate(to: size)
      }
  }

  private lazy var hostingView: NSHostingView<some View> = {
    let view = NSHostingView(rootView: rootView)
    // Disable NSHostingView's default automatic sizing behavior.
    if #available(macOS 13.0, *) {
      view.sizingOptions = []
    }
    view.isVerticalContentSizeConstraintActive = false
    view.isHorizontalContentSizeConstraintActive = false
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  init(title: String, content: @escaping () -> Content) {
    self.content = content

    super
      .init(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )

    self.title = title

    isMovable = false
    isMovableByWindowBackground = false
    isFloatingPanel = true
    level = .statusBar
    isOpaque = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true

    animationBehavior = .none
    if #available(macOS 13.0, *) {
      collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    } else {
      collectionBehavior = [.stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    }
    isReleasedWhenClosed = false
    hidesOnDeactivate = false

    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    contentView = visualEffectView
    visualEffectView.addSubview(hostingView)
    setContentSize(hostingView.intrinsicContentSize)

    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
      hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
      hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
      hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
    ])
  }

  private func contentSizeDidUpdate(to size: CGSize) {
    var nextFrame = frame
    let previousContentSize = contentRect(forFrameRect: frame).size

    let deltaX = size.width - previousContentSize.width
    let deltaY = size.height - previousContentSize.height

    nextFrame.origin.y -= deltaY
    nextFrame.size.width += deltaX
    nextFrame.size.height += deltaY

    guard frame != nextFrame else {
      return
    }

    DispatchQueue.main.async { [weak self] in
      self?.setFrame(nextFrame, display: true, animate: true)
    }
  }
}

struct VisualEffectView: NSViewRepresentable {
  var material: NSVisualEffectView.Material
  var blendingMode: NSVisualEffectView.BlendingMode

  func makeNSView(context: Context) -> NSVisualEffectView {
    context.coordinator.visualEffectView
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    context.coordinator.update(
      material: material,
      blendingMode: blendingMode
    )
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator {
    let visualEffectView = NSVisualEffectView()

    init() {
      visualEffectView.blendingMode = .withinWindow
    }

    func update(
      material: NSVisualEffectView.Material,
      blendingMode: NSVisualEffectView.BlendingMode
    ) {
      visualEffectView.material = material
      visualEffectView.blendingMode = blendingMode
    }
  }
}

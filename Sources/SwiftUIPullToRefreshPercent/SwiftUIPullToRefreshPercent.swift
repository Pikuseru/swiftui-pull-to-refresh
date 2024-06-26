import SwiftUI

// There are two type of positioning views - one that scrolls with the content,
// and one that stays fixed
private enum PositionType {
    case fixed
    case moving
}

// This struct is the currency of the Preferences, and has a type
// (fixed or moving) and the actual Y-axis value.
// It's Equatable because Swift requires it to be.
private struct Position: Equatable {
    let type: PositionType
    let y: CGFloat
}

// This might seem weird, but it's necessary due to the funny nature of
// how Preferences work. We can't just store the last position and merge
// it with the next one - instead we have a queue of all the latest positions.
private struct PositionPreferenceKey: PreferenceKey {
    typealias Value = [Position]

    static var defaultValue = [Position]()

    static func reduce(value: inout [Position], nextValue: () -> [Position]) {
        value.append(contentsOf: nextValue())
    }
}

private struct PositionIndicator: View {
    let type: PositionType

    var body: some View {
        GeometryReader { proxy in
            // the View itself is an invisible Shape that fills as much as possible
            Color.clear
                // Compute the top Y position and emit it to the Preferences queue
                .preference(key: PositionPreferenceKey.self, value: [Position(type: type, y: proxy.frame(in: .global).minY)])
        }
    }
}

// Callback that'll trigger once refreshing is done
public typealias RefreshComplete = () -> Void

// The actual refresh action that's called once refreshing starts. It has the
// RefreshComplete callback to let the refresh action let the View know
// once it's done refreshing.
public typealias OnRefresh = (@escaping RefreshComplete) -> Void

// The offset threshold. 68 is a good number, but you can play
// with it to your liking.
public let defaultRefreshThreshold: CGFloat = 68

// Tracks the state of the RefreshableScrollView - it's either:
// 1. waiting for a scroll to happen
// 2. has been primed by pulling down beyond THRESHOLD
// 3. is doing the refreshing.
public enum RefreshState {
    case waiting
    case primed
    case loading
}

// ViewBuilder for the custom progress View, that may render itself
// based on the current RefreshState and a % value in the range 0...100
public typealias RefreshProgressBuilder<Progress: View> = (RefreshState, Int) -> Progress

// Default color of the rectangle behind the progress spinner
public let defaultLoadingViewBackgroundColor = Color(UIColor.systemBackground)

public struct RefreshableScrollView<Progress, Content>: View where Progress: View, Content: View {
    let showsIndicators: Bool // if the ScrollView should show indicators
    let showsContentUnderProgressWhenLoading: Bool // if we want to show the content underneath the progress spinner when loading
    let shouldTriggerHapticFeedback: Bool // if key actions should trigger haptic feedback
    let loadingViewBackgroundColor: Color
    let threshold: CGFloat // what height do you have to pull down to trigger the refresh
    let onRefresh: OnRefresh // the refreshing action
    let progress: RefreshProgressBuilder<Progress> // custom progress view
    let content: Content // the ScrollView content
    @State private var offset: CGFloat = 0
    @State private var percent = 0
    @State private var state = RefreshState.waiting // the current state

    // Haptic Feedback
    let finishedReloadingFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    let primedFeedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // We use a custom constructor to allow for usage of a @ViewBuilder for the content
    public init(
        showsIndicators: Bool = true,
        showsContentUnderProgressWhenLoading: Bool = true,
        shouldTriggerHapticFeedback: Bool = false,
        loadingViewBackgroundColor: Color = defaultLoadingViewBackgroundColor,
        threshold: CGFloat = defaultRefreshThreshold,
        onRefresh: @escaping OnRefresh,
        @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>,
        @ViewBuilder content: () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.showsContentUnderProgressWhenLoading = showsContentUnderProgressWhenLoading
        self.shouldTriggerHapticFeedback = shouldTriggerHapticFeedback
        self.loadingViewBackgroundColor = loadingViewBackgroundColor
        self.threshold = threshold
        self.onRefresh = onRefresh
        self.progress = progress
        self.content = content()
    }

    public var body: some View {
        // The root view is a regular ScrollView
        ScrollView(showsIndicators: showsIndicators) {
            // The moving positioning indicator, that sits at the top
            // of the ScrollView and scrolls down with the content
            PositionIndicator(type: .moving)
                .frame(height: 0)

            // Bung the content below the progress when loading.
            if state == .loading, showsContentUnderProgressWhenLoading {
                Spacer().frame(height: threshold)
            }

            // Your ScrollView content.
            content
                .overlay(alignment: .top) {
                    // to avoid quirks with the layout of child views in the
                    // content, we use an overlay that sits above the content
                    ZStack {
                        Rectangle()
                            .foregroundColor(loadingViewBackgroundColor)
                            .frame(height: threshold)
                        progress(state, percent)
                    }
                    .offset(y: -threshold)
                }
        }
        // Put a fixed PositionIndicator in the background so that we have
        // a reference point to compute the scroll offset.
        .background(PositionIndicator(type: .fixed))
        // Once the scrolling offset changes, we want to see if there should
        // be a state change.
        .onPreferenceChange(PositionPreferenceKey.self) { values in
            DispatchQueue.main.async {
                // Compute the offset between the moving and fixed PositionIndicators
                let movingY = values.first { $0.type == .moving }?.y ?? 0
                let fixedY = values.first { $0.type == .fixed }?.y ?? 0
                offset = movingY - fixedY
                // scaling 0...1 to 0...100 improves scrolling performance
                // assuming because it reduces the number of state changes
                percent = Int(max(min(Double(offset / threshold), 1), 0) * 100)
                if state != .loading { // If we're already loading, ignore everything
                    // Map the preference change action to the UI thread

                    // If the user pulled down below the threshold, prime the view
                    if offset > threshold && state == .waiting {
                        state = .primed
                        if shouldTriggerHapticFeedback {
                            primedFeedbackGenerator.impactOccurred()
                        }

                        // If the view is primed and we've crossed the threshold again on the
                        // way back, trigger the refresh
                    } else if offset < threshold && state == .primed {
                        state = .loading
                        onRefresh { // trigger the refreshing callback
                            // once refreshing is done, smoothly move the loading view
                            // back to the offset position
                            withAnimation {
                                state = .waiting
                            }
                            if shouldTriggerHapticFeedback {
                                finishedReloadingFeedbackGenerator.impactOccurred()
                            }
                        }
                    }
                }
            }
        }
    }
}

// Extension that uses default RefreshActivityIndicator so that you don't have to
// specify it every time.
extension RefreshableScrollView where Progress == RefreshActivityIndicator {
    public init(
        showsIndicators: Bool = true,
        loadingViewBackgroundColor: Color = defaultLoadingViewBackgroundColor,
        threshold: CGFloat = defaultRefreshThreshold,
        onRefresh: @escaping OnRefresh,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            showsIndicators: showsIndicators,
            loadingViewBackgroundColor: loadingViewBackgroundColor,
            threshold: threshold,
            onRefresh: onRefresh,
            progress: { state, _ in
                RefreshActivityIndicator(isAnimating: state == .loading) {
                    $0.hidesWhenStopped = false
                }
            },
            content: content
        )
    }
}

// Wraps a UIActivityIndicatorView as a loading spinner that works on all SwiftUI versions.
public struct RefreshActivityIndicator: UIViewRepresentable {
    public typealias UIView = UIActivityIndicatorView
    public var isAnimating: Bool = true
    public var configuration = { (_: UIView) in }

    public init(isAnimating: Bool, configuration: ((UIView) -> Void)? = nil) {
        self.isAnimating = isAnimating
        if let configuration {
            self.configuration = configuration
        }
    }

    public func makeUIView(context: UIViewRepresentableContext<Self>) -> UIView {
        UIView()
    }

    public func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<Self>) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
        configuration(uiView)
    }
}

extension RefreshActivityIndicator {
    /// Masks the underlying UIActivityIndicatorView with
    /// circle segments to recreate the UIRefreshControl
    /// effect of appearing capsules.
    ///
    /// Assumes the activity indicator view is square and
    /// uses pythagoras h = √(x²+y²) to calculate radius.
    ///
    /// - Parameters:
    ///   - state: refresh state
    ///   - percent: value in the range 0...100
    /// - Returns: a masked view
    @ViewBuilder
    public func masked(
        state: RefreshState,
        percent: Int
    ) -> some View {
        mask {
            if state == .waiting {
                GeometryReader { geo in
                    Path { path in
                        let rect = geo.frame(in: .local)
                        let center = CGPoint(x: rect.midX, y: rect.midY)

                        // pythagoras
                        let halfSquared = pow(rect.width / 2, 2)
                        let radius = sqrt(halfSquared + halfSquared)

                        // these values have been picked through
                        // trial and error so we can see capsules
                        // we -90 to start at top center
                        let ratio = Double(percent) / 100
                        let start = Double(-45 / 2 - 90)
                        let end = start + floor((360 * ratio) / 45) * 45

                        // draw the segments over the capsules
                        path.move(to: center)
                        path.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .degrees(start),
                            endAngle: .degrees(end),
                            clockwise: false
                        )
                        path.addLine(to: center)
                    }.fill(Color.black)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.black
            }
        }
    }
}

// Allows using RefreshableScrollView with an async block.

extension RefreshableScrollView {
    public init(
        showsIndicators: Bool = true,
        loadingViewBackgroundColor: Color = defaultLoadingViewBackgroundColor,
        threshold: CGFloat = defaultRefreshThreshold,
        action: @escaping @Sendable () async -> Void,
        @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            showsIndicators: showsIndicators,
            loadingViewBackgroundColor: loadingViewBackgroundColor,
            threshold: threshold,
            onRefresh: { refreshComplete in
                Task {
                    await action()
                    refreshComplete()
                }
            },
            progress: progress,
            content: content
        )
    }
}

public struct RefreshableCompat<Progress>: ViewModifier where Progress: View {
    private let showsIndicators: Bool
    private let loadingViewBackgroundColor: Color
    private let threshold: CGFloat
    private let onRefresh: OnRefresh
    private let progress: RefreshProgressBuilder<Progress>

    public init(
        showsIndicators: Bool = true,
        loadingViewBackgroundColor: Color = defaultLoadingViewBackgroundColor,
        threshold: CGFloat = defaultRefreshThreshold,
        onRefresh: @escaping OnRefresh,
        @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>
    ) {
        self.showsIndicators = showsIndicators
        self.loadingViewBackgroundColor = loadingViewBackgroundColor
        self.threshold = threshold
        self.onRefresh = onRefresh
        self.progress = progress
    }

    public func body(content: Content) -> some View {
        RefreshableScrollView(
            showsIndicators: showsIndicators,
            loadingViewBackgroundColor: loadingViewBackgroundColor,
            threshold: threshold,
            onRefresh: onRefresh,
            progress: progress
        ) {
            content
        }
    }
}

extension List {
    @ViewBuilder
    public func refreshableCompat<Progress: View>(
        showsIndicators: Bool = true,
        loadingViewBackgroundColor: Color = defaultLoadingViewBackgroundColor,
        threshold: CGFloat = defaultRefreshThreshold,
        onRefresh: @escaping OnRefresh,
        @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>
    ) -> some View {
        refreshable {
            await withCheckedContinuation { cont in
                onRefresh {
                    cont.resume()
                }
            }
        }
    }
}

extension View {
    @ViewBuilder
    public func refreshableCompat<Progress: View>(
        showsIndicators: Bool = true,
        loadingViewBackgroundColor: Color = defaultLoadingViewBackgroundColor,
        threshold: CGFloat = defaultRefreshThreshold,
        onRefresh: @escaping OnRefresh,
        @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>
    ) -> some View {
        modifier(RefreshableCompat(
            showsIndicators: showsIndicators,
            loadingViewBackgroundColor: loadingViewBackgroundColor,
            threshold: threshold,
            onRefresh: onRefresh,
            progress: progress
        ))
    }
}

struct TestView: View {
    @State private var now = Date()

    var body: some View {
        RefreshableScrollView(
            onRefresh: { done in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    now = Date()
                    done()
                }
            }) {
                VStack {
                    ForEach(1 ..< 20) {
                        Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
                            .padding(.bottom, 10)
                    }
                }.padding()
            }
    }
}

struct TestViewWithMaskedLargeRefreshActivityIndicator: View {
    @State private var now = Date()

    var body: some View {
        RefreshableScrollView(
            onRefresh: { done in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    now = Date()
                    done()
                }
            }, progress: { state, percent in
                RefreshActivityIndicator(isAnimating: state == .loading) {
                    $0.hidesWhenStopped = false
                    $0.style = .large
                }.masked(state: state, percent: percent)
            }
        ) {
            VStack {
                ForEach(1 ..< 20) {
                    Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
                        .padding(.bottom, 10)
                }
            }.padding()
        }
    }
}

struct TestViewWithMaskedMediumRefreshActivityIndicator: View {
    @State private var now = Date()

    var body: some View {
        RefreshableScrollView(
            onRefresh: { done in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    now = Date()
                    done()
                }
            }, progress: { state, percent in
                RefreshActivityIndicator(isAnimating: state == .loading) {
                    $0.hidesWhenStopped = false
                }.masked(state: state, percent: percent)
            }
        ) {
            VStack {
                ForEach(1 ..< 20) {
                    Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
                        .padding(.bottom, 10)
                }
            }.padding()
        }
    }
}

struct TestViewWithLargerThreshold: View {
    @State private var now = Date()

    var body: some View {
        RefreshableScrollView(
            threshold: defaultRefreshThreshold * 3,
            onRefresh: { done in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    now = Date()
                    done()
                }
            }
        ) {
            VStack {
                ForEach(1 ..< 20) {
                    Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
                        .padding(.bottom, 10)
                }
            }.padding()
        }
    }
}

struct TestViewWithCustomProgress: View {
    @State private var now = Date()

    var body: some View {
        RefreshableScrollView(
            onRefresh: { done in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    now = Date()
                    done()
                }
            },
            progress: { state, percent in
                if state == .waiting {
                    Text("Pull me down... \(percent)")
                } else if state == .primed {
                    Text("Now release!")
                } else {
                    Text("Working...")
                }
            }
        ) {
            VStack {
                ForEach(1 ..< 20) {
                    Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
                        .padding(.bottom, 10)
                }
            }.padding()
        }
    }
}

struct TestViewWithAsync: View {
    @State private var now = Date()

    var body: some View {
        RefreshableScrollView(action: {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            now = Date()
        }, progress: { state, _ in
            RefreshActivityIndicator(isAnimating: state == .loading) {
                $0.hidesWhenStopped = false
            }
        }) {
            VStack {
                ForEach(1 ..< 20) {
                    Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
                        .padding(.bottom, 10)
                }
            }.padding()
        }
    }
}

struct TestViewCompat: View {
    @State private var now = Date()

    var body: some View {
        VStack {
            ForEach(1 ..< 20) {
                Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
                    .padding(.bottom, 10)
            }
        }
        .refreshableCompat(
            showsIndicators: false,
            onRefresh: { done in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    now = Date()
                    done()
                }
            },
            progress: { state, _ in
                RefreshActivityIndicator(isAnimating: state == .loading) {
                    $0.hidesWhenStopped = false
                }
            }
        )
    }
}

struct TestView_Previews: PreviewProvider {
    static var previews: some View {
        TestView()
    }
}

struct TestViewWithMaskedLargeRefreshActivityIndicator_Previews: PreviewProvider {
    static var previews: some View {
        TestViewWithMaskedLargeRefreshActivityIndicator()
    }
}

struct TestViewWithMaskedMediumRefreshActivityIndicator_Previews: PreviewProvider {
    static var previews: some View {
        TestViewWithMaskedMediumRefreshActivityIndicator()
    }
}

struct TestViewWithLargerThreshold_Previews: PreviewProvider {
    static var previews: some View {
        TestViewWithLargerThreshold()
    }
}

struct TestViewWithCustomProgress_Previews: PreviewProvider {
    static var previews: some View {
        TestViewWithCustomProgress()
    }
}

struct TestViewWithAsync_Previews: PreviewProvider {
    static var previews: some View {
        TestViewWithAsync()
    }
}

struct TestViewCompat_Previews: PreviewProvider {
    static var previews: some View {
        TestViewCompat()
    }
}

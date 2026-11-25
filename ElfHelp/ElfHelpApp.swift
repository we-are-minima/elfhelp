import SwiftUI
import StoreKit
import UserNotifications
import UIKit
import ImageIO
import NaturalLanguage
import CoreText

private let accent = Color(red: 0.97, green: 0.12, blue: 0.20)
private let pink = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.28, green: 0.16, blue: 0.23, alpha: 1)
        : UIColor(red: 1, green: 0.89, blue: 0.93, alpha: 1)
})
private let pinkCardText = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.83, blue: 0.91, alpha: 1)
        : UIColor(red: 0.39, green: 0.10, blue: 0.24, alpha: 1)
})

@main
struct ElfHelpApp: App {
    @UIApplicationDelegateAdaptor(ReminderDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { Home().tint(.primary).buttonStyle(GlassControl()) }
    }
}

final class ReminderDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let day = response.notification.request.content.userInfo["day"] as? Int {
            await MainActor.run {
                UserDefaults.standard.set(day, forKey: "reminderDay")
                NotificationCenter.default.post(name: .openReminder, object: nil)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

private extension Notification.Name {
    static let openReminder = Notification.Name("openReminder")
}

private enum Panel: Identifiable {
    case idea(Trastada), day(Int), calendar, settings, setup, filters, club, closing, review(Int), promotion(AppPromotion)

    var id: String {
        switch self {
        case .idea(let idea): "idea-\(idea.id)"
        case .day(let day): "day-\(day)"
        case .calendar: "calendar"
        case .settings: "settings"
        case .setup: "setup"
        case .filters: "filters"
        case .club: "club"
        case .closing: "closing"
        case .review(let day): "review-\(day)"
        case .promotion(let promotion): "promotion-\(promotion.id)"
        }
    }
}

private enum SetupStep: Int {
    case introduction = 1, reminders, loading
}

private enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "Sistema", light = "Claro", dark = "Oscuro"
    var id: Self { self }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct LaunchArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 414, geometry.size.height / 896)
            ZStack(alignment: .topLeading) {
                Image("SplashElf")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 414, height: 480)
                    .offset(x: 0, y: 281)
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 307, height: 197.17)
                    .offset(x: 65, y: 105)
                Image("SplashTagline")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 324, height: 35)
                    .offset(x: 45, y: 803)
                Image("SplashHat")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .offset(x: -80, y: -10)
                Image("SplashCandy")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .offset(x: 260, y: 25)
                Image("SplashSock")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .offset(x: -72, y: 260)
                Image("SplashMug")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 135, height: 135)
                    .offset(x: 326, y: 274)
                Image("SplashWC")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .offset(x: 280, y: 638)
                Image("SplashStarBalloon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 145, height: 145)
                    .offset(x: -79, y: 715)
                Image("SplashStar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 53.33)
                    .offset(x: 47, y: 153)
                Image("SplashStar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 33.33)
                    .offset(x: 363, y: 783)
            }
            .frame(width: 414, height: 896, alignment: .topLeading)
            .clipped()
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 414 * scale, height: 896 * scale, alignment: .topLeading)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .background(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elf Help! ¡Que cunda la magia!")
    }
}

private struct Home: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("plan2026") private var savedPlan = Data()
    @AppStorage("illustratedCalendar2026Applied") private var starterPlanApplied = false
    @AppStorage("initialSetupComplete") private var initialSetupComplete = false
    @AppStorage("catalogFilterPreferences") private var savedFilters = Data()
    @State private var showSplash = true
    @State private var setupStep: SetupStep = .introduction
    @State private var handTapCount = 0
    @State private var hasScrolledHome = false
    @State private var keyboardVisible = false
    @State private var homeViewportHeight: CGFloat = 0
    @State private var promptedReviewDay: Int?
    @State private var promotionPreviewDismissed = false
    /// Minimax preview card is hidden for now; set to true to show it again in DEBUG builds.
    private let showsPromotionPreview = false
    @Environment(\.requestReview) private var requestAppReview
    @AppStorage("firstUseTimestamp") private var firstUseTimestamp = 0.0
    @AppStorage("ratingMilestones") private var ratingMilestones = ""
    @AppStorage("seenPromotions") private var seenPromotions = ""
    @State private var ratingTask: Task<Void, Never>?
    @State private var sharedTravesura: SharedTravesura?
    @State private var setupShownThisLaunch = false
    @State private var planReady = false
    @AppStorage("planningWeekdays") private var planningWeekdays = 127
    @AppStorage("firstPlanningDay") private var firstPlanningDay = 1
    @AppStorage("lastPlanningDay") private var lastPlanningDay = 24

    private var planningDays: ClosedRange<Int> { firstPlanningDay...lastPlanningDay }

    private var shouldShowSetup: Bool {
        #if DEBUG
        return !setupShownThisLaunch
        #else
        return !initialSetupComplete
        #endif
    }

    private func canEdit(_ day: Int) -> Bool {
        planningDays.contains(day) && includesWeekday(day, mask: planningWeekdays)
            && edition.canEdit(day, now: Self.planningDate)
    }
    @State private var elfPreference = "1 elfo"
    @State private var requestingReminders = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMinutes") private var reminderMinutes = 1320
    @AppStorage("clubModalCount") private var clubModalCount = 0
    @AppStorage("clubModalDay") private var clubModalDay = 0
    @AppStorage("closingSeen") private var closingSeen = false
    @State private var panel: Panel?
    @State private var calendarDetailPage: Int?
    @State private var confirmedDay: Int?
    @State private var confirmationCount = 0
    @State private var showsConfirmation = false
    @State private var assignmentDay: Int?
    @State private var browsingCatalog = false
    @State private var surpriseRound: SurpriseRound?
    @State private var flippedDay: Int?
    @State private var homePositionReady = false
    @State private var focusedDay: Int?
    @State private var replacing: Trastada?
    @State private var replacementDay: Int?
    @State private var now = Self.planningDate

    private static var planningDate: Date {
        #if DEBUG
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 10))!
        #else
        Date()
        #endif
    }
    @State private var reminderTask: Task<Void, Never>?
    private let edition = DecemberEdition(year: 2026)
    @ObservedObject private var catalogStore = CatalogStore.shared
    private var catalog: [Trastada] { catalogStore.items }

    private var illustratedCatalog: [Trastada] {
        catalog.filter(Artwork.hasPhoto)
    }

    private var storedPlan: DecemberPlan {
        var saved = PlanDecodingCache.value(for: savedPlan)
        saved.assignments = saved.assignments.filter { DecemberEdition.pages.contains($0.key) }
        return saved
    }

    private var plan: DecemberPlan {
        var current = storedPlan
        if !starterPlanApplied {
            current.fillStarterDays(from: illustratedCatalog, matching: filterSelection, days: DecemberEdition.pages)
        }
        return current
    }

    private var filtersActive: Bool { !filterSelection.selections.isEmpty }

    private var appStoreURL: URL? { configuredURL("ElfStoreURL") }
    private var clubURL: URL? { configuredURL("ElfClubURL") }

    private var screenTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 12, y: 0)),
            removal: .opacity
        )
    }

    private var screenAnimation: Animation {
        .easeInOut(duration: reduceMotion ? 0.18 : 0.30)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if assignmentDay != nil || browsingCatalog {
                    ScrollView {
                        VStack(spacing: 10) {
                            ideaList
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        header
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    .modifier(CatalogBackdrop(ideas: listIdeas))
                    .id(scrollContext)
                    .transition(screenTransition)
                } else {
                    VStack(spacing: 0) {
                        header
                            .disabled(surpriseRound != nil)
                        dailyHome
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .background {
                        FloatingDecorations(
                            idea: idea(on: selectedDay),
                            showsDecorations: false,
                            showsSnow: surpriseRound == nil && panel == nil && !showSplash
                        )
                    }
                    .transition(screenTransition)
                }
            }
            .task(id: confirmationCount) {
                guard confirmationCount > 0 else { return }
                do {
                    try await Task.sleep(for: .milliseconds(420))
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.8)) { showsConfirmation = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    UIAccessibility.post(notification: .announcement, argument: "Idea sustituida con éxito")
                    try await Task.sleep(for: .seconds(3))
                    withAnimation(.easeInOut(duration: 0.22)) { showsConfirmation = false }
                } catch { return }
            }
            .animation(screenAnimation, value: scrollContext)
            .background(Color(uiColor: .systemBackground))
            .accessibilityHidden(showSplash || surpriseRound != nil)
            .overlay {
                if let round = surpriseRound {
                    GeometryReader { space in
                        IdeaBoard(ideas: round.ideas, size: space.size, day: round.day, date: edition.date(round.day), cancel: {
                            surpriseRound = nil
                        }, select: { idea in
                            commit(idea, to: round.day)
                            surpriseRound = nil
                        })
                        .accessibilityAddTraits(.isModal)
                    }
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.975, anchor: .bottom)),
                        removal: .opacity
                    ))
                }
            }
            .animation(.easeInOut(duration: reduceMotion ? 0.18 : 0.36),
                       value: surpriseRound != nil)
            .overlay {
                if showSplash {
                    LaunchArtwork()
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .animation(screenAnimation, value: showSplash)
            .fullScreenCover(isPresented: Binding(
                get: { panel?.id == "setup" },
                set: { if !$0, panel?.id == "setup" { panel = nil } }
            ), onDismiss: { activate() }) {
                panelContent(.setup)
            }
            .sheet(item: Binding(
                get: { panel?.id == "setup" || panel?.id.hasPrefix("review-") == true ? nil : panel },
                set: { if panel?.id != "setup" { panel = $0 } }
            ), onDismiss: {
                calendarDetailPage = nil
                activate()
            }) { current in
                NavigationStack {
                    panelContent(current)
                        .navigationDestination(for: Trastada.self) { idea in
                            detail(idea, day: nil)
                                .toolbar {
                                    ToolbarItem(placement: .principal) { detailHeading("La idea") }
                                }
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                if current.id != "setup" {
                                    Button { panel = nil } label: {
                                        Image(systemName: "xmark")
                                            .font(.body.weight(.semibold))
                                    }
                                    .buttonStyle(HapticPlainStyle())
                                    .foregroundStyle(current.id == "settings" || current.id == "filters" ? Color.primary : Color.white)
                                    .accessibilityLabel("Cerrar")
                                }
                            }
                        }
                }
                .tint(.primary)
                .buttonStyle(GlassControl())
                .presentationBackground {
                    if current.id == "settings" || current.id == "filters" {
                        Color(uiColor: .systemGroupedBackground)
                    } else {
                        FrostedBackdrop()
                    }
                }
                .presentationDetents(current.id.hasPrefix("review-") ? [.medium, .large] : [.large])
                .interactiveDismissDisabled(current.id == "setup")
            }
            .confirmationDialog(
                "¿Cambiar la travesura del día \(replacementDay ?? 0)?",
                isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
                titleVisibility: .visible
            ) {
                Button("Sustituir travesura") {
                    AppHaptics.tap()
                    if let replacing, let replacementDay { commit(replacing, to: replacementDay) }
                    replacing = nil
                }
                Button("Cancelar", role: .cancel) { AppHaptics.tap(); replacing = nil }
            } message: {
                if let replacementDay, let existing = idea(on: replacementDay) { Text(existing.title) }
            }
        }
        .sheet(item: $sharedTravesura) { payload in
            TravesuraShareSheet(payload: payload)
        }
        .overlay {
            ZStack(alignment: .bottom) {
                if case .review(let day) = panel {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { submitReview(day: day, outcome: .skipped) }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    panelContent(.review(day))
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { submitReview(day: day, outcome: .skipped) }
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.35), value: panel?.id.hasPrefix("review-") == true)
        }
        .preferredColorScheme(appearance.colorScheme)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            if showSplash {
                await Task.yield()
                guard !Task.isCancelled else { return }
                showSplash = false
            }
            activate()
            PlanSync.shared.schedule(savedPlan, year: edition.year)
            await catalogStore.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            keyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                activate()
                Task { await catalogStore.refresh() }
            }
        }
        .onChange(of: savedPlan) { _, data in PlanSync.shared.schedule(data, year: edition.year) }
        .onReceive(NotificationCenter.default.publisher(for: .openReminder)) { _ in activate() }
    }

    private var header: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(height: 106)
            .accessibilityLabel("Elf help!")
            .frame(maxWidth: 176)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if assignmentDay != nil || browsingCatalog {
                    Button("Volver", systemImage: "chevron.left", action: returnFromIdeaList)
                        .labelStyle(.iconOnly)
                        .buttonStyle(GlassControl(iconOnly: true))
                } else {
                    Button("Ajustes", systemImage: "gearshape") { panel = .settings }
                    .labelStyle(.iconOnly)
                    .buttonStyle(GlassControl(iconOnly: true))
                }
            }
    }

    private var scrollContext: String {
        if let assignmentDay { return "assignment-\(assignmentDay)" }
        if browsingCatalog { return "catalog" }
        return "daily"
    }

    private var selectedDay: Int { focusedDay ?? (now < edition.date(1) ? 0 : edition.stripFocus(now)) }

    private var dailyHome: some View {
        GeometryReader { space in
            let cardWidth = space.size.width
            let cardHeight = max(0, min(space.size.height * 0.74, cardWidth * dayPhotoRatio * 1.1))
            dailyCards(width: cardWidth, height: cardHeight, viewportHeight: space.size.height)
                .allowsHitTesting(surpriseRound == nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { if !keyboardVisible { homeViewportHeight = space.size.height } }
                .onChange(of: space.size.height) { _, height in
                    if !keyboardVisible { homeViewportHeight = height }
                }
        }
        .frame(height: keyboardVisible && homeViewportHeight > 0 ? homeViewportHeight : nil, alignment: .top)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .mask {
            GeometryReader { space in
                let fade = flippedDay == nil ? 0.13 : min(0.025, 12 / max(1, space.size.height))
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.15), location: fade * 0.3),
                    .init(color: .black.opacity(0.65), location: fade * 0.7),
                    .init(color: .black, location: fade),
                    .init(color: .black, location: 1 - fade),
                    .init(color: .black.opacity(0.65), location: 1 - fade * 0.7),
                    .init(color: .black.opacity(0.15), location: 1 - fade * 0.3),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .padding(.horizontal, -48)
            }
        }
        .overlay {
            if selectedDay == 0 && !hasScrolledHome {
                GeometryReader { space in
                    let cardHeight = max(0, min(space.size.height * 0.74, space.size.width * dayPhotoRatio * 1.1))
                    ScrollHandHint()
                        .position(x: space.size.width / 2,
                                  y: (space.size.height + cardHeight) / 2 + 24 + 20)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay {
            if showsConfirmation {
                GeometryReader { space in
                    let cardHeight = max(0, min(space.size.height * 0.74, space.size.width * dayPhotoRatio * 1.1))
                    let snackbarY = min(space.size.height - 24, (space.size.height + cardHeight) / 2 + 36)
                    if !reduceMotion {
                        SuccessConfetti()
                            .frame(height: 200)
                            .position(x: space.size.width / 2, y: snackbarY + 75)
                    }
                    Label("Travesura cambiada", systemImage: "checkmark.circle.fill")
                        .modifier(AppTypography.selection)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ideaControlTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .modifier(GlassSurface(prominent: false, radius: 16, interactive: false))
                        .position(x: space.size.width / 2,
                                  y: snackbarY)
                }
                .allowsHitTesting(false)
                .transition(reduceMotion ? .opacity : .offset(y: 8).combined(with: .opacity))
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
            if !hasScrolledHome {
                withAnimation(.easeOut(duration: 0.15)) { hasScrolledHome = true }
            }
        })
        .onChange(of: selectedDay) { flippedDay = nil }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.85), trigger: selectedDay)
    }

    private var showsFarewellCard: Bool {
        #if DEBUG
        true
        #else
        now >= edition.date(24)
        #endif
    }

    private var promotionPreview: some View {
        VStack(spacing: 20) {
            HStack {
                Text("MINIMAX · VISTA PREVIA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    focusedDay = 1
                    promotionPreviewDismissed = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassControl(iconOnly: true))
                .accessibilityLabel("Cerrar promoción")
            }
            Image("SplashElf")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("Que siga la magia")
                .systemHeading(.largeTitle)
            Text("Descubre nuevas formas de compartir momentos especiales en familia con Minimax.")
                .modifier(AppTypography.body)
            Link("Descubrir Minimax", destination: URL(string: "https://www.heyminimax.com")!)
                .modifier(PrimaryIdeaControl(animated: false))
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
    }

    private func dailyCards(width: CGFloat, height: CGFloat, viewportHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 16) {
                    VStack(spacing: 25) {
                        Text("Un poco de magia cada día")
                            .modifier(AppTypography(name: "NewKansasSwash-MediumItalic", size: 28, relativeTo: .title2))
                            .frame(maxWidth: 272)
                            .accessibilityAddTraits(.isHeader)
                        Text("Desliza hacia arriba para descubrir la travesura que hemos elegido para cada día, del 1 al 24 de diciembre. Aprende cómo se hacen o cámbialas por las que más te gusten.")
                            .modifier(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("¡Empezamos!") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                focusedDay = 1
                            }
                        }
                        .modifier(PrimaryIdeaControl(animated: false))
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(24)
                    .frame(width: width, height: height)
                    .modifier(DayCardFrame(alignment: .center, inset: 0))
                    .id(0)
                    #if DEBUG
                    if showsPromotionPreview && !promotionPreviewDismissed {
                        promotionPreview
                            .padding(24)
                            .frame(width: width, height: height)
                            .modifier(DayCardFrame(alignment: .center, inset: 0))
                            .id(-1)
                    }
                    #endif
                    ForEach(DecemberEdition.pages, id: \.self) { day in
                        let cardHeight = flippedDay == day ? max(height, viewportHeight * 0.94) : height
                        dailyCard(page: day, height: cardHeight)
                            .frame(width: width, height: cardHeight)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: flippedDay)
                            .modifier(AssignmentCelebration(trigger: day == confirmedDay ? confirmationCount : 0))
                            .shadow(color: .black.opacity(0.24), radius: 12, y: 3)
                            .scrollTransition(.interactive, axis: .vertical) { [reduceMotion] card, phase in
                                let progress = abs(phase.value)
                                return card
                                    .scaleEffect(reduceMotion ? 1 : 1 - 0.12 * progress)
                                    .opacity(1 - 0.25 * progress)
                            }
                            .id(day)
                    }
                    if showsFarewellCard {
                        ScrollView {
                            ChristmasFarewell()
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: max(0, height - 48))
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .padding(24)
                        .frame(width: width, height: height)
                        .modifier(DayCardFrame(alignment: .center, inset: 0))
                        .id(25)
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: .infinity)
            }
            .contentMargins(.vertical, max(0, (viewportHeight - (flippedDay == nil ? height : max(height, viewportHeight * 0.94))) / 2), for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: Binding<Int?>(
                get: { selectedDay },
                set: { if homePositionReady, let day = $0, day != selectedDay { focusedDay = day } }
            ), anchor: .center)
            .frame(height: viewportHeight)
            .task(id: viewportHeight) {
                homePositionReady = false
                let target = selectedDay
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(target, anchor: .center)
                await Task.yield()
                homePositionReady = true
            }
            .onChange(of: flippedDay) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    proxy.scrollTo(selectedDay, anchor: .center)
                }
            }
        }
    }

    private func dailyCard(page: Int, height: CGFloat) -> some View {
        let active = page == selectedDay
        let day = page
        let date = edition.calendarDate(for: page)
        let assigned = idea(on: day)
        let editable = canEdit(day)
        let isPastDay = edition.calendar.startOfDay(for: date) < edition.calendar.startOfDay(for: now)
        let completed = plan.reviews?[day].map { $0.outcome != .skipped } ?? false
        let preview = catalog.indices.contains(day - 1) ? catalog[day - 1] : nil

        return Group {
            if let idea = assigned {
                let flipped = flippedDay == day && active
                ZStack {
                    Button { flippedDay = day } label: {
                        CardPhoto(
                            idea: idea, height: height,
                            captionInset: cardBarControlHeight + cardIconInset + 26,
                            showsPlaceholder: false, showsInstructions: flipped
                        )
                    }
                    .buttonStyle(HapticPlainStyle())
                    .disabled(completed)
                    .overlay(alignment: .bottom) {
                        Group {
                            if completed {
                                Button {
                                    promptedReviewDay = day
                                    update { $0.unmarkCompleted(day: day) }
                                } label: {
                                    Label("Travesura completada", systemImage: "checkmark.circle.fill")
                                }
                                .buttonStyle(OnboardingActionStyle())
                                .accessibilityHint("Desmarca la travesura como hecha")
                            } else if isPastDay {
                                Button("Marcar travesura como hecha") {
                                    update { $0.markCompleted(day: day) }
                                }
                                .buttonStyle(OnboardingActionStyle())
                            } else {
                                HStack(spacing: 10) {
                                    Button("Cómo se hace") { flippedDay = day }
                                        .buttonStyle(OnboardingActionStyle())
                                    Button("Cambiar") { startSurprise(for: day) }
                                        .modifier(PrimaryIdeaControl(animated: false))
                                        .frame(width: 120)
                                        .disabled(!editable)
                                }
                            }
                        }
                        .padding(cardIconInset)
                        .opacity(flipped ? 0 : 1)
                        .allowsHitTesting(active && !flipped)
                        .accessibilityHidden(!active)
                    }
                    .allowsHitTesting(!flipped)
                    .accessibilityHidden(flipped)

                    if active {
                        cardBack(idea)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded {
                            guard flippedDay == day else { return }
                            AppHaptics.tap()
                            flippedDay = nil
                        })
                        .opacity(flipped ? 1 : 0)
                        .offset(y: reduceMotion || flipped ? 0 : 18)
                        .allowsHitTesting(flipped)
                        .accessibilityHidden(!flipped)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: flipped)
            } else {
                emptyDayContent(
                    day, editable: editable, preview: preview,
                    height: max(60, height - 2 * pearlCardInset - (editable ? 76 : 32)),
                    showMessage: edition.today(now) == day || edition.nextDiscovery(now) == day,
                    animated: selectedDay == page && surpriseRound == nil && panel == nil && !showSplash
                )
                .allowsHitTesting(active)
                .accessibilityHidden(!active)
            }
        }
        .modifier(DayCardFrame(alignment: .topLeading, inset: assigned == nil ? pearlCardInset : 0, radius: flippedDay == day ? 32 : pearlCardRadius))
        .overlay(alignment: .topTrailing) {
            HStack(alignment: .top) {
                cardDate(for: date)
                Spacer()
                if let assigned {
                    share(assigned, cardGlass: true)
                }
            }
            .padding(cardIconInset)
            .opacity(flippedDay == day && active ? 0 : 1)
            .allowsHitTesting(active && flippedDay != day)
            .accessibilityHidden(!active || flippedDay == day)
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.18 : 0.45), value: flippedDay)
    }

    private func cardBack(_ idea: Trastada) -> some View {
        GeometryReader { space in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Materiales")
                            .modifier(AppTypography(name: "NewKansasSwash-MediumItalic", size: 24, relativeTo: .title3))
                            .accessibilityAddTraits(.isHeader)
                        MaterialTagLayout(spacing: 8) {
                            ForEach(Array(idea.materialTags.enumerated()), id: \.offset) { _, material in
                                Text(material)
                                    .modifier(AppTypography(name: "Inter-Medium", size: 13,
                                                            relativeTo: .footnote, tracking: -0.02))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .overlay { Capsule().strokeBorder(.white, lineWidth: 1) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preparación")
                            .modifier(AppTypography(name: "NewKansasSwash-MediumItalic", size: 24, relativeTo: .title3))
                            .accessibilityAddTraits(.isHeader)
                        Text(idea.preparation)
                            .modifier(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: max(0, space.size.height - 96), alignment: .bottom)
                .padding(.horizontal, 24)
                .padding(.top, 72)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .topTrailing) {
                Button { flippedDay = nil } label: {
                    Image("CardBackClose")
                        .frame(width: 40, height: 40)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HapticPlainStyle())
                .accessibilityLabel("Volver a la foto")
                .padding(14)
            }
        }
    }

    private func farewell(day: Int) -> some View {
        ChristmasFarewell()
    }

    private func cardDate(for date: Date) -> some View {
        let locale = Locale(identifier: "es_ES")
        let weekday = date.formatted(.dateTime.weekday(.wide).locale(locale))
        return VStack(spacing: 0) {
            Text(weekday.prefix(1).uppercased(with: locale) + weekday.dropFirst())
                .modifier(AppTypography(name: "Inter-SemiBold", size: 13, relativeTo: .caption))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(LinearGradient(
                colors: [Color(red: 1, green: 0, blue: 0.17), Color(red: 0.65, green: 0, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            ))
            Text(edition.calendar.component(.day, from: date), format: .number)
                .modifier(AppTypography(name: "NewKansas-Bold", size: 40, relativeTo: .largeTitle))
                .foregroundStyle(Color(red: 0.34, green: 0.18, blue: 0.33))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .frame(width: 96)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
    }

    private var ideaList: some View {
        let options = listIdeas
        return VStack(alignment: .leading, spacing: 12) {
            Text(assignmentDay.map { "Elige la travesura para el \($0) de diciembre" } ?? "Catálogo de travesuras")
                .systemHeading(.title2)
                .accessibilityAddTraits(.isHeader)
            catalogToolbar
            if options.isEmpty { emptyResults }
            LazyVStack(spacing: 14) {
                ForEach(options) { idea in
                    ideaListCard(idea).id(idea.id)
                    if options.count > 12, options[11].id == idea.id, clubURL != nil {
                        ClubInvitation(url: clubURL, source: "catalogo")
                    }
                }
            }
            .scrollTargetLayout()
        }
    }

    private func ideaListCard(_ idea: Trastada) -> some View {
        catalogCard(idea) { photo in
            Button { panel = .idea(idea) } label: { photo }
                .buttonStyle(HapticPlainStyle())
        }
    }

    private func catalogCard<Preview: View>(
        _ idea: Trastada,
        @ViewBuilder preview: @escaping (CardPhoto) -> Preview
    ) -> some View {
        let day = plan.assignments.first(where: { $0.value == idea.id })?.key
        return GeometryReader { space in
            preview(CardPhoto(idea: idea, height: space.size.height, captionInset: day != nil ? 72 : 24))
                .overlay(alignment: .bottom) {
                    if let day {
                        Text("\(day) de diciembre")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.bottom, 14)
                    }
                }
                .modifier(DayCardFrame(alignment: .topLeading, inset: 0))
        }
        .aspectRatio(1 / dayCardHeightToWidth, contentMode: .fit)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    private var availableIdeas: [Trastada] {
        guard assignmentDay != nil else { return illustratedCatalog }
        let assigned = Set(plan.assignments.values)
        return illustratedCatalog.filter { !assigned.contains($0.id) }
    }

    private var listIdeas: [Trastada] { availableIdeas.filter(filterSelection.matches) }

    private var catalogToolbar: some View {
        HStack(spacing: 12) {
            catalogCount
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
            Button { panel = .filters } label: {
                Label(filtersActive ? "Filtros activos" : "Filtros", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(GlassControl(prominent: filtersActive))
        }
    }

    private var catalogCount: Text {
        let count = listIdeas.count
        return count == 1 ? Text("1 travesura") : Text("\(count) travesuras")
    }

    private var emptyResults: some View {
        ContentUnavailableView {
            Label("No hay travesuras disponibles", systemImage: "sparkles")
        } actions: {
            if filtersActive { Button("Restablecer filtros") { saveFilters(CatalogFilters()) } }
        }
    }

    @ViewBuilder private func panelContent(_ current: Panel) -> some View {
        switch current {
        case .idea(let idea):
            detail(idea, day: nil)
                .toolbar {
                    ToolbarItem(placement: .principal) { detailHeading("La idea") }
                }
                .navigationBarTitleDisplayMode(.inline)
        case .day(let day):
            dayDetail(page: day)
        case .calendar:
            BubbleCalendar(edition: edition, selectedDay: selectedDay, now: now, idea: { page in
                idea(on: page)
            }) { page in
                calendarDetailPage = page
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Calendario")
                        .systemHeading(.title3)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: Binding(
                get: { calendarDetailPage != nil },
                set: { if !$0 { calendarDetailPage = nil } }
            )) {
                if let page = calendarDetailPage {
                    NavigationStack {
                        dayDetail(page: page)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cerrar") { calendarDetailPage = nil }
                            }
                        }
                    }
                    .presentationBackground { FrostedBackdrop() }
                }
            }
        case .filters:
            FilterEditor(initial: filterSelection, ideas: availableIdeas, save: saveFilters)
        case .settings:
            settings
        case .setup:
            ZStack {
                initialSetup
                    .id(setupStep)
                    .transition(screenTransition)
            }
            .animation(screenAnimation, value: setupStep)
        case .club:
            VStack(spacing: 20) {
                ClubInvitation(url: clubURL, source: "modal")
                Button("Seguir explorando") { panel = nil }
            }
            .padding()
        case .promotion(let promotion):
            ScrollView {
                VStack(spacing: 24) {
                    AsyncImage(url: promotion.imageURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { ProgressView() }
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    Text(promotion.title).systemHeading(.title2)
                    Text(promotion.message).modifier(AppTypography.body)
                    Link(promotion.buttonTitle, destination: promotion.destinationURL)
                        .modifier(PrimaryIdeaControl(animated: false))
                }
                .multilineTextAlignment(.center)
                .padding(24)
            }
        case .review(let day):
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button { submitReview(day: day, outcome: .skipped) } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(GlassControl(iconOnly: true))
                    .accessibilityLabel("Cerrar. No lo hice")
                }
                // Same 16 pt gap from the top and right edges of the modal.
                .padding(.trailing, -8)
                VStack(spacing: 4) {
                    Text("¿Qué tal fue la travesura de ayer?")
                        .modifier(AppTypography(name: "Inter-SemiBold", size: 17, relativeTo: .headline))
                        .multilineTextAlignment(.center)
                    if let idea = idea(on: day) {
                        Text(idea.title).modifier(AppTypography.body).multilineTextAlignment(.center)
                    }
                }
                HStack(alignment: .top, spacing: 64) {
                    ForEach([TravesuraOutcome.incredible, .disaster], id: \.self) { outcome in
                        Button {
                            submitReview(day: day, outcome: outcome)
                        } label: {
                            VStack(spacing: 8) {
                                Image(outcome == .incredible ? "ReviewOk" : "ReviewWrong")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(6)
                                    .frame(width: 84, height: 84)
                                    .accessibilityHidden(true)
                                    .background(.black.opacity(0.15), in: Circle())
                                    .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2) }
                                Text(outcome.title)
                                    .modifier(AppTypography(name: "Inter-SemiBold", size: 13, relativeTo: .footnote))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 84)
                        }
                        .buttonStyle(HapticPlainStyle())
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 64)
            .background {
                FrostedBackdrop()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        case .closing:
            ScrollView {
                ChristmasFarewell()
                .padding(24)
            }
        }
    }

    private func submitReview(day: Int, outcome: TravesuraOutcome) {
        update { plan in
            #if DEBUG
            // Allow another QA response without clearing the saved plan on launch.
            if let previous = plan.reviews?[day] {
                if plan.assignments[day] == nil,
                   !plan.assignments.values.contains(previous.ideaID) {
                    plan.assignments[day] = previous.ideaID
                }
                if plan.assignments[day] != nil { plan.reviews?[day] = nil }
            }
            #endif
            plan.review(day: day, outcome: outcome)
        }
        panel = nil
    }

    private func dayDetail(page: Int) -> some View {
        let day = page
        let date = edition.calendarDate(for: page)
        return Group {
            if let idea = idea(on: day) {
                detail(idea, day: day)
            } else {
                emptyDay(day)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                detailHeading(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_ES"))))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var initialSetup: some View {
        Group {
            if setupStep == .loading {
                GeometryReader { space in
                    VStack(spacing: 12) {
                        Image("Logo").resizable().scaledToFit()
                            .frame(height: min(160, space.size.height * 0.25))
                            .accessibilityLabel("Elf Help!")
                        LoadingBubbleParade()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else if setupStep == .introduction {
                introductionPage
            } else {
                reminderPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            setupFooter
                .foregroundStyle(.white)
                .frame(maxWidth: 432)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
        }
        .tint(.white)
        .environment(\.colorScheme, .dark)
        .background {
            FloatingDecorations(idea: nil, showsDecorations: setupStep != .introduction, showsSnow: setupStep != .introduction)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var introductionPage: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Text("La Navidad empieza aquí")
                    .modifier(AppTypography.context)
                Text("Y mañana, ¿qué travesura hará el elfo?")
                    .modifier(AppTypography(name: "NewKansasSwash-RegularItalic", size: 36, relativeTo: .largeTitle, lineHeight: 1.2))
                    .accessibilityAddTraits(.isHeader)
                Text("Cada día, una nueva idea para que la magia aparezca por sorpresa a la mañana siguiente.")
                    .modifier(AppTypography.onboardingBody)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            introductionBubbles
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .frame(maxWidth: 480)
    }

    private var reminderPage: some View {
        ScrollView {
            VStack(spacing: 18) {
                OnboardingBell()
                setupHeading("Avisos", title: "¡Que no se duerma la magia!",
                             message: "Elige una hora y te damos un toque la noche anterior. Así tu elfo hace su travesura antes de que te venza el sueño.")

            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }

    private var introductionBubbles: some View {
        GeometryReader { space in
            let diameter = min(146, space.size.width * 0.39, space.size.height * 0.40)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    floatingPreview("scene-bananas", size: diameter * 0.22, x: -1.15, y: -1.12, depth: 0.18, time: time, container: space.size)
                    floatingPreview("scene-paper-ghosts", size: diameter * 0.27, x: 0.92, y: -1.0, depth: 0.22, time: time, container: space.size)
                    floatingPreview("scene-film-hammock", size: diameter * 0.18, x: 1.16, y: 0.78, depth: 0.14, time: time, container: space.size)
                    floatingPreview("scene-flour-sled", size: diameter * 0.23, x: -1.16, y: 0.76, depth: 0.24, time: time, container: space.size)
                    floatingPreview("scene-cotton-snowman", size: diameter * 0.2, x: -0.35, y: 1.9, depth: 0.17, time: time, container: space.size)
                    floatingPreview("scene-snow-bowling", size: diameter * 0.31, x: 0.04, y: -1.23, depth: 0.31, time: time, container: space.size)
                    floatingPreview("scene-mandarin-choir", size: diameter * 0.45, x: -0.59, y: -0.67, depth: 0.42, time: time, container: space.size)
                    floatingPreview("scene-last-cookie-thief", size: diameter * 0.68, x: -0.68, y: 0.32, depth: 0.7, time: time, container: space.size)
                    floatingPreview("scene-sink-regatta", size: diameter * 0.62, x: 0.68, y: 0.34, depth: 0.63, time: time, container: space.size)
                    floatingPreview("scene-midnight-movie", size: diameter, x: 0, y: -0.02, depth: 1, time: time, container: space.size)
                    floatingPreview("scene-rubber-ducks", size: diameter * 0.58, x: -0.69, y: 1.42, depth: 0.72, time: time, container: space.size)
                    floatingPreview("scene-spaghetti-chef", size: diameter * 0.64, x: 0.10, y: 1.67, depth: 0.82, time: time, container: space.size)
                    floatingPreview("scene-sack-race", size: diameter * 0.49, x: 0.66, y: 1.24, depth: 0.51, time: time, container: space.size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func floatingPreview(
        _ name: String, size: CGFloat, x: Double, y: Double, depth: Double, time: Double, container: CGSize
    ) -> some View {
        let phase = time * (0.9 + depth * 0.4) + x * 4 + y * 3
        let horizontal = x * Double(container.width) * 0.35 + (reduceMotion ? 0 : sin(phase) * 8 * depth)
        // Keep the complete glass shell, blur and floating movement inside the available height.
        let verticalLimit = max(0, Double(container.height / 2 - size * 0.62 - 18))
        let restingY = min(verticalLimit, max(-verticalLimit, (y - 0.30) * Double(container.height) * 0.27))
        let vertical = restingY + (reduceMotion ? 0 : cos(phase) * 11 * depth)
        return Circle()
            .fill(.clear)
            .overlay {
                Image(name)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(Circle().inset(by: size * 0.025))
            .overlay {
                // The visible bubble spans about 520 px in the 640 px glass asset.
                Image("OrnamentBubbleGlass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 640 / 520, height: size * 640 / 520)
                    .offset(x: size * 3 / 520)
                    .accessibilityHidden(true)
            }
            .frame(width: size, height: size)
            .blur(radius: (1 - depth) * 6)
            .opacity(0.40 + depth * 0.60)
            .offset(x: horizontal, y: vertical)
    }

    @ViewBuilder private var setupFooter: some View {
        switch setupStep {
        case .introduction:
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("¿Cuántos elfos habrá en casa?").modifier(AppTypography(name: "Inter-SemiBold", size: 17, relativeTo: .headline))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 16) {
                        elfChoice("Un elfo", image: "OneElf", value: "1 elfo")
                        elfChoice("Dos elfos o +", image: "TwoElves", value: "2 elfos")
                    }
                    .frame(maxWidth: 260)
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
                .modifier(GlassSurface(prominent: false, radius: 24, interactive: false))
                Button("Siguiente") { setupStep = .reminders }
                    .buttonStyle(OnboardingActionStyle())
            }
        case .reminders:
            VStack(spacing: 16) {
                reminderTimePicker
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .modifier(GlassSurface(prominent: false, radius: 24, interactive: false))
            Button("Activar avisos") {
                Task {
                    await enableReminders()
                    setupStep = .loading
                }
            }
            .buttonStyle(OnboardingActionStyle())
            .disabled(requestingReminders)
            }
        case .loading:
            if planReady {
                Button("¡Vamos!", action: finishSetup)
                    .buttonStyle(OnboardingActionStyle())
            } else {
                SetupProgress(prepare: prepareSetupPlan) {
                    planReady = true
                }
            }
        }
    }

    private func elfChoice(_ title: String, image: String, value: String) -> some View {
        let selected = elfPreference == value
        return Button {
            elfPreference = value
            handTapCount += 1
        } label: {
            VStack(spacing: 8) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 74, height: 82)
                    .keyframeAnimator(initialValue: CGFloat.zero, trigger: handTapCount) { image, lift in
                        image
                            .scaleEffect(selected && !reduceMotion ? 1 + lift * 0.10 : 1, anchor: .bottom)
                    } keyframes: { _ in
                        SpringKeyframe(1, duration: 0.22, spring: .bouncy)
                        SpringKeyframe(0, duration: 0.38, spring: .bouncy)
                    }
                    .frame(width: 84, height: 84, alignment: .bottom)
                    .background(.black.opacity(selected ? 0.25 : 0.12), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(selected ? 0.95 : 0.15), lineWidth: 2) }
                Text(title)
                    .modifier(AppTypography(name: "Inter-SemiBold", size: 13, relativeTo: .footnote))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticPlainStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setupHeading(_ section: String, title: String, message: String? = nil) -> some View {
        VStack(spacing: 12) {
            Text(section).modifier(AppTypography.context)
            Text(title)
                .modifier(AppTypography(name: "NewKansasSwash-RegularItalic", size: 36, relativeTo: .largeTitle, lineHeight: 1.2))
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message).modifier(AppTypography.onboardingBody)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func includesWeekday(_ day: Int, mask: Int) -> Bool {
        let index = (edition.calendar.component(.weekday, from: edition.date(day)) + 5) % 7
        return mask & (1 << index) != 0
    }

    private func prepareSetupPlan() {
        planningWeekdays = 127
        firstPlanningDay = 1
        lastPlanningDay = 24
        let preferences = CatalogFilters([.elves: [elfPreference]])
        saveFilters(preferences)
        applyStarterPlan(using: preferences, fillNewDates: true)
    }

    private func finishSetup() {
        initialSetupComplete = true
        let target = edition.stripFocus(now)
        let activeDays = planningDays.filter { includesWeekday($0, mask: planningWeekdays) }
        focusedDay = now < edition.date(1) ? 0 : (activeDays.first { $0 >= target } ?? activeDays.last)
        panel = nil
        refreshReminders()
    }

    private func emptyDay(_ day: Int) -> some View {
        let editable = canEdit(day)
        let preview = catalog.indices.contains(day - 1) ? catalog[day - 1] : nil
        return ScrollView {
            emptyDayContent(day, editable: editable, preview: preview, height: 280)
                .modifier(DayCardFrame(alignment: .center))
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding(20)
        }
        .background { FloatingDecorations(idea: nil, showsDecorations: false) }
    }

    private func emptyDayContent(_ day: Int, editable: Bool, preview: Trastada?, height: CGFloat, showMessage: Bool = true, animated: Bool = true) -> some View {
        VStack(spacing: 12) {
            DayAnimation(day: day, preview: preview, animated: animated, displayHeight: height)
            if showMessage {
                Text(editable ? "Aún no hay travesura" : "Ese día no hubo travesura")
                    .systemHeading(.title3)
            }
            if editable {
                Button("Añadir travesura", systemImage: "calendar.badge.plus") { choose(for: day) }
                    .buttonStyle(GlassControl(white: true))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func detail(
        _ idea: Trastada, day: Int?, confirm: (() -> Void)? = nil,
        hero: (namespace: Namespace.ID, id: String)? = nil
    ) -> some View {
        let scheduledDay = day ?? plan.assignments.first { $0.value == idea.id }?.key
        return ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                GeometryReader { space in
                    CardPhoto(idea: idea, height: space.size.height, captionInset: 24,
                              showsPlaceholder: false, presentsCaption: hero != nil, showsMetadata: true)
                        .overlay(alignment: .topTrailing) { share(idea).padding(cardIconInset) }
                        .modifier(DayCardFrame(alignment: .topLeading, inset: 0))
                }
                .aspectRatio(1 / dayPhotoRatio, contentMode: .fit)
                .modifier(IdeaHeroGeometry(hero: hero, destination: true))

                preparationInstructions(idea)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if let confirm {
                    Button("Elegir esta idea", systemImage: "checkmark") {
                        confirm()
                    }
                        .modifier(PrimaryIdeaControl())
                } else if let scheduledDay, canEdit(scheduledDay) {
                    Button("Cambiar travesura", systemImage: "sparkles") { startSurprise(for: scheduledDay) }
                        .modifier(PrimaryIdeaControl())
                } else if scheduledDay == nil, planningDays.contains(where: canEdit) {
                    calendarAction(for: idea, detailPrimary: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background {
            if confirm == nil { FloatingDecorations(idea: idea, showsDecorations: false, showsSnow: true) }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func preparationInstructions(_ idea: Trastada) -> some View {
        Text("Materiales")
            .systemHeading(.title3)
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 10)
        MaterialTagLayout(spacing: 7) {
            ForEach(Array(idea.materialTags.enumerated()), id: \.offset) { _, material in
                Text(material)
                    .modifier(AppTypography.context)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .overlay { Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1) }
            }
        }

        Text("Preparación")
            .systemHeading(.title3)
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 10)
        ForEach(Array(preparationSteps(idea.preparation).enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 11) {
                Text(index + 1, format: .number)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(ideaControlTint, in: Circle())
                Text(step)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.90))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func preparationSteps(_ preparation: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = preparation
        tokenizer.setLanguage(.spanish)
        return tokenizer.tokens(for: preparation.startIndex..<preparation.endIndex).map {
            preparation[$0].trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private func share(_ idea: Trastada) -> some View {
        share(idea, cardGlass: false)
    }

    @ViewBuilder private func share(_ idea: Trastada, cardGlass: Bool) -> some View {
        let link = Button {
            let message = "Descubre esta y otras travesuras en Elf Help!"
                + (appStoreURL.map { " Descárgala ahora en App Store\n" + $0.absoluteString } ?? "")
            sharedTravesura = SharedTravesura(image: Artwork.shareUIImage(for: idea), message: message)
        } label: {
            Label("Compartir", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
        }
        if cardGlass {
            link.buttonStyle(CardGlassButtonStyle())
        } else {
            link.buttonStyle(GlassControl(iconOnly: true))
        }
    }

    @ViewBuilder private func calendarAction(for idea: Trastada, compactDelete: Bool = false, detailPrimary: Bool = false) -> some View {
        if let day = plan.assignments.first(where: { $0.value == idea.id })?.key {
            if canEdit(day) {
                RemoveAssignmentButton(iconOnly: compactDelete) {
                    guard canEdit(day), plan.assignments[day] == idea.id else { return }
                    update { $0.remove(from: day, catalog: catalog) }
                    if case .day = panel { return }
                    panel = nil
                }
            }
        } else if let assignmentDay, edition.canEdit(assignmentDay, now: now) {
            Button {
                panel = nil
                requestAssignment(idea, to: assignmentDay)
            } label: {
                Label("Añadir", systemImage: "calendar.badge.plus")
            }
            .modifier(AssignmentControlAppearance(primary: detailPrimary))
            .accessibilityHint("Añade la travesura al día \(assignmentDay)")
        } else if planningDays.contains(where: canEdit) {
            Menu {
                ForEach(planningDays.filter(canEdit), id: \.self) { target in
                    Button("\(target) de diciembre") {
                        panel = nil
                        requestAssignment(idea, to: target)
                    }
                }
            } label: {
                Label("Añadir", systemImage: "calendar.badge.plus")
            }
            .modifier(AssignmentControlAppearance(primary: detailPrimary))
        }
    }

    private var settings: some View {
        List {
            Section {
                Toggle("Avisos de preparación", isOn: Binding(
                    get: { remindersEnabled },
                    set: { enabled in
                        AppHaptics.tap()
                        if enabled {
                            Task { await enableReminders() }
                        } else {
                            remindersEnabled = false
                            refreshReminders()
                        }
                    }
                ))
                .disabled(requestingReminders)
                if remindersEnabled {
                    reminderTimePicker
                }
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        settingsLabel("Permisos de notificación", icon: "gearshape", tint: .gray)
                    }
                }
            } header: {
                Text("Avisos de preparación")
            } footer: {
                Text("Recibe un aviso la noche anterior a cada travesura.")
            }
            Section("Preferencias") {
                NavigationLink {
                    FilterEditor(initial: filterSelection, ideas: illustratedCatalog, save: saveFilters)
                } label: {
                    settingsLabel("Filtros del catálogo", icon: "slider.horizontal.3", tint: .purple)
                }
            }
            Section("Información") {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    settingsLabel("Política de privacidad", icon: "hand.raised", tint: .green)
                }
                if let appStoreURL {
                    ShareLink(item: appStoreURL) {
                        settingsLabel("Compartir la app", icon: "square.and.arrow.up", tint: .cyan)
                    }
                }
                LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .listStyle(.insetGrouped)
        .buttonStyle(HapticPlainStyle())
        .tint(.blue)
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsLabel(_ title: String, icon: String, tint: Color) -> some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.vertical, 3)
    }

    private var reminderTimePicker: some View {
        DatePicker("Hora del aviso", selection: reminderTime, displayedComponents: .hourAndMinute)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                edition.calendar.date(
                    bySettingHour: reminderMinutes / 60,
                    minute: reminderMinutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                AppHaptics.tap()
                let components = edition.calendar.dateComponents([.hour, .minute], from: date)
                reminderMinutes = (components.hour ?? 22) * 60 + (components.minute ?? 0)
                refreshReminders()
            }
        )
    }

    private func enableReminders() async {
        guard !requestingReminders else { return }
        requestingReminders = true
        defer { requestingReminders = false }
        remindersEnabled = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        refreshReminders()
    }

    private var filterSelection: CatalogFilters {
        let stored = FilterDecodingCache.value(for: savedFilters)
        return CatalogFilters(stored)
    }

    private func saveFilters(_ filters: CatalogFilters) {
        if let encoded = try? JSONEncoder().encode(filters.selections) { savedFilters = encoded }
    }

    private func idea(on day: Int) -> Trastada? {
        let current = plan
        let id = current.assignments[day] ?? current.reviews?[day]?.ideaID
        return catalog.first { $0.id == id }
    }

    private func returnFromIdeaList() {
        let dayToRestore = assignmentDay ?? selectedDay
        focusedDay = dayToRestore
        assignmentDay = nil
        browsingCatalog = false
    }

    private func startSurprise(for day: Int) {
        guard canEdit(day) else { return }
        let assigned = Set(plan.assignments.values)
        let unassigned = illustratedCatalog.filter { !assigned.contains($0.id) }
        let preferred = unassigned.filter(filterSelection.matches)
        let ideas = (preferred.isEmpty ? unassigned : preferred).shuffled()
        guard !ideas.isEmpty else {
            choose(for: day)
            return
        }
        calendarDetailPage = nil
        panel = nil
        focusedDay = day
        surpriseRound = SurpriseRound(day: day, ideas: ideas)
    }

    private func choose(for day: Int) {
        guard canEdit(day) else { return }
        assignmentDay = day
        panel = nil
    }

    private func requestAssignment(_ idea: Trastada, to day: Int) {
        guard canEdit(day) else { return }
        if let old = plan.assignments.first(where: { $0.value == idea.id })?.key,
           !edition.canEdit(old, now: Self.planningDate) { return }
        if let current = self.idea(on: day), current.id != idea.id {
            replacementDay = day
            replacing = idea
        } else {
            commit(idea, to: day)
        }
    }

    private func commit(_ idea: Trastada, to day: Int) {
        guard canEdit(day) else { return }
        if let old = plan.assignments.first(where: { $0.value == idea.id })?.key,
           !edition.canEdit(old, now: Self.planningDate) { return }
        update {
            $0.assign(idea.id, to: day, catalog: catalog)
            $0.fillStarterDays(from: illustratedCatalog, matching: filterSelection, days: DecemberEdition.pages)
        }
        assignmentDay = nil
        panel = nil
        focusedDay = day
        browsingCatalog = false
        showsConfirmation = false
        confirmedDay = day
        confirmationCount += 1
    }

    private func update(_ changes: (inout DecemberPlan) -> Void) {
        var revised = plan
        changes(&revised)
        if let data = try? JSONEncoder().encode(revised) { savedPlan = data }
        refreshReminders()
    }

    private func applyStarterPlan(using filters: CatalogFilters, fillNewDates: Bool = false) {
        guard fillNewDates || !starterPlanApplied else { return }
        var revised = storedPlan
        revised.fillStarterDays(from: illustratedCatalog, matching: filters, days: DecemberEdition.pages)
        guard let data = try? JSONEncoder().encode(revised) else { return }
        savedPlan = data
        starterPlanApplied = true
        refreshReminders()
    }

    private func scheduleAppRating() {
        let elapsed = Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: firstUseTimestamp), to: Date()).day ?? 0
        let candidates = [3, 7, 14].filter { elapsed >= $0 }.map { "day-\($0)" }
            + (edition.today(now) == 24 ? ["final-\(edition.year)"] : [])
        let seen = Set(ratingMilestones.split(separator: "|").map(String.init))
        guard candidates.contains(where: { !seen.contains($0) }) else { return }
        ratingTask?.cancel()
        ratingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, panel == nil, surpriseRound == nil, scenePhase == .active else { return }
            ratingMilestones = seen.union(candidates).sorted().joined(separator: "|")
            requestAppReview()
        }
    }

    private func activate() {
        let currentDate = Self.planningDate
        if !edition.calendar.isDate(now, inSameDayAs: currentDate) { focusedDay = nil }
        now = currentDate
        if firstUseTimestamp == 0 { firstUseTimestamp = Date().timeIntervalSince1970 }
        guard !showSplash, panel?.id != "setup" else { return }
        if shouldShowSetup {
            setupShownThisLaunch = true
            planReady = false
            setupStep = .introduction
            panel = .setup
            return
        }
        if initialSetupComplete {
            applyStarterPlan(using: filterSelection)

        }
        refreshReminders()
        let defaults = UserDefaults.standard
        let reminderDay = defaults.integer(forKey: "reminderDay")
        if (1...24).contains(reminderDay) {
            defaults.removeObject(forKey: "reminderDay")
            focusedDay = reminderDay
            browsingCatalog = false
            assignmentDay = nil
            panel = nil
        }
        guard panel == nil else { return }
        if (1...24).contains(reminderDay) { return }
        let yesterday = edition.calendar.date(byAdding: .day, value: -1, to: now) ?? now
        #if DEBUG
        let previewReview = true
        #else
        let previewReview = false
        #endif
        if let day = edition.today(yesterday), idea(on: day) != nil,
           (previewReview || plan.reviews?[day] == nil), promptedReviewDay != day {
            promptedReviewDay = day
            panel = .review(day)
            return
        }
        if let day = edition.today(now), let promotion = AppPromotion.configured.first(where: {
            $0.enabled && $0.days.contains(day) && !seenPromotions.split(separator: "|").contains(Substring("\(edition.year):\($0.id)"))
        }) {
            seenPromotions += "|\(edition.year):\(promotion.id)"
            panel = .promotion(promotion)
            return
        }
        scheduleAppRating()
        if now >= edition.date(26), !closingSeen {
            closingSeen = true
            panel = .closing
        }
    }

    private func refreshReminders() {
        let assignments = plan.assignments
        let days = planningDays.filter { includesWeekday($0, mask: planningWeekdays) }
        let minutes = reminderMinutes
        let enabled = remindersEnabled
        let center = UNUserNotificationCenter.current()
        let previous = reminderTask
        previous?.cancel()
        reminderTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: (1...24).map { "elf-\($0)" })
            guard enabled else { return }
            for day in days {
                guard !Task.isCancelled else { return }
                guard let date = edition.reminderDate(for: day, hour: minutes / 60, minute: minutes % 60),
                      date > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = assignments[day] == nil ? "¿Preparamos mañana?" : "Todo listo para mañana"
                content.sound = .default
                content.userInfo = ["day": day]
                let components = edition.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                do {
                    try await center.add(UNNotificationRequest(identifier: "elf-\(day)", content: content, trigger: trigger))
                } catch {
                    if !Task.isCancelled {
                        NSLog("No se pudo programar el aviso del día %d: %@", day, error.localizedDescription)
                    }
                }
            }
        }
    }

    private func configuredURL(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}


private struct ScrollHandHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scenePhase != .active)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 3.4
            Image("ScrollHand")
                .renderingMode(.template)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .offset(y: reduceMotion ? 0 : -6 * sin(phase))
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }
}

private struct OnboardingBell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30,
                                paused: reduceMotion || scenePhase != .active)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(started))
            let phase = elapsed * 2 * .pi / 3.2
            let entrance = min(1, elapsed / 0.6)
            let swing = reduceMotion ? 0 : sin(phase) * 7 * entrance
            let pendulum = reduceMotion ? 0 : sin(phase - .pi * 0.65) * 14 * entrance
            // The supplied layers share the same canvas; preserve their registration.
            ZStack {
                bellLayer("BellBack")
                bellLayer("BellPendulum")
                    .rotationEffect(.degrees(pendulum), anchor: UnitPoint(x: 0.5, y: 0.52))
                bellLayer("BellFront")
            }
            .frame(width: 120, height: 120)
            .rotationEffect(.degrees(swing), anchor: UnitPoint(x: 0.5, y: 0.17))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bellLayer(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
    }
}

private struct LoadingBubbleParade: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()
    private let objects = ["DecorationCandy", "DecorationHat", "DecorationCocoa", "DecorationStocking", "DecorationGift"]

    private func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        GeometryReader { space in
            let diameter = min(230, space.size.width * 0.58, space.size.height * 0.68)
            let travel = (space.size.width + diameter) / 2 + 24
            TimelineView(.animation(minimumInterval: 1.0 / 30,
                                    paused: reduceMotion || scenePhase != .active)) { timeline in
                let time = reduceMotion ? 1.4 : max(0, timeline.date.timeIntervalSince(started))
                let cycle = Int(time / 2.1)
                ZStack {
                    ForEach(max(0, cycle - 1)...cycle, id: \.self) { index in
                        let age = time - Double(index) * 2.1
                        let entry = ease(age / 1.0)
                        let exit = ease((age - 1.8) / 1.0)
                        let x = travel * (entry + exit - 1) + 5 * sin(age * 1.8)
                        let arc = max(0, 1 - pow(x / travel, 2))
                        let turn = sin(age * 1.6 - 1.0) * 16
                        ZStack {
                            Image(objects[index % objects.count])
                                .resizable()
                                .scaledToFit()
                                .frame(width: diameter * 0.70, height: diameter * 0.70)
                                .rotationEffect(.degrees(reduceMotion ? 0 : turn))
                            Image("OrnamentBubbleGlass")
                                .resizable()
                                .scaledToFit()
                                .frame(width: diameter * 640 / 520)
                                .offset(x: diameter * 3 / 520)
                        }
                        .frame(width: diameter, height: diameter)
                        .opacity(age <= 2.8 ? 1 : 0)
                        .position(x: space.size.width / 2 + (reduceMotion ? 0 : x),
                                  y: space.size.height * 0.58 - (reduceMotion ? 0 : arc * 32 + sin(age * 2.2) * 7))
                    }
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SetupProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    let prepare: () -> Void
    let complete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .modifier(AppTypography(name: "NewKansas-Bold", size: 32, relativeTo: .title))
            GeometryReader { space in
            Capsule()
                .fill(.white.opacity(0.16))
                .overlay(alignment: .leading) {
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                        for x in stride(from: -24.0, to: size.width, by: 24.0) {
                            var stripe = Path()
                            stripe.move(to: CGPoint(x: x + size.height, y: 0))
                            stripe.addLine(to: CGPoint(x: x + size.height + 12, y: 0))
                            stripe.addLine(to: CGPoint(x: x + 12, y: size.height))
                            stripe.addLine(to: CGPoint(x: x, y: size.height))
                            stripe.closeSubpath()
                            context.fill(stripe, with: .color(Color(red: 0.78, green: 0.04, blue: 0.16)))
                        }
                    }
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.18), location: 0),
                            .init(color: .white.opacity(0.8), location: 0.18),
                            .init(color: .white.opacity(0.22), location: 0.42),
                            .init(color: .clear, location: 0.55),
                            .init(color: .black.opacity(0.32), location: 0.9),
                            .init(color: .white.opacity(0.25), location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.65))
                            .frame(height: 2)
                            .blur(radius: 0.5)
                            .padding(.horizontal, 8)
                            .padding(.top, 5)
                    }
                    .frame(width: space.size.width * progress)
                    .clipShape(Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.65), lineWidth: 0.8) }
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 4)
                    .shadow(color: .white.opacity(0.25), radius: 5, y: -1)
                }
                .overlay { Capsule().strokeBorder(.white.opacity(0.4)) }
        }
            .frame(height: 28)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando tu experiencia")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            prepare()
            do {
                for percent in 1...100 {
                    try await Task.sleep(for: .milliseconds(50))
                    withAnimation(reduceMotion ? nil : .linear(duration: 0.05)) {
                        progress = Double(percent) / 100
                    }
                }
                complete()
            } catch { return }
        }
    }
}

private func detailHeading(_ title: String) -> some View {
    Text(title)
        .systemHeading(.title3)
        .foregroundStyle(.white)
        .accessibilityAddTraits(.isHeader)
}

private struct SuccessConfetti: View {
    @State private var started = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { time in
            let progress = min(1, max(0, time.date.timeIntervalSince(started) / 1.4))
            Canvas { context, size in
                let colors: [Color] = [.pink, .yellow, .cyan, .white, .purple]
                for index in 0..<32 {
                    let seed = Double(index)
                    let x = size.width / 2 + sin(seed * 2.4) * size.width * 0.5 * progress
                    let y = 25 + progress * (80 + Double(index % 7) * 16) + progress * progress * 45
                    var particle = context
                    particle.opacity = 1 - progress
                    particle.translateBy(x: x, y: y)
                    particle.rotate(by: .degrees(seed * 37 + progress * 240))
                    particle.fill(Path(CGRect(x: -3, y: -2, width: 6, height: 4)), with: .color(colors[index % colors.count]))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AssignmentCelebration: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { [reduceMotion] card, progress in
            let glow = min(1, min(progress * 8, (1 - progress) * 8))
            let highlight = AngularGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.72),
                    .init(color: .purple.opacity(0.5), location: 0.80),
                    .init(color: .pink, location: 0.90),
                    .init(color: .white, location: 0.95),
                    .init(color: .cyan.opacity(0.8), location: 0.98),
                    .init(color: .clear, location: 1)
                ]),
                center: .center,
                angle: .degrees(progress * 360)
            )
            card.overlay {
                RoundedRectangle(cornerRadius: pearlCardRadius, style: .continuous)
                    .strokeBorder(highlight, lineWidth: 3)
                    .shadow(color: .pink, radius: 6)
                    .opacity(reduceMotion ? 0 : glow)
                    .overlay {
                        if reduceMotion {
                            RoundedRectangle(cornerRadius: pearlCardRadius, style: .continuous)
                                .strokeBorder(.white.opacity(glow * 0.7), lineWidth: 2)
                        }
                    }
                    .allowsHitTesting(false)
            }
        } keyframes: { _ in
            if trigger > 0 {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: 0.38)
                LinearKeyframe(1, duration: 1.15)
                MoveKeyframe(0)
            } else {
                MoveKeyframe(0)
            }
        }
    }
}

private let pearlCardInset: CGFloat = 16
private let pearlCardRadius: CGFloat = cardBarControlHeight / 2 + 12
private let dayControlHeight: CGFloat = 50
private let cardBarControlHeight: CGFloat = 56
private let dayPhotoRatio: CGFloat = 1.43
private let surpriseButtonHeight: CGFloat = 104
private let surpriseButtonInset: CGFloat = 14
private let cardIconInset: CGFloat = 16
private let dayCardHeightToWidth: CGFloat = 1.54

@MainActor
private enum PlanDecodingCache {
    private static var source: Data?
    private static var decoded = DecemberPlan()
    static func value(for data: Data) -> DecemberPlan {
        if source != data {
            decoded = (try? JSONDecoder().decode(DecemberPlan.self, from: data)) ?? DecemberPlan()
            source = data
        }
        return decoded
    }
}

@MainActor
private enum FilterDecodingCache {
    private static var source: Data?
    private static var decoded: [CatalogFilter: Set<String>] = [:]
    static func value(for data: Data) -> [CatalogFilter: Set<String>] {
        if source != data {
            decoded = (try? JSONDecoder().decode([CatalogFilter: Set<String>].self, from: data)) ?? [:]
            source = data
        }
        return decoded
    }
}

@MainActor
private enum TypographyFontCache {
    private static let fonts = NSCache<NSString, UIFont>()

    static func font(name: String, size: CGFloat) -> UIFont {
        let key = "\(name):\(size)" as NSString
        if let cached = fonts.object(forKey: key) { return cached }
        let base = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
        let descriptor = name.hasPrefix("Inter-")
            ? base.fontDescriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureTag as String): "salt",
                    UIFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureValue as String): 1
                ]]
            ]) : base.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: size)
        fonts.setObject(font, forKey: key)
        return font
    }
}

private struct AppTypography: ViewModifier {
    let name: String
    let lineHeight: CGFloat?
    let tracking: CGFloat
    @ScaledMetric private var pointSize: CGFloat

    init(name: String, size: CGFloat, relativeTo style: Font.TextStyle,
         lineHeight: CGFloat? = nil, tracking: CGFloat = 0) {
        self.name = name
        self.lineHeight = lineHeight
        self.tracking = tracking
        _pointSize = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        let font = TypographyFontCache.font(name: name, size: pointSize)
        let extraLeading = lineHeight.map { $0 * pointSize - font.lineHeight } ?? 0
        content
            .font(Font(font))
            .tracking(pointSize * tracking)
            .lineSpacing(extraLeading)
            .padding(.vertical, max(0, extraLeading) / 2)
    }
}

private extension AppTypography {
    static var onboardingBody: AppTypography { AppTypography(name: "Inter-Regular", size: 17, relativeTo: .body, lineHeight: 1.5, tracking: -0.02) }
    static var body: AppTypography { AppTypography(name: "Inter-Regular", size: 15, relativeTo: .subheadline, lineHeight: 1.5, tracking: -0.02) }
    static var context: AppTypography { AppTypography(name: "Inter-Medium", size: 15, relativeTo: .subheadline) }
    static var selection: AppTypography { AppTypography(name: "Inter-SemiBold", size: 15, relativeTo: .subheadline) }
    static var itemTitle: AppTypography { AppTypography(name: "NewKansasSwash-RegularItalic", size: 20, relativeTo: .title3, lineHeight: 1.2) }
}

private extension View {
    func systemHeading(_ size: Font.TextStyle) -> some View {
        let points: CGFloat = switch size {
        case .largeTitle: 39
        case .title2: 28
        case .title3: 24
        default: 17
        }
        return modifier(AppTypography(name: "NewKansasSwash-RegularItalic", size: points, relativeTo: size, lineHeight: 1.2))
            .foregroundStyle(.white)
    }
}

private struct FrostedBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.09, green: 0.04, blue: 0.19), location: 0),
                    .init(color: Color(red: 0.18, green: 0.07, blue: 0.36), location: 0.42),
                    .init(color: Color(red: 0.23, green: 0.11, blue: 0.40), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: 0.94, green: 0.19, blue: 0.64).opacity(colorScheme == .dark ? 0.58 : 0.72), .clear],
                center: UnitPoint(x: 0.99, y: 0.57), startRadius: 5, endRadius: 270
            )
            RadialGradient(
                colors: [Color(red: 0.70, green: 0.72, blue: 1).opacity(colorScheme == .dark ? 0.45 : 0.62), .clear],
                center: UnitPoint(x: 0.09, y: 0.73), startRadius: 0, endRadius: 220
            )
            RadialGradient(
                colors: [Color(red: 0.53, green: 0.29, blue: 0.96).opacity(0.52), .clear],
                center: UnitPoint(x: 0.74, y: 0.98), startRadius: 0, endRadius: 245
            )
        }
    }
}

private struct BubbleCalendar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let edition: DecemberEdition
    let selectedDay: Int
    let now: Date
    let idea: (Int) -> Trastada?
    let select: (Int) -> Void

    private let locale = Locale(identifier: "es_ES")
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                month(-3...0)
                month(1...24)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background { FloatingDecorations(idea: idea(selectedDay)) }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
            }
            appeared = true
        }
    }

    private func month(_ pages: ClosedRange<Int>) -> some View {
        let first = edition.calendarDate(for: pages.lowerBound)
        let offset = (edition.calendar.component(.weekday, from: first) + 5) % 7
        return VStack(spacing: 12) {
            Text(first.formatted(.dateTime.month(.wide).locale(locale)).capitalized(with: locale))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(Array(["L", "M", "X", "J", "V", "S", "D"].enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.63))
                        .accessibilityHidden(true)
                }
                ForEach(0..<offset, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                        .accessibilityHidden(true)
                }
                ForEach(pages, id: \.self) { page in
                    bubble(page)
                }
            }
        }
        .padding(12)
        .modifier(GlassSurface(prominent: false, radius: 24, interactive: false))
    }

    private func bubble(_ page: Int) -> some View {
        let date = edition.calendarDate(for: page)
        let today = edition.calendar.isDate(date, inSameDayAs: now)
        let selected = selectedDay == page
        let past = date < edition.calendar.startOfDay(for: now)
        return Button { select(page) } label: {
            VStack(spacing: 3) {
                Text(edition.calendar.component(.day, from: date), format: .number)
                    .font(.subheadline.weight(today ? .bold : .semibold).monospacedDigit())
                    .foregroundStyle(today ? Color.black : .white)
                    .frame(minWidth: 25, minHeight: 21)
                    .background {
                        if today { Capsule().fill(.white) }
                    }
                GeometryReader { space in
                    let diameter = space.size.width
                    if let scene = idea(page) {
                        Artwork(idea: scene, height: diameter, rounded: false, thumbnail: true)
                            .frame(width: diameter, height: diameter)
                            .clipShape(Circle())
                            .overlay {
                                Circle().strokeBorder(.white.opacity(today ? 0.95 : selected ? 0.75 : 0.25),
                                                      lineWidth: today ? 2 : 1)
                            }
                            .overlay(alignment: .topLeading) {
                                if past {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 14, height: 14)
                                        .background(.black.opacity(0.8), in: Circle())
                                        .overlay { Circle().strokeBorder(.white.opacity(0.55)) }
                                }
                            }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticPlainStyle())
        .accessibilityLabel((today ? "Hoy, " : past ? "Día pasado, " : "") + date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .scaleEffect(appeared || reduceMotion ? 1 : 0.22)
        .opacity(appeared ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.16)
                : .spring(response: 0.40, dampingFraction: 0.68)
                    .delay(Double(page - DecemberEdition.pages.lowerBound) * 0.060),
            value: appeared
        )
    }
}

private struct DayCardFrame: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let alignment: Alignment
    var inset: CGFloat = pearlCardInset
    var radius: CGFloat = pearlCardRadius
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .foregroundStyle(.white)
            .clipShape(shape)
            .background {
                shape.fill(reduceTransparency ? Color(white: 0.17) : .black.opacity(0.22))
                    .overlay {
                        if !reduceTransparency {
                            shape.fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.20), location: 0),
                                        .init(color: .white.opacity(0.06), location: 0.28),
                                        .init(color: .clear, location: 0.73),
                                        .init(color: .white.opacity(0.10), location: 1)
                                    ],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                        }
                    }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Color(red: 0.89, green: 0.90, blue: 1).opacity(0.68),
                                    .white.opacity(0.13),
                                    Color(red: 1, green: 0.81, blue: 0.94).opacity(0.46)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                    }
                    .background {
                        if !reduceTransparency {
                            shape.strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.66, green: 0.72, blue: 1).opacity(0.66),
                                        Color(red: 0.70, green: 0.50, blue: 1).opacity(0.25),
                                        Color(red: 1, green: 0.57, blue: 0.83).opacity(0.54)
                                    ],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 4
                            )
                            .padding(-2)
                            .blur(radius: 8)
                        }
                    }
                    .shadow(color: .black.opacity(0.32), radius: 12, y: 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                if !reduceTransparency {
                    shape.strokeBorder(LinearGradient(
                        colors: [.white.opacity(0.70), .purple.opacity(0.28), .pink.opacity(0.55), .white.opacity(0.30)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

private struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let prominent: Bool
    let radius: CGFloat
    var darkInk = false
    var interactive = true

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let ink: Color = prominent || darkInk ? .black : .white
        let label = content.foregroundStyle(ink)

        if reduceTransparency {
            label.background(prominent || darkInk ? Color(white: 0.95) : Color(white: 0.18), in: shape)
        } else {
            Group {
                if #available(iOS 26.0, *) {
                    let glass = prominent ? Glass.regular.tint(.white.opacity(0.82)) : .clear
                    label
                        .glassEffect(glass.interactive(interactive), in: shape)
                } else if prominent {
                    label.background(.white, in: shape)
                } else {
                    label.background(.ultraThinMaterial, in: shape)
                }
            }
            .background {
                shape.fill(.white.opacity(prominent ? 0.66 : (darkInk ? 0.14 : 0.06)))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            (darkInk ? Color.black.opacity(0.18) : Color.white.opacity(0.55)),
                            (darkInk ? Color.black.opacity(0.07) : Color.white.opacity(0.16))
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
            }
        }
    }
}

@MainActor
private enum AppHaptics {
    private static let generator = UIImpactFeedbackGenerator(style: .heavy)
    private static var lastFeedback = Date.distantPast

    static func tap() {
        let now = Date()
        guard now.timeIntervalSince(lastFeedback) > 0.1 else { return }
        lastFeedback = now
        generator.impactOccurred(intensity: 1)
        generator.prepare()
    }
}

private struct ButtonHaptics: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    let isPressed: Bool

    func body(content: Content) -> some View {
        content.onChange(of: isPressed) { _, pressed in
            if pressed && enabled { AppHaptics.tap() }
        }
    }
}

private struct HapticPlainStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .modifier(ButtonHaptics(isPressed: configuration.isPressed))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct GlassControl: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var prominent = false
    var iconOnly = false
    var white = false
    var quiet = false
    var darkInk = false

    func makeBody(configuration: Configuration) -> some View {
        let filled = white || (prominent && configuration.role != .destructive)
        return configuration.label
            .modifier(ButtonHaptics(isPressed: configuration.isPressed))
            .font(.subheadline.weight(quiet ? .regular : (filled ? .semibold : .medium)))
            .padding(.horizontal, iconOnly ? 0 : 12)
            .padding(.vertical, iconOnly ? 0 : 5)
            .frame(minWidth: iconOnly ? 44 : nil, minHeight: 44)
            .contentShape(Rectangle())
            .modifier(GlassSurface(prominent: filled, radius: 24, darkInk: darkInk))
            .shadow(color: .white.opacity(filled ? 0.45 : 0), radius: 8)
            .opacity(enabled ? 1 : 0.55)
    }
}

private struct SurpriseRound {
    let day: Int
    let ideas: [Trastada]
}

private struct IdeaBoard: View {
    @AppStorage("bubbleGuideSeen") private var bubbleGuideSeen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var limitsEffects = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        || ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var showsList = false
    @State private var birthStarted: Date?
    @State private var entries: [Entry] = []

    private enum Entry {
        case idea(Trastada)
        case ornament(String)
    }

    private let ornaments = ["Candy", "Ornament", "Stocking", "Snowflake", "Tape", "Star",
                             "Cookie", "Hat", "Gift", "Paper", "Flour", "Cocoa", "Sleigh",
                             "Thread", "Reindeer", "Wrap", "Envelope", "Mailbox", "Snowman"]

    private var entryCount: Int { entries.isEmpty ? ideas.count : entries.count }

    private func idea(at index: Int) -> Trastada? {
        guard !entries.isEmpty else { return ideas[index] }
        if case .idea(let idea) = entries[index] { return idea }
        return nil
    }

    @State private var position: CGPoint?
    @State private var backdropPosition: CGPoint?
    @State private var scrollRequest: CGPoint?
    @State private var selectionSettled = false
    @State private var hasScrolled = false
    let ideas: [Trastada]
    let size: CGSize
    let day: Int
    let date: Date
    let cancel: () -> Void
    let select: (Trastada) -> Void

    private let columns = 6
    private let tile = CGSize(width: 170, height: 220)
    private let spacing = CGSize(width: 86, height: 75)

    private struct Slot: Hashable {
        let row: Int
        let column: Int
        var heroID: String { "\(row):\(column)" }
    }

    private var repeatingRows: Int { (entryCount + columns - 1) / columns }

    private func wrapped(_ value: Int, modulo: Int) -> Int {
        let remainder = value % modulo
        return remainder < 0 ? remainder + modulo : remainder
    }

    private func entryIndex(for slot: Slot) -> Int {
        let row = wrapped(slot.row, modulo: repeatingRows)
        let column = wrapped(slot.column, modulo: columns)
        return (row * columns + column) % entryCount
    }

    private func center(of slot: Slot) -> CGPoint {
        let stagger: CGFloat = slot.row.isMultiple(of: 2) ? 0 : spacing.width / 2
        return CGPoint(x: CGFloat(slot.column) * spacing.width + stagger,
                       y: CGFloat(slot.row) * spacing.height)
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private var startingPosition: CGPoint {
        let middle = Slot(row: (repeatingRows - 1) / 2, column: (min(columns, entryCount) - 1) / 2)
        let origin = center(of: middle)
        return CGPoint(x: origin.x + spacing.width / 2, y: origin.y + spacing.height / 3)
    }

    private func nearestCard(to point: CGPoint) -> Slot {
        let row = Int((point.y / spacing.height).rounded())
        let column = Int((point.x / spacing.width).rounded())
        let nearby = ((row - 2)...(row + 2)).flatMap { r in
            ((column - 2)...(column + 2)).map { Slot(row: r, column: $0) }
        }
        return nearby.min {
            distance(from: center(of: $0), to: point) < distance(from: center(of: $1), to: point)
        } ?? Slot(row: row, column: column)
    }

    private func visibleCards(around point: CGPoint) -> [Slot] {
        let margin = CGSize(width: size.width / 2 + tile.width * 1.8, height: size.height / 2 + tile.height)
        let firstRow = Int(floor((point.y - margin.height) / spacing.height))
        let lastRow = Int(ceil((point.y + margin.height) / spacing.height))
        let firstColumn = Int(floor((point.x - margin.width) / spacing.width))
        let lastColumn = Int(ceil((point.x + margin.width) / spacing.width))
        return (firstRow...lastRow).flatMap { row in
            (firstColumn...lastColumn).map { Slot(row: row, column: $0) }
        }
    }

    var body: some View {
        let current = position ?? startingPosition
        let centered = distance(from: current, to: center(of: nearestCard(to: current))) < 1
        let resting = centered ? current : (backdropPosition ?? startingPosition)
        let restingIdea = idea(at: entryIndex(for: nearestCard(to: resting)))
        let restingCard = restingIdea ?? ideas[0]
        return Group {
            if showsList {
                selectionList
            } else if !entries.isEmpty {
                let pieces = packedPieces(around: current)
                TimelineView(.animation(paused: birthStarted == nil || reduceMotion)) { timeline in
                    grid(at: current, pieces: pieces, birthElapsed: birthStarted.map { timeline.date.timeIntervalSince($0) })
                }
                    .overlay {
                        NativeBoardScroll(start: current, request: scrollRequest,
                                          animated: !reduceMotion,
                                          started: { bubbleGuideSeen = true; hasScrolled = true; selectionSettled = false },
                                          snap: { center(of: nearestCard(to: $0)) }) { point in
                            if distance(from: position ?? startingPosition, to: point) > 0.1 {
                                selectionSettled = false
                                position = point
                            }
                        } settled: { point in
                            scrollRequest = nil
                            backdropPosition = point
                            position = point
                            selectionSettled = hasScrolled
                        } tapped: { point in
                            let boardPoint = CGPoint(x: current.x + point.x - size.width / 2,
                                                     y: current.y + point.y - size.height / 2)
                            if let piece = pieces.first(where: { piece in
                                distance(from: piece.center, to: boardPoint) <= piece.corner
                            }) {
                                chooseIdea(at: piece.id)
                            }
                        }
                        .accessibilityHidden(true)
                    }
            } else {
                Color.clear.frame(width: size.width, height: size.height)
            }
        }
        .task {
            let shuffledOrnaments = ornaments.shuffled()
            var nextOrnament = Int.random(in: 4...7)
            var ornamentIndex = 0
            var items: [Entry] = []
            for (index, idea) in ideas.enumerated() {
                items.append(.idea(idea))
                if index == nextOrnament, ornamentIndex < shuffledOrnaments.count {
                    items.append(.ornament("Decoration" + shuffledOrnaments[ornamentIndex]))
                    ornamentIndex += 1
                    nextOrnament += Int.random(in: 6...9)
                }
            }
            entries = items
            if !reduceMotion { birthStarted = Date() }
            if birthStarted != nil {
                try? await Task.sleep(for: .milliseconds(1400))
                if !Task.isCancelled { birthStarted = nil }
            }
        }
        .background {
            ZStack {
                FloatingDecorations(idea: restingCard, showsDecorations: false)
                RadialGradient(
                    colors: [Color(red: 0.085, green: 0.025, blue: 0.16), .clear],
                    center: .topLeading, startRadius: 0, endRadius: size.width * 1.12
                )
                RadialGradient(
                    colors: [Color(red: 0.16, green: 0.035, blue: 0.115), .clear],
                    center: .bottomTrailing, startRadius: 0, endRadius: size.width * 1.12
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            LinearGradient(stops: [
                .init(color: Color(red: 0.10, green: 0.025, blue: 0.18).opacity(0.98), location: 0),
                .init(color: Color(red: 0.10, green: 0.025, blue: 0.18).opacity(0.85), location: 0.5),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 184)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            HStack {
                Button("Volver", systemImage: "arrow.uturn.backward", action: cancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(GlassControl(iconOnly: true))
                VStack(spacing: 8) {
                    Text("Elige una travesura")
                        .modifier(AppTypography(name: "NewKansasSwash-MediumItalic", size: 24, relativeTo: .title3, lineHeight: 1))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))).prefix(1).uppercased() + date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))).dropFirst())
                        .modifier(AppTypography.body)
                        .foregroundStyle(.white)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                Button {
                    bubbleGuideSeen = true
                    showsList.toggle()
                    if !showsList {
                        scrollRequest = hasScrolled ? center(of: nearestCard(to: current)) : startingPosition
                    }
                } label: {
                    Image(systemName: showsList ? "circle.grid.2x2" : "list.bullet")
                }
                .buttonStyle(GlassControl(iconOnly: true))
                .accessibilityLabel(showsList ? "Ver burbujas" : "Ver lista")
            }
            .padding(.horizontal, cardIconInset)
            .frame(minHeight: 54)
            .padding(.top, 16)
        }
        .overlay(alignment: .bottom) {
            if !bubbleGuideSeen && !showsList {
                VStack(spacing: 12) {
                    ScrollHandHint()
                    Text("Deslízate entre las burbujas para encontrar tu idea. Toca una para elegirla para ese día, o céntrala y pulsa el botón.")
                        .modifier(AppTypography.body)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(24)
                .background(ideaControlTint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(16)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if !showsList, hasScrolled, (selectionSettled || centered), birthStarted == nil {
                Button {
                    if let restingIdea {
                        select(restingIdea)
                    } else {
                        selectRandomIdea()
                    }
                } label: {
                    HStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Rectangle()
                                .fill(LinearGradient(colors: [Color(red: 1, green: 0, blue: 0.17), Color(red: 0.65, green: 0, blue: 0.10)], startPoint: .top, endPoint: .bottom))
                                .frame(height: 12)
                            Text("\(day)")
                                .modifier(AppTypography(name: "NewKansas-Bold", size: 24, relativeTo: .title3, lineHeight: 1))
                                .foregroundStyle(Color(red: 88 / 255, green: 49 / 255, blue: 82 / 255))
                                .padding(.bottom, 8)
                        }
                        .frame(width: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.32), radius: 8, y: 8)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(restingIdea?.title ?? "¡Sorpréndeme!")
                                .modifier(AppTypography.itemTitle)
                            if restingIdea == nil {
                                Text("Travesura al azar")
                                    .modifier(AppTypography.body)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image("BoardConfirm")
                            .frame(width: 32, height: 32)
                            .padding(8)
                            .background(.white, in: Circle())
                    }
                    .padding(16)
                    .background(ideaControlTint, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .modifier(GlassSurface(prominent: false, radius: 32))
                    .overlay { CardActionHalo(animated: false, cornerRadius: 32) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Elegir \(restingIdea?.title ?? "una travesura aleatoria") para el día \(day)")
                }
                .buttonStyle(HapticPlainStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectionSettled)
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            updateEffectBudget()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            updateEffectBudget()
        }
    }

    private struct Piece: Identifiable {
        let id: Slot
        var center: CGPoint
        let width: CGFloat
        let height: CGFloat
        let corner: CGFloat
        let morph: CGFloat
    }

    private var selectionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(ideas) { idea in
                    Button { select(idea) } label: {
                        HStack(spacing: 16) {
                            Artwork(idea: idea, height: 72, rounded: false, thumbnail: true)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityHidden(true)
                            Text(idea.title)
                                .modifier(AppTypography.itemTitle)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 32)
                        .padding(.vertical, 8)
                        .background(ideaControlTint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .modifier(GlassSurface(prominent: false, radius: 24))
                        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(HapticPlainStyle())
                    .accessibilityLabel("Elegir \(idea.title) para el día \(day)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .contentMargins(.top, 104, for: .scrollContent)
        .scrollIndicators(.hidden)
        .frame(width: size.width, height: size.height)
    }

    private func diameter(of index: Int) -> CGFloat {
        CGFloat(100 + (index * 37) % 17) * (idea(at: index) == nil ? 0.94 : 1.12)
    }

    private func packedPieces(around focus: CGPoint) -> [Piece] {
        // Expand a fixed lattice smoothly around the viewport center. Positions never
        // depend on collision iterations or on which neighbors enter the viewport.
        let reach: CGFloat = 85
        let expansion = min(size.width * 0.34, 135)
        var pieces = visibleCards(around: focus).map { slot in
            let origin = center(of: slot)
            let dx = origin.x - focus.x
            let dy = origin.y - focus.y
            let radius = hypot(dx, dy)
            let influence = exp(-radius / reach)
            let scale = 1 + expansion / reach * influence
            let displacement = radius > 0.001 ? expansion * (1 - influence) / radius : expansion / reach
            let width = 82 * scale
            return Piece(id: slot,
                         center: CGPoint(x: origin.x + dx * displacement, y: origin.y + dy * displacement),
                         width: width, height: width, corner: width / 2,
                         morph: reduceMotion ? 0 : influence)
        }

        // Limit diameters against actual neighbors without moving their centers.
        var factors = Array(repeating: CGFloat(1), count: pieces.count)
        for first in pieces.indices {
            for second in (first + 1)..<pieces.count {
                let separation = distance(from: pieces[first].center, to: pieces[second].center)
                let radii = pieces[first].corner + pieces[second].corner
                let factor = min(1, max(0, separation - 1) / radii)
                factors[first] = min(factors[first], factor)
                factors[second] = min(factors[second], factor)
            }
        }
        for index in pieces.indices {
            let piece = pieces[index]
            let width = piece.width * factors[index]
            pieces[index] = Piece(id: piece.id, center: piece.center, width: width,
                                  height: width, corner: width / 2, morph: piece.morph)
        }
        return pieces
    }

    private func bubbleBirth(for slot: Slot, elapsed: TimeInterval?) -> CGFloat {
        guard !reduceMotion, let elapsed else { return 1 }
        let radius = distance(from: center(of: slot), to: startingPosition)
        let delay = min(0.85, Double(radius / max(1, min(size.width, size.height))) * 0.7)
        let duration = 0.44
        let progress = min(1, max(0, (elapsed - delay) / duration))
        return CGFloat(progress * progress * (3 - 2 * progress))
    }

    private func grid(at current: CGPoint, pieces: [Piece], birthElapsed: TimeInterval?) -> some View {
        let focused = nearestCard(to: current)
        let usesCrystal = !limitsEffects && !reduceTransparency
            && !ProcessInfo.processInfo.arguments.contains("-ElfDisableCrystal")
        return ZStack {
            Color.clear
            ForEach(pieces) { piece in
                let index = entryIndex(for: piece.id)
                let x = piece.center.x - current.x
                let y = piece.center.y - current.y
                let distanceFromFocus = hypot(x / max(1, size.width * 0.60),
                                              y / max(1, size.height * 0.57))
                let fade = min(1, max(0, (distanceFromFocus - 0.22) / 0.74))
                let attention = 1 - fade * fade * (3 - 2 * fade)
                if abs(x) < size.width / 2 + tile.width, abs(y) < size.height / 2 + tile.height {
                    let imageSize = piece.width
                    let growth = bubbleBirth(for: piece.id, elapsed: birthElapsed)
                    Group {
                        if let idea = idea(at: index) {
                            Button {
                                chooseIdea(at: piece.id)
                            } label: {
                                bubbleSurface(
                                    Artwork(idea: idea, height: imageSize, rounded: false, thumbnail: true, thumbnailMaxPixelSize: 1200).equatable(),
                                    size: imageSize, morph: piece.morph, usesCrystal: usesCrystal
                                )
                            }
                            .buttonStyle(HapticPlainStyle())
                            .accessibilityLabel("Elegir \(idea.title) para el día \(day)")
                            .accessibilityAddTraits(hasScrolled && selectionSettled && piece.id == focused ? [.isSelected] : [])
                        } else if case .ornament(let name) = entries[index] {
                            Button { chooseIdea(at: piece.id) } label: {
                                OrnamentBubble(
                                    name: name, index: index, size: imageSize,
                                    animated: !reduceMotion && !limitsEffects && attention > 0.30
                                )

                            }
                            .buttonStyle(HapticPlainStyle())
                            .accessibilityLabel("¡Sorpréndeme! Elegir una travesura aleatoria para el día \(day)")
                        }
                    }
                    .scaleEffect(max(0.05, growth))
                    .blur(radius: 5 * fade * fade)
                    .opacity((0.65 + 0.35 * attention) * min(1, growth * 1.65))
                    .offset(x: x, y: y)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .accessibilityAdjustableAction { direction in
            hasScrolled = true
            selectionSettled = false
            let increment = direction == .increment ? 1 : -1
            let index = focused.row * columns + focused.column
            let next = index + increment
            let column = wrapped(next, modulo: columns)
            let slot = Slot(row: (next - column) / columns, column: column)
            scrollRequest = center(of: slot)
        }

        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: focused)
    }

    private func bubbleSurface<Content: View>(
        _ content: Content, size: CGFloat, morph: CGFloat, usesCrystal: Bool
    ) -> some View {
        content
            .frame(width: size, height: size)
            .clipped()
            .layerEffect(
                ShaderLibrary.crystalLens(.float2(Float(size), Float(size)), .float(Float(morph))),
                maxSampleOffset: CGSize(width: 32, height: 32),
                isEnabled: usesCrystal && morph > 0.01
            )
            .clipShape(Circle().inset(by: size * 0.025))
            .overlay {
                Image("OrnamentBubbleGlass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 640 / 520, height: size * 640 / 520)
                    .offset(x: size * 3 / 520)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    private func updateEffectBudget() {
        let info = ProcessInfo.processInfo
        limitsEffects = info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
            || info.isLowPowerModeEnabled
    }

    private func selectRandomIdea() {
        guard let idea = ideas.randomElement() else { return }
        select(idea)
    }

    private func chooseIdea(at slot: Slot) {
        bubbleGuideSeen = true
        AppHaptics.tap()
        if let selectedIdea = idea(at: entryIndex(for: slot)) {
            select(selectedIdea)
        } else {
            selectRandomIdea()
        }
    }
}

private struct OrnamentBubble: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    let index: Int
    let size: CGFloat
    let animated: Bool

    var body: some View {
        let moving = animated && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { timeline in
            let time = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
            let phase = time * 0.45 + Double(index)
            let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
            let rotation = Double((index * 71) % 360)
                + direction * time.truncatingRemainder(dividingBy: 60) * 6
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.66, height: size * 0.66)
                .rotationEffect(.degrees(rotation))
                .offset(x: moving ? sin(phase) * size * 0.035 : 0,
                        y: moving ? cos(phase * 0.8) * size * 0.045 : 0)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Image("OrnamentBubbleGlass")
                .resizable()
                .scaledToFit()
                // Align the visible shell inside the PNG's transparent padding.
                .frame(width: size * 640 / 520, height: size * 640 / 520)
                .offset(x: size * 3 / 520)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct NativeBoardScroll: UIViewRepresentable {
    private let midpoint: CGFloat = 32_768
    let start: CGPoint
    let request: CGPoint?
    let animated: Bool
    let started: () -> Void
    let snap: (CGPoint) -> CGPoint
    let moved: (CGPoint) -> Void
    let settled: (CGPoint) -> Void
    let tapped: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BoardScrollView {
        let view = BoardScrollView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.contentInsetAdjustmentBehavior = .never
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.scrollsToTop = false
        view.travel = CGSize(width: midpoint * 2, height: midpoint * 2)
        view.initialOffset = CGPoint(x: midpoint, y: midpoint)
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return view
    }

    func updateUIView(_ view: BoardScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if let request, request != coordinator.lastRequest {
            coordinator.lastRequest = request
            let target = coordinator.offset(for: request)
            if animated, view.contentOffset != target {
                view.setContentOffset(target, animated: true)
            } else {
                Task { @MainActor in
                    guard coordinator.lastRequest == request else { return }
                    view.setContentOffset(target, animated: false)
                    coordinator.parent.settled(request)
                }
            }
        } else if request == nil {
            coordinator.lastRequest = nil
        }
    }

    final class BoardScrollView: UIScrollView {
        var travel = CGSize.zero
        var initialOffset: CGPoint?

        override func layoutSubviews() {
            super.layoutSubviews()
            let extent = CGSize(width: bounds.width + travel.width, height: bounds.height + travel.height)
            if contentSize != extent { contentSize = extent }
            if let initialOffset, !bounds.isEmpty {
                self.initialOffset = nil
                contentOffset = initialOffset
            }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: NativeBoardScroll
        var lastRequest: CGPoint?

        private var origin: CGPoint
        private var isRecentering = false

        init(_ parent: NativeBoardScroll) {
            self.parent = parent
            origin = parent.start
        }

        func offset(for point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - origin.x + parent.midpoint,
                    y: point.y - origin.y + parent.midpoint)
        }

        private func position(_ view: UIScrollView) -> CGPoint {
            CGPoint(x: view.contentOffset.x - parent.midpoint + origin.x,
                    y: view.contentOffset.y - parent.midpoint + origin.y)
        }

        private func finishScroll(_ view: UIScrollView) {
            let point = position(view)
            let target = parent.snap(point)
            if hypot(target.x - point.x, target.y - point.y) > 0.5 {
                view.setContentOffset(offset(for: target), animated: parent.animated)
                if parent.animated { return }
            }
            if abs(view.contentOffset.x - parent.midpoint) > parent.midpoint / 4
                || abs(view.contentOffset.y - parent.midpoint) > parent.midpoint / 4 {
                isRecentering = true
                origin = target
                view.contentOffset = CGPoint(x: parent.midpoint, y: parent.midpoint)
                isRecentering = false
            }
            parent.settled(target)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if !isRecentering { parent.moved(position(scrollView)) }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.started()
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let projected = CGPoint(x: targetContentOffset.pointee.x - parent.midpoint + origin.x,
                                    y: targetContentOffset.pointee.y - parent.midpoint + origin.y)
            targetContentOffset.pointee = offset(for: parent.snap(projected))
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { finishScroll(scrollView) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finishScroll(scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            finishScroll(scrollView)
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UIScrollView else { return }
            let point = gesture.location(in: view)
            parent.tapped(CGPoint(x: point.x - view.bounds.minX, y: point.y - view.bounds.minY))
        }
    }
}

private struct GenerateIdeaPressStyle: ButtonStyle {
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(AppTypography.selection)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: cardBarControlHeight)
            .background(ideaControlTint, in: Capsule())
            .modifier(GlassSurface(prominent: false, radius: cardBarControlHeight / 2))
            .overlay { CardActionHalo(animated: animated) }
            .contentShape(Rectangle())
            .modifier(ButtonHaptics(isPressed: configuration.isPressed))
            .overlay {
                Capsule()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.30), .pink.opacity(0.15), .clear],
                        center: .center, startRadius: 0, endRadius: 110
                    ))
                    .opacity(configuration.isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct CardActionHalo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let animated: Bool
    var cornerRadius: CGFloat = 1000

    var body: some View {
        let moving = animated && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !moving)) { timeline in
            let phase = moving
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.8) / 3.8
                : 0
            let angle = Angle.degrees(phase * 360 - 120)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AngularGradient(
                    stops: [
                        .init(color: .purple.opacity(0.56), location: 0),
                        .init(color: .pink.opacity(0.66), location: 0.22),
                        .init(color: .white, location: 0.32),
                        .init(color: .cyan.opacity(0.65), location: 0.43),
                        .init(color: .purple.opacity(0.28), location: 0.72),
                        .init(color: .purple.opacity(0.56), location: 1)
                    ],
                    center: .center, startAngle: angle, endAngle: angle + .degrees(360)
                ), lineWidth: 1.6)
                .shadow(color: .pink.opacity(0.64), radius: 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private let ideaControlTint = LinearGradient(
    colors: [
        Color(red: 0.19, green: 0.14, blue: 0.31).opacity(0.75),
        Color(red: 0.57, green: 0.27, blue: 0.45).opacity(0.55),
        Color(red: 0.31, green: 0.24, blue: 0.48).opacity(0.68)
    ],
    startPoint: .bottomLeading, endPoint: .topTrailing
)

private struct CardGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ButtonHaptics(isPressed: configuration.isPressed))
            .font(.system(size: 16, weight: .semibold))
            .frame(width: cardBarControlHeight, height: cardBarControlHeight)
            .background(ideaControlTint, in: Circle())
            .modifier(GlassSurface(prominent: false, radius: cardBarControlHeight / 2))
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct OnboardingActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ButtonHaptics(isPressed: configuration.isPressed))
            .modifier(AppTypography.selection)
            .foregroundStyle(Color(red: 0.18, green: 0.11, blue: 0.23))
            .frame(maxWidth: .infinity, minHeight: cardBarControlHeight)
            .background {
                Capsule().fill(LinearGradient(
                    colors: [.white, Color(red: 0.91, green: 0.95, blue: 1), .white,
                             Color(red: 1, green: 0.90, blue: 0.97), .white],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            }
            .overlay {
                Capsule().strokeBorder(.white, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .white.opacity(0.6), radius: 7)
            .shadow(color: Color(red: 1, green: 0.8, blue: 0.94).opacity(0.4), radius: 18)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private struct PrimaryIdeaControl: ViewModifier {
    var animated = true

    func body(content: Content) -> some View {
        content.buttonStyle(GenerateIdeaPressStyle(animated: animated))
    }
}

private struct AssignmentControlAppearance: ViewModifier {
    let primary: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if primary {
            content.modifier(PrimaryIdeaControl())
        } else {
            content.buttonStyle(GlassControl(white: true))
        }
    }
}

private struct CatalogBackdrop: ViewModifier {
    let ideas: [Trastada]
    @State private var visibleID: Trastada.ID?

    func body(content: Content) -> some View {
        content
            .scrollPosition(id: $visibleID)
            .sensoryFeedback(.impact(weight: .heavy, intensity: 0.85), trigger: visibleID) { previous, current in
                guard let previous, let current else { return false }
                return ideas.contains { $0.id == previous } && ideas.contains { $0.id == current }
            }
            .background {
                FloatingDecorations(
                    idea: ideas.first { $0.id == visibleID } ?? ideas.first,
                    showsDecorations: false
                )
            }
    }
}

private struct FloatingDecorations: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let idea: Trastada?
    var showsDecorations = true
    var showsSnow = false

    private struct Piece {
        let name: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let tilt: Double
        let blur: CGFloat
    }

    private let pieces = [
        Piece(name: "Thread", x: 0.14, y: 0.20, width: 47, tilt: -13, blur: 2),
        Piece(name: "Reindeer", x: 0.93, y: 0.64, width: 86, tilt: 15, blur: 2),
        Piece(name: "Wrap", x: 0.86, y: 0.14, width: 56, tilt: -19, blur: 3),
        Piece(name: "Envelope", x: 0.18, y: 0.92, width: 63, tilt: 12, blur: 2),
        Piece(name: "Mailbox", x: 0.10, y: 0.53, width: 53, tilt: -9, blur: 4),
        Piece(name: "Snowman", x: 0.80, y: 0.86, width: 54, tilt: 12, blur: 2),
        Piece(name: "Snowflake", x: 0.20, y: 0.29, width: 125, tilt: -14, blur: 9),
        Piece(name: "Sleigh", x: 0.81, y: 0.58, width: 145, tilt: -12, blur: 8),
        Piece(name: "Flour", x: 0.14, y: 0.69, width: 92, tilt: 15, blur: 5),
        Piece(name: "Cookie", x: 0.88, y: 0.34, width: 76, tilt: 24, blur: 3),
        Piece(name: "Tape", x: 0.29, y: 0.09, width: 35, tilt: 18, blur: 2.2),
        Piece(name: "Ornament", x: 0.75, y: 0.07, width: 36, tilt: -15, blur: 1.5),
        Piece(name: "Paper", x: 0.96, y: 0.48, width: 47, tilt: 18, blur: 2.6),
        Piece(name: "Gift", x: 0.11, y: 0.76, width: 43, tilt: -13, blur: 2),
        Piece(name: "Hat", x: 0.04, y: 0.11, width: 105, tilt: -21, blur: 0),
        Piece(name: "Cocoa", x: 0.95, y: 0.95, width: 91, tilt: 13, blur: 0),
        Piece(name: "Candy", x: 0.01, y: 0.40, width: 90, tilt: -16, blur: 0),
        Piece(name: "Star", x: 0.96, y: 0.76, width: 88, tilt: 16, blur: 0),
        Piece(name: "Stocking", x: 0.03, y: 0.90, width: 83, tilt: -10, blur: 0)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    FrostedBackdrop()
                    if let idea, let photo = Artwork.photo(for: idea) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(1.28)
                            .blur(radius: 44, opaque: true)
                            .saturation(0.94)
                            .overlay {
                                LinearGradient(
                                    colors: [.black.opacity(0.64), .black.opacity(0.24), .black.opacity(0.56)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            }
                            .clipped()
                            .id(idea.id)
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.46), value: idea?.id)

                RadialGradient(
                    stops: [
                        .init(color: Color(red: 0.43, green: 0.16, blue: 0.78).opacity(0.63), location: 0),
                        .init(color: Color(red: 0.51, green: 0.19, blue: 0.76).opacity(0.30), location: 0.48),
                        .init(color: Color(red: 0.68, green: 0.27, blue: 0.72).opacity(0.08), location: 0.78),
                        .init(color: .clear, location: 1)
                    ],
                    center: UnitPoint(x: 0.02, y: 0.06), startRadius: 0, endRadius: geometry.size.width * 0.96
                )
                RadialGradient(
                    stops: [
                        .init(color: Color(red: 0.93, green: 0.30, blue: 0.65).opacity(0.25), location: 0),
                        .init(color: Color(red: 0.84, green: 0.29, blue: 0.70).opacity(0.12), location: 0.45),
                        .init(color: .clear, location: 1)
                    ],
                    center: UnitPoint(x: 0.22, y: 0.17), startRadius: 0, endRadius: geometry.size.width * 0.68
                )
                RadialGradient(
                    stops: [
                        .init(color: Color(red: 0.82, green: 0.28, blue: 0.71).opacity(0.30), location: 0),
                        .init(color: Color(red: 0.52, green: 0.24, blue: 0.75).opacity(0.13), location: 0.52),
                        .init(color: .clear, location: 1)
                    ],
                    center: .bottomTrailing, startRadius: 0, endRadius: geometry.size.width * 0.82
                )

                if showsDecorations || showsSnow {
                    TimelineView(.animation(minimumInterval: 1.0 / 12, paused: reduceMotion || scenePhase != .active)) { context in
                        let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                        snow(at: time)
                        if showsDecorations {
                            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                                let wave = sin(time * 0.72 + Double(index) * 1.3)
                                Image("Decoration" + piece.name)
                                    .resizable().scaledToFit()
                                    .frame(width: piece.width * 1.16)
                                    .rotationEffect(.degrees(piece.tilt + wave * 6))
                                    .blur(radius: piece.blur)
                                    .opacity(piece.blur >= 5 ? 0.32 : (piece.blur == 0 ? 0.9 : 0.63))
                                    .position(
                                        x: geometry.size.width * piece.x + wave * (piece.blur == 0 ? 4 : 2),
                                        y: geometry.size.height * piece.y + wave * (piece.blur == 0 ? 10 : 5)
                                    )
                            }
                        }
                    }
                }
            }
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func snow(at time: TimeInterval) -> some View {
        Canvas { context, size in
            guard size.width > 0 && size.height > 0 else { return }
            for index in 0..<44 {
                let phase = Double(index)
                let speed = 9 + Double(index % 5) * 4
                let x = size.width * ((phase * 0.618).truncatingRemainder(dividingBy: 1))
                    + sin(time * 0.55 + phase) * 8
                let y = (time * speed + phase * 157).truncatingRemainder(dividingBy: size.height + 20) - 10
                let diameter = CGFloat(2 + index % 4)
                if index % 3 == 0 {
                    let glint = time == 0 || index % 2 != 0 ? 0 : pow(max(0, sin(time * 1.65 + phase * 0.83)), 10)
                    let radius = diameter * 1.30
                    var crystal = context
                    crystal.translateBy(x: x, y: y)
                    crystal.rotate(by: .radians(phase * 0.21))
                    crystal.stroke(snowCrystal(radius: radius), with: .color(.white.opacity(0.36 + 0.59 * glint)), lineWidth: 0.7)
                    if glint > 0.04 {
                        let flare = radius * (1 + glint * 1.12)
                        let glowSize = flare * 2
                        crystal.fill(
                            Path(ellipseIn: CGRect(x: -flare, y: -flare, width: glowSize, height: glowSize)),
                            with: .radialGradient(
                                Gradient(colors: [.white.opacity(0.56 * glint), .clear]),
                                center: .zero, startRadius: 0, endRadius: flare
                            )
                        )
                        var reflection = Path()
                        reflection.move(to: CGPoint(x: -flare, y: 0))
                        reflection.addLine(to: CGPoint(x: flare, y: 0))
                        reflection.move(to: CGPoint(x: 0, y: -flare))
                        reflection.addLine(to: CGPoint(x: 0, y: flare))
                        crystal.stroke(reflection, with: .color(.white.opacity(glint * 0.76)), lineWidth: 0.65)
                    }
                } else {
                    let flake = CGRect(x: x, y: y, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: flake), with: .color(.white.opacity(0.30 + Double(index % 4) * 0.10)))
                }
            }
        }
    }

    private func snowCrystal(radius: CGFloat) -> Path {
        var crystal = Path()
        for arm in 0..<6 {
            let angle = Double(arm) * .pi / 3
            let dx = cos(angle)
            let dy = sin(angle)
            let branch = CGPoint(x: dx * radius * 0.55, y: dy * radius * 0.55)
            crystal.move(to: .zero)
            crystal.addLine(to: CGPoint(x: dx * radius, y: dy * radius))
            for turn in [-Double.pi / 4, Double.pi / 4] {
                crystal.move(to: branch)
                crystal.addLine(to: CGPoint(
                    x: branch.x + cos(angle + turn) * radius * 0.35,
                    y: branch.y + sin(angle + turn) * radius * 0.35
                ))
            }
        }
        return crystal
    }
}

private struct FilterEditor: View {
    @State private var draft: CatalogFilters
    let ideas: [Trastada]
    let save: (CatalogFilters) -> Void

    init(initial: CatalogFilters, ideas: [Trastada], save: @escaping (CatalogFilters) -> Void) {
        _draft = State(initialValue: initial)
        self.ideas = ideas
        self.save = save
    }

    var body: some View {
        List {
            Section("Número de elfos") {
                optionRow("Uno", checked: draft.selections[.elves] == ["1 elfo"]) {
                    draft.selections[.elves] = ["1 elfo"]
                }
                optionRow("Dos o más", checked: draft.selections[.elves] == ["2 elfos"]) {
                    draft.selections[.elves] = ["2 elfos"]
                }
            }

        }
        .listStyle(.insetGrouped)
        .buttonStyle(HapticPlainStyle())
        .tint(.blue)
        .navigationTitle("Filtros del catálogo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, filters in
            save(filters)
        }
    }

    private func optionRow(_ label: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                if checked { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.blue) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticPlainStyle())
        .foregroundStyle(.primary)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

private struct MaterialTagLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var frames: [CGRect] = []
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}

private struct RemoveAssignmentButton: View {
    @State private var confirming = false
    var iconOnly = false
    let remove: () -> Void

    var body: some View {
        Group {
            if iconOnly {
                Button(role: .destructive) { confirming = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: dayControlHeight, height: dayControlHeight)
                        .modifier(GlassSurface(prominent: false, radius: dayControlHeight / 2))
                }
                .buttonStyle(HapticPlainStyle())
                .accessibilityLabel("Eliminar")
            } else {
                Button(role: .destructive) { confirming = true } label: {
                    Label("Eliminar", systemImage: "trash")
                }
                .buttonStyle(GlassControl())
            }
        }
        .accessibilityHint("Quita la travesura del calendario")
        .alert("¿Seguro que quieres eliminarla?", isPresented: $confirming) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive, action: remove)
        } message: {
            Text("La travesura se quitará del calendario.")
        }
    }
}

private struct DayAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var frames: [Frame] = []
    @State private var started = Date()
    let day: Int
    let preview: Trastada?
    var miniature = false
    var animated = true
    var displayHeight: CGFloat = 280

    private var height: CGFloat { displayHeight }
    private var playsMotion: Bool { animated && !reduceMotion }
    private static let poster = UIImage(named: "EmptyStatePosterAlpha.png")
    private static let sharedAnimation = Task.detached(priority: .userInitiated) {
        guard let url = Bundle.main.url(forResource: "EmptyState", withExtension: "apng") else { return [Frame]() }
        return loadFrames(from: url, animated: true, maxSize: 560)
    }

    private struct Frame: Sendable {
        let image: UIImage
        let end: TimeInterval
    }

    var body: some View {
        Group {
            if let first = frames.first, let last = frames.last {
                if !playsMotion || frames.count == 1 {
                    image(first.image)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 24, paused: scenePhase != .active)) { timeline in
                        let elapsed = max(0, timeline.date.timeIntervalSince(started))
                            .truncatingRemainder(dividingBy: last.end)
                        image((frames.first { elapsed < $0.end } ?? last).image)
                    }
                }
            } else if let poster = Self.poster {
                image(poster)
            } else if miniature {
                if playsMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
                        let beat = sin(timeline.date.timeIntervalSince(started) * 6)
                        miniatureElf(rotation: beat * 13, lift: abs(beat) * -4)
                    }
                } else {
                    miniatureElf(rotation: Double(day % 5 - 2) * 5, lift: 0)
                }
            } else if let preview {
                Artwork(idea: preview, height: height)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(pink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .accessibilityHidden(true)
        .frame(width: miniature ? height + 6 : nil)
        .task(id: playsMotion) {
            let name = String(format: "elf-day-%02d", day)
            let decoded: [Frame]
            if let url = Bundle.main.url(forResource: name, withExtension: "gif") {
                let animated = playsMotion
                let size = miniature ? 144 : 840
                decoded = await Task.detached {
                    Self.loadFrames(from: url, animated: animated, maxSize: size)
                }.value
            } else if playsMotion {
                decoded = await Self.sharedAnimation.value
            } else {
                decoded = []
            }
            guard !Task.isCancelled else { return }
            frames = decoded
            started = Date()
        }
    }

    private func miniatureElf(rotation: Double, lift: Double) -> some View {
        Text("🧝")
            .font(.system(size: height * 0.76))
            .rotationEffect(.degrees(rotation))
            .offset(y: lift)
            .frame(width: height + 6, height: height)
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func image(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    nonisolated private static func loadFrames(from url: URL, animated: Bool, maxSize: Int) -> [Frame] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        var end: TimeInterval = 0
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ] as CFDictionary
        let count = CGImageSourceGetCount(source)
        return (0..<(animated ? count : min(count, 1))).compactMap { index in
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions)
            else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let png = properties?[kCGImagePropertyPNGDictionary as String] as? [String: Any]
            let gifDelay = gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
                ?? gif?[kCGImagePropertyGIFDelayTime as String] as? Double
            let pngDelay = png?[kCGImagePropertyAPNGUnclampedDelayTime as String] as? Double
                ?? png?[kCGImagePropertyAPNGDelayTime as String] as? Double
            let delay = gifDelay ?? pngDelay ?? 0.1
            end += delay >= 0.02 ? delay : 0.1
            return Frame(image: UIImage(cgImage: frame), end: end)
        }
    }
}

private struct IdeaHeroGeometry: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let hero: (namespace: Namespace.ID, id: String)?
    var destination = false

    @ViewBuilder func body(content: Content) -> some View {
        if let hero, !reduceMotion {
            if destination {
                content
                    .clipShape(.rect(cornerRadius: expanded ? pearlCardRadius : 150))
                    .matchedGeometryEffect(id: hero.id, in: hero.namespace)
                    .task {
                        withAnimation(.easeInOut(duration: 0.38)) { expanded = true }
                    }
            } else {
                content.matchedGeometryEffect(id: hero.id, in: hero.namespace)
            }
        } else {
            content
        }
    }
}

private struct CardPhoto: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var captionVisible = false
    let idea: Trastada
    let height: CGFloat
    let captionInset: CGFloat
    var context: String? = nil
    var showsPlaceholder = true
    var showsInstructions = false
    var presentsCaption = false
    var showsMetadata = false

    var body: some View {
        Artwork(idea: idea, height: height, rounded: false)
            .blur(radius: showsInstructions ? 24 : 0, opaque: true)
            .overlay(Color(red: 88 / 255, green: 49 / 255, blue: 82 / 255).opacity(showsInstructions ? 0.2 : 0))
            .overlay {
                Artwork(idea: idea, height: height, rounded: false)
                    .blur(radius: 27, opaque: true)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.43),
                                .init(color: .black.opacity(0.30), location: 0.58),
                                .init(color: .black.opacity(0.88), location: 0.75),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .opacity(showsInstructions ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.44),
                        .init(color: .black.opacity(0.24), location: 0.63),
                        .init(color: .black.opacity(0.58), location: 0.87),
                        .init(color: .black.opacity(0.63), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(showsInstructions ? 0 : 1)
                .allowsHitTesting(false)
            }
            .clipped()
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    if let context {
                        Text(context)
                            .modifier(AppTypography(name: "Inter-Medium", size: 13, relativeTo: .footnote))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    Text(idea.title)
                        .modifier(AppTypography(name: "NewKansasSwash-RegularItalic", size: 36, relativeTo: .title2, lineHeight: 1.2))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    if showsMetadata {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) { metadata }
                            VStack(spacing: 4) { metadata }
                        }
                        .modifier(AppTypography.context)
                        .foregroundStyle(.white.opacity(0.92))
                    }
                    if context == nil && showsPlaceholder {
                        Text("Lorem ipsum dolor sit amet.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.77))
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                }
                .opacity(showsInstructions ? 0 : 1)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, captionInset)
                .opacity(!presentsCaption || captionVisible || reduceMotion ? 1 : 0)
                .offset(y: presentsCaption && !captionVisible && !reduceMotion ? 8 : 0)
                .allowsHitTesting(false)
            }
            .task {
                guard presentsCaption, !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) { captionVisible = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibleCaption)
    }

    private var accessibleCaption: String {
        let title = context.map { "\($0) \(idea.title)" } ?? idea.title
        guard showsMetadata else { return title }
        return idea.time.isEmpty ? "\(title). \(difficulty)" : "\(title). \(idea.time). \(difficulty)"
    }

    private var difficulty: String { "Dificultad \(idea.difficulty.lowercased())" }

    @ViewBuilder private var metadata: some View {
        if !idea.time.isEmpty {
            Label {
                Text(idea.time)
            } icon: {
                Text("🕒").accessibilityHidden(true)
            }
        }
        Label {
            Text(difficulty)
        } icon: {
            Text("💪").accessibilityHidden(true)
        }
    }
}

private struct Artwork: View, Equatable {
    let idea: Trastada
    let height: CGFloat
    var rounded = true
    var thumbnail = false
    var thumbnailMaxPixelSize: CGFloat = 500

    var body: some View {
        GeometryReader { geometry in
            if let photo = thumbnail ? Self.thumbnail(for: idea, maxPixelSize: thumbnailMaxPixelSize) : Self.photo(for: idea) {
                Image(uiImage: photo).resizable().interpolation(.high).scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(colors: [pink, accent.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if !thumbnail {
                        Text("Foto pendiente")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: rounded ? 16 : 0, style: .continuous))
        .accessibilityHidden(true)
    }

    private static var photoAvailability: [String: Bool] = [:]

    @MainActor static func hasPhoto(_ idea: Trastada) -> Bool {
        if photoAvailability[idea.id] == true { return true }
        // Solo guardamos los aciertos: una imagen remota puede descargarse más tarde.
        let available = photo(for: idea) != nil
        if available { photoAvailability[idea.id] = true }
        return available
    }

    static func photo(for idea: Trastada) -> UIImage? {
        // Primero la foto descargada de Supabase; las de Assets solo como respaldo.
        RemoteArtwork.image(for: idea) ?? UIImage(named: idea.imagePath ?? idea.id) ?? UIImage(named: idea.id)
    }

    private static let thumbnailAssets: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func thumbnail(for idea: Trastada, maxPixelSize: CGFloat = 500) -> UIImage? {
        let id = "\(idea.id)-\(idea.imagePath ?? "")-\(Int(maxPixelSize))" as NSString
        if let cached = thumbnailAssets.object(forKey: id) { return cached }
        guard let photo = photo(for: idea) else { return nil }
        let image = photo.preparingThumbnail(of: CGSize(width: maxPixelSize * 0.8, height: maxPixelSize)) ?? photo
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        thumbnailAssets.setObject(image, forKey: id, cost: cost)
        return image
    }

    @MainActor static func shareUIImage(for idea: Trastada) -> UIImage? {
        let renderer = ImageRenderer(content:
            Artwork(idea: idea, height: 800, rounded: false)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 12) {
                        Text(idea.title)
                            .modifier(AppTypography(name: "NewKansasSwash-RegularItalic", size: 42, relativeTo: .largeTitle, lineHeight: 1.2))
                        Text("Elf Help!").modifier(AppTypography.context)
                    }
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                }
                .frame(width: 640, height: 800)
        )
        renderer.scale = 2
        return renderer.uiImage ?? photo(for: idea)
    }
}

private struct ChristmasFarewell: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.title2)
                .accessibilityHidden(true)
            Text("¡Feliz Navidad!")
                .systemHeading(.largeTitle)
            Text("Los elfos vuelven al Polo Norte. Gracias por llenar de magia estas mañanas. ¡Nos vemos el próximo diciembre!")
                .modifier(AppTypography.body)
                .foregroundStyle(.white.opacity(0.86))
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: 380)
    }
}

private struct ClubInvitation: View {
    let url: URL?
    let source: String

    private var campaignURL: URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let campaign = [
            URLQueryItem(name: "utm_source", value: "elf_help"),
            URLQueryItem(name: "utm_medium", value: "app"),
            URLQueryItem(name: "utm_content", value: source)
        ]
        components.queryItems = (components.queryItems ?? []).filter { item in
            !campaign.contains { $0.name == item.name }
        } + campaign
        return components.url
    }

    var body: some View {
        if let campaignURL {
            VStack(alignment: .leading, spacing: 8) {
                Text("Que dure la magia").systemHeading(.title3)
                Link("Conocer el club de cartas", destination: campaignURL)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(pink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

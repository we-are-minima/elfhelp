import SwiftUI
import UserNotifications
import UIKit
import ImageIO
import NaturalLanguage

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
    case idea(Trastada), day(Int), calendar, settings, setup, filters, club, closing

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
        }
    }
}

private enum SetupStep: Int {
    case introduction = 1, preferences, dates, reminders, loading, welcome
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
    @State private var setupShownThisLaunch = false
    @State private var preferredDifficulty = "Me da igual"
    @State private var cleanupPreference = "Me da igual"
    @State private var customWeekdays = false
    @State private var weekdayMask = 127
    @AppStorage("planningWeekdays") private var planningWeekdays = 127
    @State private var startDay = 1
    @State private var endDay = 24
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
    @State private var elfPreference = "Me da igual"
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
    @State private var focusedDay: Int?
    @State private var replacing: Trastada?
    @State private var replacementDay: Int?
    @State private var now = Self.planningDate

    private static var planningDate: Date {
        #if DEBUG
        return DecemberEdition(year: 2026).date(3)
        #else
        return Date()
        #endif
    }
    @State private var reminderTask: Task<Void, Never>?
    private let edition = DecemberEdition(year: 2026)
    private let catalog: [Trastada] = {
        guard let url = Bundle.main.url(forResource: "Catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Trastada].self, from: data)) ?? []
    }()

    private var illustratedCatalog: [Trastada] {
        catalog.filter(Artwork.hasPhoto)
    }

    private var storedPlan: DecemberPlan {
        (try? JSONDecoder().decode(DecemberPlan.self, from: savedPlan)) ?? DecemberPlan()
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
                            showsDecorations: surpriseRound == nil && panel == nil && !showSplash
                        )
                    }
                    .overlay(alignment: .center) {
                        if showsConfirmation {
                            Label("Idea sustituida con éxito", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(ideaControlTint, in: RoundedRectangle(cornerRadius: 16))
                                .modifier(GlassSurface(prominent: false, radius: 16, interactive: false))
                                .padding(.horizontal, 12)
                                .allowsHitTesting(false)
                                .transition(reduceMotion ? .opacity : .offset(y: 12).combined(with: .opacity))
                        }
                    }
                    .transition(screenTransition)
                }
            }
            .task(id: confirmationCount) {
                guard confirmationCount > 0 else { return }
                do {
                    try await Task.sleep(for: .milliseconds(420))
                    withAnimation(.easeInOut(duration: 0.22)) { showsConfirmation = true }
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
                        IdeaBoard(ideas: round.ideas, size: space.size, day: round.day, cancel: {
                            surpriseRound = nil
                        }) { idea, namespace, heroID, confirm in
                            detail(idea, day: nil, confirm: confirm, hero: (namespace, heroID))
                        } select: { idea in
                            commit(idea, to: round.day)
                            surpriseRound = nil
                        }
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
                    Color.white
                        .overlay {
                            Image("Splash").resizable().scaledToFit().accessibilityLabel("Elf Help!")
                        }
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .animation(screenAnimation, value: showSplash)
            .fullScreenCover(isPresented: Binding(
                get: { panel?.id == "setup" },
                set: { if !$0, panel?.id == "setup" { panel = nil } }
            )) {
                panelContent(.setup)
            }
            .sheet(item: Binding(
                get: { panel?.id == "setup" ? nil : panel },
                set: { if panel?.id != "setup" { panel = $0 } }
            ), onDismiss: {
                calendarDetailPage = nil
                if now >= edition.date(26), !closingSeen { activate() }
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
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.white)
                                    .accessibilityLabel("Cerrar")
                                }
                            }
                        }
                }
                .tint(.primary)
                .buttonStyle(GlassControl())
                .presentationBackground { FrostedBackdrop() }
                .presentationDetents([.large])
                .interactiveDismissDisabled(current.id == "setup")
            }
            .confirmationDialog(
                "¿Cambiar la trastada del día \(replacementDay ?? 0)?",
                isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
                titleVisibility: .visible
            ) {
                Button("Sustituir trastada") {
                    if let replacing, let replacementDay { commit(replacing, to: replacementDay) }
                    replacing = nil
                }
                Button("Cancelar", role: .cancel) { replacing = nil }
            } message: {
                if let replacementDay, let existing = idea(on: replacementDay) { Text(existing.title) }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            if showSplash {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                showSplash = false
            }
            activate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in activate() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { activate() } }
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

    private var selectedDay: Int { focusedDay ?? edition.stripFocus(now) }

    private var dailyHome: some View {
        GeometryReader { space in
            let cardWidth = space.size.width * 0.94
            let cardHeight = max(0, min(space.size.height * 0.67, cardWidth * dayPhotoRatio))
            dailyCards(width: cardWidth, height: cardHeight, viewportHeight: space.size.height)
                .allowsHitTesting(surpriseRound == nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func dailyCards(width: CGFloat, height: CGFloat, viewportHeight: CGFloat) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: -(min(118, height * 0.24) * 1.6)) {
                ForEach(DecemberEdition.pages, id: \.self) { day in
                    dailyCard(page: day, height: height)
                        .frame(width: width, height: height)
                        .modifier(AssignmentCelebration(trigger: day == confirmedDay ? confirmationCount : 0))
                        .overlay {
                            let shape = RoundedRectangle(cornerRadius: pearlCardRadius)
                            shape.fill(LinearGradient(
                                colors: [.white.opacity(0.33), .white.opacity(0.12)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .overlay { shape.strokeBorder(.white.opacity(0.58)) }
                            .opacity(day == selectedDay ? 0 : 1)
                            .animation(.easeInOut(duration: 0.22), value: day == selectedDay)
                            .allowsHitTesting(false)
                        }
                        .shadow(color: .black.opacity(day == selectedDay ? 0.32 : 0), radius: 12, y: 3)
                        .scrollTransition(.interactive, axis: .vertical) { [reduceMotion] card, phase in
                            let depth = abs(phase.value)
                            return card
                                .scaleEffect(reduceMotion ? 1 : 1 - depth * 0.12)
                                .saturation(1 - depth * 0.23)
                        }
                        .zIndex(-Double(abs(day - selectedDay)))
                        .id(day)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.vertical, max(0, (viewportHeight - height) / 2), for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: Binding<Int?>(
            get: { selectedDay },
            set: { if let day = $0, day != selectedDay { focusedDay = day } }
        ), anchor: .center)
        .frame(height: viewportHeight)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.10),
                .init(color: .black, location: 0.90),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    private func dailyCard(page: Int, height: CGFloat) -> some View {
        let active = page == selectedDay
        let day = page
        let date = edition.calendarDate(for: page)
        let dayNumber = edition.calendar.component(.day, from: date)
        let shortMonth = date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "es_ES")))
        let assigned = idea(on: day)
        let editable = canEdit(day)
        let preview = catalog.indices.contains(day - 1) ? catalog[day - 1] : nil

        return Group {
            if page == DecemberEdition.pages.upperBound {
                ViewThatFits(in: .vertical) {
                    farewell(day: day)
                    ScrollView { farewell(day: day) }
                }
                .padding(.top, 36)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
            } else if let idea = assigned {
                Button { panel = .day(day) } label: {
                    CardPhoto(
                        idea: idea, height: height,
                        captionInset: editable ? cardBarControlHeight + cardIconInset + 26 : 24,
                        context: "La idea propuesta para el \(dayNumber) de \(shortMonth)"
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if editable {
                        Button("Genera otra idea", systemImage: "sparkles") { startSurprise(for: day) }
                            .modifier(PrimaryIdeaControl(animated: page == selectedDay
                                && surpriseRound == nil && panel == nil && !showSplash))
                            .padding(cardIconInset)
                            .opacity(active ? 1 : 0)
                            .allowsHitTesting(active)
                            .accessibilityHidden(!active)
                    }
                }
            } else {
                emptyDayContent(
                    day, editable: editable && active, preview: preview,
                    height: max(60, height - 2 * pearlCardInset - (editable ? 76 : 32)),
                    showMessage: edition.today(now) == day || edition.nextDiscovery(now) == day,
                    animated: selectedDay == page && surpriseRound == nil && panel == nil && !showSplash
                )
            }
        }
        .modifier(DayCardFrame(alignment: .topLeading, inset: assigned == nil ? pearlCardInset : 0))
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Button { panel = .calendar } label: {
                    cardDateBadge(for: date)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre el calendario de trastadas")
                if page != DecemberEdition.pages.upperBound, let assigned {
                    share(assigned, cardGlass: true)
                }
            }
            .padding(cardIconInset)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
        }
        .animation(.easeInOut(duration: 0.18), value: active)
    }

    private func farewell(day: Int) -> some View {
        ChristmasFarewell { panel = .day(day) }
    }

    private func cardDateBadge(for date: Date) -> some View {
        let locale = Locale(identifier: "es_ES")
        let month = date.formatted(.dateTime.month(.abbreviated).locale(locale))
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        let past = date < edition.calendar.startOfDay(for: now)
        return VStack(spacing: 0) {
            Text(month.uppercased(with: locale))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
            Text(edition.calendar.component(.day, from: date), format: .number)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            HStack(spacing: 2) {
                Text(weekday)
                if past { Image(systemName: "checkmark") }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.78))
        }
        .frame(width: cardBarControlHeight, height: cardBarControlHeight)
        .background(ideaControlTint, in: Circle())
        .modifier(GlassSurface(prominent: false, radius: cardBarControlHeight / 2, interactive: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
    }

    private var ideaList: some View {
        let options = listIdeas
        return VStack(alignment: .leading, spacing: 12) {
            Text(assignmentDay.map { "Elige la trastada para el \($0) de diciembre" } ?? "Catálogo de trastadas")
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
                .buttonStyle(.plain)
        }
    }

    private func catalogCard<Preview: View>(
        _ idea: Trastada,
        @ViewBuilder preview: @escaping (CardPhoto) -> Preview
    ) -> some View {
        let day = plan.assignments.first(where: { $0.value == idea.id })?.key
        let hasActions = day.map(canEdit) ?? planningDays.contains(where: canEdit)
        return GeometryReader { space in
            preview(CardPhoto(idea: idea, height: space.size.height, captionInset: hasActions || day != nil ? 72 : 24))
                .overlay(alignment: .bottom) {
                    HStack(spacing: 10) {
                        if let day {
                            Text("\(day) de diciembre")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        calendarAction(for: idea)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
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
        return count == 1 ? Text("1 trastada") : Text("\(count) trastadas")
    }

    private var emptyResults: some View {
        ContentUnavailableView {
            Label("No hay trastadas disponibles", systemImage: "sparkles")
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
        case .closing:
            ScrollView {
                ChristmasFarewell {
                    panel = nil
                    focusedDay = DecemberEdition.pages.upperBound
                }
                .padding(24)
            }
        }
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
                    let danceHeight = min(520, space.size.height * 0.63)
                    DayAnimation(day: startDay, preview: illustratedCatalog.first, displayHeight: danceHeight)
                        .frame(width: space.size.width)
                        .position(x: space.size.width / 2, y: space.size.height * 0.58)
                        .overlay(alignment: .top) {
                            setupHeading("Preparación", title: "Cargando tu experiencia")
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                        }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            } else if setupStep == .welcome {
                GeometryReader { space in
                    let logoHeight = min(220, space.size.height * 0.37)
                    Image("Logo").resizable().scaledToFit()
                        .frame(width: min(300, space.size.width - 48), height: logoHeight)
                        .accessibilityLabel("Elf Help!")
                        .position(x: space.size.width / 2, y: space.size.height / 2)
                        .overlay(alignment: .top) {
                            Text("Veamos qué están tramando los elfos.")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, (space.size.height + logoHeight) / 2 + 12)
                        }
                }
            } else {
                setupPages
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
            FloatingDecorations(idea: nil, showsDecorations: true, showsSnow: true)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var setupPages: some View {
        ScrollView {
            VStack(spacing: 18) {
                switch setupStep {
                case .introduction:
                    VStack(spacing: 12) {
                        Text("La Navidad empieza aquí")
                            .font(.subheadline.weight(.medium))
                        Text("¿Y mañana dónde pongo al elfo?")
                            .font(.custom("ITCGaramondStd-LtCond", size: 54, relativeTo: .largeTitle))
                            .accessibilityAddTraits(.isHeader)
                        Text("Descubre cómo crear magia sin complicaciones. Basta con abrir la notificación que te llegará cada noche con la mejor de las ideas.")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    introductionBubbles

                case .preferences:
                    setupHeading("Personalización", title: "En mi casa somos más de…",
                                 message: "Elige las opciones perfectas para ti y nosotros las prepararemos mágicamente")
                    VStack(alignment: .leading, spacing: 14) {
                        Text("¿Cuántos elfos hay en casa?").font(.headline)
                        Picker("¿Cuántos elfos hay en casa?", selection: $elfPreference) {
                            Text("Uno").tag("1 elfo")
                            Text("Dos o más").tag("2 elfos")
                            Text("Me da igual").tag("Me da igual")
                        }
                        .pickerStyle(.segmented)
                        Divider()
                        Text("¿Cuánto quieres preparar?").font(.headline)
                        setupRadioGroup([
                            ("Me da igual", "Me da igual"),
                            ("Cambiarlo de sitio", "Fácil"),
                            ("Preparar algo sencillo", "Media"),
                            ("Montar una escena", "Elaborada")
                        ], selection: $preferredDifficulty)
                    }
                    .padding(16)
                    .modifier(GlassSurface(prominent: false, radius: 24, interactive: false))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("¿Cuánto quieres recoger después?").font(.headline)
                        setupRadioGroup(
                            ["Nada", "Un poco", "Me da igual"].map { ($0, $0) },
                            selection: $cleanupPreference
                        )
                    }
                    .padding(16)
                    .modifier(GlassSurface(prominent: false, radius: 24, interactive: false))

                case .dates:
                    setupHeading("Fechas", title: "¿Qué mañanas aparece el elfo?",
                                 message: "Elige cuándo empieza, cuándo acaba y si se toma algún día libre")
                    VStack(alignment: .leading, spacing: 20) {
                        DatePicker("Primera mañana", selection: setupDate($startDay),
                                   in: edition.date(1)...edition.date(endDay), displayedComponents: .date)
                        DatePicker("Última mañana", selection: setupDate($endDay),
                                   in: edition.date(startDay)...edition.date(24), displayedComponents: .date)
                        Divider()
                        Text("¿Qué días de la semana?").font(.headline)
                        Toggle(customWeekdays ? "Elegir días" : "Cada mañana", isOn: $customWeekdays)
                            .toggleStyle(.switch)
                            .accessibilityLabel("Elegir días")
                            .accessibilityHint("Desactivado para cada mañana")
                        if customWeekdays { weekdayChoices }
                    }
                    .datePickerStyle(.compact)
                    .padding(16)
                    .modifier(GlassSurface(prominent: false, radius: 24, interactive: false))

                case .reminders:
                    OnboardingBell()
                    setupHeading("Avisos", title: "¡Que no se duerma la magia!",
                                 message: "Elige una hora y te damos un toque la noche anterior. Así tu elfo hace su trastada antes de que te venza el sueño.")
                    reminderTimePicker
                        .labelsHidden()
                        .datePickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .modifier(GlassSurface(prominent: false, radius: 24, interactive: false))
                case .loading, .welcome:
                    EmptyView()
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }

    private func setupRadioGroup(_ options: [(String, String)], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.1) { label, value in
                let selected = selection.wrappedValue == value
                Button {
                    selection.wrappedValue = value
                } label: {
                    Label(label, systemImage: selected ? "largecircle.fill.circle" : "circle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var introductionBubbles: some View {
        GeometryReader { space in
            let diameter = min(146, space.size.width * 0.39)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    floatingPreview("DecorationThread", size: diameter * 0.33, x: -0.96, y: -1.08, depth: 0.27, time: time, container: space.size, ornament: true)
                    floatingPreview("DecorationWrap", size: diameter * 0.38, x: 0.94, y: -1.12, depth: 0.40, time: time, container: space.size, ornament: true)
                    floatingPreview("scene-snow-bowling", size: diameter * 0.31, x: 0.04, y: -1.23, depth: 0.31, time: time, container: space.size)
                    floatingPreview("DecorationEnvelope", size: diameter * 0.37, x: -0.95, y: 0.84, depth: 0.63, time: time, container: space.size, ornament: true)
                    floatingPreview("DecorationMailbox", size: diameter * 0.42, x: 0.97, y: 1.02, depth: 0.55, time: time, container: space.size, ornament: true)
                    floatingPreview("DecorationSnowman", size: diameter * 0.37, x: -0.20, y: 1.12, depth: 0.68, time: time, container: space.size, ornament: true)
                    floatingPreview("DecorationReindeer", size: diameter * 0.43, x: 0.90, y: -0.27, depth: 0.51, time: time, container: space.size, ornament: true)
                    floatingPreview("scene-mandarin-choir", size: diameter * 0.45, x: -0.59, y: -0.67, depth: 0.42, time: time, container: space.size)
                    floatingPreview("DecorationStar", size: diameter * 0.41, x: 0.67, y: -0.63, depth: 0.34, time: time, container: space.size, ornament: true)
                    floatingPreview("trastada-011", size: diameter * 0.68, x: -0.68, y: 0.32, depth: 0.7, time: time, container: space.size)
                    floatingPreview("scene-sink-regatta", size: diameter * 0.62, x: 0.68, y: 0.34, depth: 0.63, time: time, container: space.size)
                    floatingPreview("trastada-002", size: diameter, x: 0, y: -0.02, depth: 1, time: time, container: space.size)
                    floatingPreview("scene-rubber-ducks", size: diameter * 0.58, x: -0.69, y: 1.42, depth: 0.72, time: time, container: space.size)
                    floatingPreview("scene-spaghetti-chef", size: diameter * 0.64, x: 0.10, y: 1.67, depth: 0.82, time: time, container: space.size)
                    floatingPreview("DecorationCandy", size: diameter * 0.34, x: 0.72, y: 1.65, depth: 0.43, time: time, container: space.size, ornament: true)
                    floatingPreview("scene-sack-race", size: diameter * 0.49, x: 0.66, y: 1.24, depth: 0.51, time: time, container: space.size)
                    floatingPreview("DecorationSnowflake", size: diameter * 0.28, x: -0.70, y: 1.84, depth: 0.33, time: time, container: space.size, ornament: true)
                    floatingPreview("DecorationGift", size: diameter * 0.43, x: 0.46, y: 0.74, depth: 0.90, time: time, container: space.size, ornament: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 420)
        .accessibilityHidden(true)
    }

    private func floatingPreview(
        _ name: String, size: CGFloat, x: Double, y: Double, depth: Double, time: Double, container: CGSize, ornament: Bool = false
    ) -> some View {
        let phase = time * (0.9 + depth * 0.4) + x * 4 + y * 3
        let horizontal = x * Double(container.width) * 0.35 + (reduceMotion ? 0 : sin(phase) * 8 * depth)
        let vertical = (y - 0.30) * Double(container.height) * 0.27 + (reduceMotion ? 0 : cos(phase) * 11 * depth)
        return Group {
            if ornament {
                OrnamentBubble(name: name, index: 5, size: size, drift: .zero, animated: false)
            } else {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay {
                        Image("OrnamentBubbleGlass")
                            .resizable()
                            .scaledToFit()
                            .frame(width: size * 1.2, height: size * 1.2)
                            .opacity(0.67)
                    }
            }
        }
        .frame(width: size, height: size)
        .blur(radius: (1 - depth) * 4)
        .opacity(0.40 + depth * 0.60)
        .offset(x: horizontal, y: vertical)
    }

    @ViewBuilder private var setupFooter: some View {
        switch setupStep {
        case .introduction:
            Button("Siguiente") { setupStep = .preferences }
                .buttonStyle(OnboardingActionStyle())
        case .preferences:
            Button("Crear mis ideas") { setupStep = .dates }
                .buttonStyle(OnboardingActionStyle())
        case .dates:
            Button("Guardar fechas") { setupStep = .reminders }
                .buttonStyle(OnboardingActionStyle())
                .disabled(customWeekdays && !(startDay...endDay).contains { includesWeekday($0, mask: weekdayMask) })
        case .reminders:
            VStack(spacing: 10) {
                Button("Prefiero arriesgarme") {
                    remindersEnabled = false
                    refreshReminders()
                    setupStep = .loading
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                Button("Activar avisos") {
                    Task {
                        await enableReminders()
                        setupStep = .loading
                    }
                }
                .buttonStyle(OnboardingActionStyle())
            }
            .disabled(requestingReminders)
        case .loading:
            SetupProgress { setupStep = .welcome }
        case .welcome:
            Button("¡Vamos!", action: finishSetup)
                .buttonStyle(OnboardingActionStyle())
        }
    }

    private func setupHeading(_ section: String, title: String, message: String? = nil) -> some View {
        VStack(spacing: 12) {
            Text(section).font(.subheadline.weight(.medium))
            Text(title)
                .font(.custom("ITCGaramondStd-LtCond", size: 54, relativeTo: .largeTitle))
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message).font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setupDate(_ day: Binding<Int>) -> Binding<Date> {
        Binding(get: { edition.date(day.wrappedValue) },
                set: { day.wrappedValue = edition.calendar.component(.day, from: $0) })
    }

    private func includesWeekday(_ day: Int, mask: Int) -> Bool {
        let index = (edition.calendar.component(.weekday, from: edition.date(day)) + 5) % 7
        return mask & (1 << index) != 0
    }

    private var weekdayChoices: some View {
        let names = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
        let fullNames = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
            ForEach(names.indices, id: \.self) { index in
                let bit = 1 << index
                let selected = weekdayMask & bit != 0
                Button(names[index]) { weekdayMask ^= bit }
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .background(selected ? Color.white : Color.white.opacity(0.13), in: Capsule())
                    .foregroundStyle(selected ? Color.black : Color.white)
                    .buttonStyle(.plain)
                    .accessibilityLabel(fullNames[index])
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func finishSetup() {
        var filters: [CatalogFilter: Set<String>] = [:]
        if elfPreference != "Me da igual" { filters[.elves] = [elfPreference] }
        if preferredDifficulty != "Me da igual" { filters[.difficulty] = [preferredDifficulty] }
        if cleanupPreference != "Me da igual" { filters[.cleanup] = ["Mínima"] }
        if cleanupPreference == "Nada" { filters[.time] = ["Hasta 5 min"] }
        planningWeekdays = customWeekdays ? weekdayMask : 127
        firstPlanningDay = startDay
        lastPlanningDay = endDay
        let preferences = CatalogFilters(filters)
        saveFilters(preferences)
        applyStarterPlan(using: preferences, fillNewDates: true)
        initialSetupComplete = true
        let target = edition.stripFocus(now)
        let activeDays = planningDays.filter { includesWeekday($0, mask: planningWeekdays) }
        focusedDay = activeDays.first { $0 >= target } ?? activeDays.last
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
                Text(editable ? "Aún no hay trastada" : "Ese día no hubo trastada")
                    .systemHeading(.title3)
            }
            if editable {
                Button("Añadir trastada", systemImage: "calendar.badge.plus") { choose(for: day) }
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

                Text("Materiales")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 10)
                MaterialTagLayout(spacing: 7) {
                    ForEach(Array(idea.materialTags.enumerated()), id: \.offset) { _, material in
                        Text(material)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .overlay { Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1) }
                    }
                }

                Text("Preparación")
                    .font(.title3.weight(.semibold))
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if let confirm {
                    Button("Elegir esta idea", systemImage: "checkmark") {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        confirm()
                    }
                        .modifier(PrimaryIdeaControl())
                } else if let scheduledDay, canEdit(scheduledDay) {
                    Button("Genera otra idea", systemImage: "sparkles") { startSurprise(for: scheduledDay) }
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
        let image = Artwork.shareImage(for: idea)
        let link = ShareLink(
            item: image,
            subject: Text("Elf help!"),
            message: Text("Mira qué trastada he encontrado. ¡Descárgate la app de Elf Help!" + (appStoreURL.map { "\n\($0.absoluteString)" } ?? "")),
            preview: SharePreview(idea.title, image: image)
        ) {
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
            .accessibilityHint("Añade la trastada al día \(assignmentDay)")
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
                reminderTimePicker
                    .disabled(!remindersEnabled)
                if remindersEnabled {
                    Button("Desactivar avisos", systemImage: "bell.slash") {
                        remindersEnabled = false
                        refreshReminders()
                    }
                } else {
                    Button("Activar avisos", systemImage: "bell") {
                        Task { await enableReminders() }
                    }
                    .disabled(requestingReminders)
                }
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        settingsLabel("Permisos de notificación", icon: "gearshape", tint: .gray)
                    }
                }
            } header: {
                Text("Avisos de preparación")
            } footer: {
                Text("Recibe un aviso la noche anterior a cada trastada.")
            }
            Section("Preferencias") {
                Button {
                    focusedDay = selectedDay
                    browsingCatalog = true
                    panel = nil
                } label: {
                    settingsLabel("Ver catálogo", icon: "rectangle.on.rectangle", tint: .pink)
                }
                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in Text(option.rawValue).tag(option) }
                } label: {
                    settingsLabel("Apariencia", icon: "circle.lefthalf.filled", tint: .orange)
                }
                NavigationLink {
                    FilterEditor(initial: filterSelection, ideas: illustratedCatalog, save: saveFilters)
                } label: {
                    settingsLabel("Filtros del catálogo", icon: "slider.horizontal.3", tint: .purple)
                }
            }
            Section("Información") {
                NavigationLink {
                    List {
                        Section("Planifica diciembre") {
                            Text("Desliza la tarjeta o toca una fecha. Pulsa Añadir trastada, elige una idea y confirma con Añadir.")
                        }
                        Section("Si no llegan los avisos") {
                            Text("Comprueba que estén activados en Elf help! y en los Ajustes de iOS.")
                        }
                    }
                    .navigationTitle("Ayuda")
                } label: {
                    settingsLabel("Ayuda", icon: "questionmark.circle", tint: .blue)
                }
                NavigationLink {
                    List {
                        Section("Datos en tu iPhone") {
                            Text("Tu calendario, los filtros y la hora de los avisos se guardan en este dispositivo. Puedes usar Elf help! sin crear una cuenta.")
                        }
                        Section("Enlaces externos") {
                            Text("El club de cartas y el formulario de recordatorio se abren en la web.")
                        }
                    }
                    .navigationTitle("Privacidad")
                } label: {
                    settingsLabel("Privacidad", icon: "hand.raised", tint: .green)
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
        .buttonStyle(.automatic)
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsLabel(_ title: String, icon: String, tint: Color) -> some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
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
        let stored = (try? JSONDecoder().decode([CatalogFilter: Set<String>].self, from: savedFilters)) ?? [:]
        return CatalogFilters(stored)
    }

    private func saveFilters(_ filters: CatalogFilters) {
        if let encoded = try? JSONEncoder().encode(filters.selections) { savedFilters = encoded }
    }

    private func idea(on day: Int) -> Trastada? { catalog.first { $0.id == plan.assignments[day] } }

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
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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

    private func activate() {
        let currentDate = Self.planningDate
        if !edition.calendar.isDate(now, inSameDayAs: currentDate) { focusedDay = nil }
        now = currentDate
        guard !showSplash, panel?.id != "setup" else { return }
        if shouldShowSetup {
            setupShownThisLaunch = true
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
        if now >= edition.date(26), !closingSeen {
            closingSeen = true
            panel = .closing
        } else if let day = edition.today(now), [8, 18].contains(day),
                  clubURL != nil, clubModalCount < 2, clubModalDay != day {
            clubModalDay = day
            clubModalCount += 1
            panel = .club
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


private struct OnboardingBell: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || scenePhase != .active)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6)
            let swing = elapsed < 1 ? sin(elapsed * .pi * 7) * (1 - elapsed) * 20 : 0
            Image("OnboardingBell")
                .resizable()
                .scaledToFit()
                .frame(height: 170)
                .rotationEffect(.degrees(reduceMotion ? 0 : swing), anchor: UnitPoint(x: 0.48, y: 0.17))
        }
        .accessibilityHidden(true)
    }
}

private struct SetupProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    let complete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())
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
                    .frame(width: space.size.width * progress)
                    .clipShape(Capsule())
                }
                .overlay { Capsule().strokeBorder(.white.opacity(0.4)) }
        }
            .frame(height: 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando tu experiencia")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        .task {
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
                RoundedRectangle(cornerRadius: pearlCardRadius)
                    .strokeBorder(highlight, lineWidth: 3)
                    .shadow(color: .pink, radius: 6)
                    .opacity(reduceMotion ? 0 : glow)
                    .overlay {
                        if reduceMotion {
                            RoundedRectangle(cornerRadius: pearlCardRadius)
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

private let pearlCardInset: CGFloat = 12
private let pearlCardRadius: CGFloat = cardBarControlHeight / 2 + 12
private let pearlCardOuterInset: CGFloat = 2
private let dayControlHeight: CGFloat = 50
private let cardBarControlHeight: CGFloat = 56
private let dayPhotoRatio: CGFloat = 1.43
private let surpriseButtonHeight: CGFloat = 104
private let surpriseButtonInset: CGFloat = 14
private let cardIconInset: CGFloat = 18
private let dayCardHeightToWidth: CGFloat = 1.54

private extension View {
    func systemHeading(_ size: Font.TextStyle) -> some View {
        let points: CGFloat = switch size {
        case .largeTitle: 39
        case .title2: 28
        case .title3: 24
        default: 17
        }
        return font(.custom("ITCGaramondStd-LtCond", size: points, relativeTo: size))
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
        .buttonStyle(.plain)
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
    private let shape = RoundedRectangle(cornerRadius: pearlCardRadius, style: .continuous)

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
            .padding(.horizontal, pearlCardOuterInset)
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
            .font(.subheadline.weight(quiet ? .regular : (filled ? .semibold : .medium)))
            .padding(.horizontal, iconOnly ? 0 : 12)
            .padding(.vertical, iconOnly ? 0 : 5)
            .frame(minWidth: iconOnly ? 44 : nil, minHeight: 44)
            .modifier(GlassSurface(prominent: filled, radius: 24, darkInk: darkInk))
            .opacity(enabled ? 1 : 0.55)
    }
}

private struct SurpriseRound {
    let day: Int
    let ideas: [Trastada]
}

private struct IdeaBoard<Detail: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var limitsEffects = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        || ProcessInfo.processInfo.isLowPowerModeEnabled
    @Namespace private var heroNamespace
    @State private var openedSlot: Slot?
    @State private var settledCenters: [CGPoint] = []
    @State private var birthStarted: Date?
    @State private var birthSeed = UInt.random(in: 0...UInt.max)
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
    let ideas: [Trastada]
    let size: CGSize
    let day: Int
    let cancel: () -> Void
    let detail: (Trastada, Namespace.ID, String, @escaping () -> Void) -> Detail
    let select: (Trastada) -> Void

    private let columns = 6
    private let columnDrift: [CGFloat] = [-8, 9, -11, 6, -5, 8]
    private let rowDrift: [CGFloat] = [-7, 10, -4, 8, 2, -8, 5]
    private let tile = CGSize(width: 170, height: 220)
    private let spacing = CGSize(width: 174, height: 151)

    private func center(of index: Int) -> CGPoint {
        settledCenters.indices.contains(index) ? settledCenters[index] : originalCenter(of: index)
    }

    private func originalCenter(of index: Int) -> CGPoint {
        let row = index / columns
        let column = index % columns
        let horizontal = CGFloat((index * 37 + row * 13) % 17 - 8)
        let vertical = CGFloat((index * 29 + row * 17) % 19 - 9)
        let stagger = (row.isMultiple(of: 2) ? -0.25 : 0.25) * spacing.width
        return CGPoint(x: CGFloat(column) * spacing.width + stagger + rowDrift[row % rowDrift.count] + horizontal,
                       y: CGFloat(row) * spacing.height + (columnDrift[column] + vertical) * 0.72)
    }

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
        let index = entryIndex(for: slot)
        let source = center(of: index)
        return CGPoint(x: source.x + CGFloat(slot.column - index % columns) * spacing.width,
                       y: source.y + CGFloat(slot.row - index / columns) * spacing.height)
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private var startingPosition: CGPoint {
        let middle = Slot(row: (repeatingRows - 1) / 2, column: (min(columns, entryCount) - 1) / 2)
        return center(of: nearestCard(to: center(of: middle)))
    }

    private func nearestCard(to point: CGPoint) -> Slot {
        let row = Int((point.y / spacing.height).rounded())
        let column = Int((point.x / spacing.width).rounded())
        let nearby = ((row - 2)...(row + 2)).flatMap { r in
            ((column - 2)...(column + 2)).map { Slot(row: r, column: $0) }
        }
        return nearby.filter { idea(at: entryIndex(for: $0)) != nil }.min {
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
        let resting = backdropPosition ?? startingPosition
        let restingCard = idea(at: entryIndex(for: nearestCard(to: resting))) ?? ideas[0]
        return Group {
            if openedSlot == nil && !settledCenters.isEmpty {
                let pieces = packedPieces(around: current)
                TimelineView(.animation(paused: birthStarted == nil || reduceMotion)) { timeline in
                    grid(at: current, pieces: pieces, birthElapsed: birthStarted.map { timeline.date.timeIntervalSince($0) })
                }
                    .overlay {
                        NativeBoardScroll(start: current, request: scrollRequest,
                                          animated: !reduceMotion) { point in
                            position = point
                        } settled: { point in
                            scrollRequest = nil
                            backdropPosition = point
                        } tapped: { point in
                            let boardPoint = CGPoint(x: current.x + point.x - size.width / 2,
                                                     y: current.y + point.y - size.height / 2)
                            if let piece = pieces.first(where: { piece in
                                distance(from: piece.center, to: boardPoint) <= piece.corner
                            }) {
                                openIdea(at: piece.id)
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
            var rest = entries.indices.map { index in
                let width = diameter(of: index)
                return Piece(id: Slot(row: index / columns, column: index % columns), center: originalCenter(of: index), width: width,
                             height: width, corner: width / 2, morph: 0)
            }
            resolveContacts(&rest, passes: 80)
            if !reduceMotion { birthStarted = Date() }
            settledCenters = rest.map(\.center)
            if birthStarted != nil {
                try? await Task.sleep(for: .milliseconds(810))
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
            HStack {
                Button("Volver", systemImage: "arrow.uturn.backward", action: cancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(GlassControl(iconOnly: true))
                VStack(spacing: 3) {
                    Text("Elige tu idea")
                        .systemHeading(.title3)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(day) de diciembre")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                Color.clear.frame(width: 44)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, cardIconInset)
            .frame(height: 54)
        }
        .accessibilityHidden(openedSlot != nil)
        .overlay {
            if let slot = openedSlot, let idea = idea(at: entryIndex(for: slot)) {
                VStack(spacing: 0) {
                    HStack {
                        Button("Volver al tablero", systemImage: "chevron.left") { openedSlot = nil }
                            .labelStyle(.iconOnly)
                            .buttonStyle(GlassControl(iconOnly: true))
                        detailHeading("La idea")
                            .frame(maxWidth: .infinity)
                        Color.clear.frame(width: 44)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, cardIconInset)
                    .frame(height: 54)
                    detail(idea, heroNamespace, slot.heroID) { select(idea) }
                }
                .background { FloatingDecorations(idea: idea, showsDecorations: false, showsSnow: true) }
                .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            updateEffectBudget()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            updateEffectBudget()
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.16 : 0.40), value: openedSlot)
    }

    private struct Piece: Identifiable {
        let id: Slot
        var center: CGPoint
        let width: CGFloat
        let height: CGFloat
        let corner: CGFloat
        let morph: CGFloat
    }

    private func diameter(of index: Int) -> CGFloat {
        CGFloat(124 + (index * 37) % 21) * (idea(at: index) == nil ? 0.94 : 1.25)
    }

    private func packedPieces(around focus: CGPoint) -> [Piece] {
        var pieces = visibleCards(around: focus).map { slot in
            let index = entryIndex(for: slot)
            let origin = center(of: slot)
            let fraction = max(0, 1 - distance(from: origin, to: focus) / (spacing.width * 1.72))
            let morph = reduceMotion ? 0 : fraction * fraction * fraction * (fraction * (6 * fraction - 15) + 10)
            let width = diameter(of: index) + (idea(at: index) == nil ? 22 : 55) * morph
            return Piece(id: slot, center: origin, width: width, height: width,
                         corner: width / 2, morph: morph)
        }
        resolveContacts(&pieces, passes: 36)
        return pieces
    }

    private func resolveContacts(_ pieces: inout [Piece], passes: Int) {
        guard pieces.count > 1 else { return }

        var pairs: [(first: Int, second: Int, separation: CGFloat, weight: CGFloat)] = []
        for first in 0..<(pieces.count - 1) {
            for second in (first + 1)..<pieces.count {
                let a = pieces[first]
                let b = pieces[second]
                if b.id.row - a.id.row > 2 { break }
                if abs(b.id.column - a.id.column) > 2 { continue }
                pairs.append((first, second, a.corner + b.corner + 3, 0.5 + (b.morph - a.morph) * 0.42))
            }
        }

        for _ in 0..<passes {
            var corrected = false
            for (first, second, separation, weight) in pairs {
                let a = pieces[first]
                let b = pieces[second]
                let dx = b.center.x - a.center.x
                let dy = b.center.y - a.center.y
                let squaredDistance = dx * dx + dy * dy
                guard squaredDistance < separation * separation, squaredDistance > 0 else { continue }
                let distance = sqrt(squaredDistance)
                let overlap = separation - distance
                guard overlap > 0.10 else { continue }
                let pushX = dx * (overlap / distance)
                let pushY = dy * (overlap / distance)
                pieces[first].center.x -= pushX * weight
                pieces[first].center.y -= pushY * weight
                pieces[second].center.x += pushX * (1 - weight)
                pieces[second].center.y += pushY * (1 - weight)
                corrected = true
            }
            if !corrected { break }
        }
    }

    private func bubbleBirth(for slot: Slot, elapsed: TimeInterval?) -> CGFloat {
        guard !reduceMotion, let elapsed else { return 1 }
        let variation = UInt(bitPattern: slot.hashValue) ^ birthSeed
        let delay = Double(variation % 220) / 1000
        let duration = 0.44 + Double((variation >> 8) % 120) / 1000
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
                    let imageSize = diameter(of: index)
                    let growth = bubbleBirth(for: piece.id, elapsed: birthElapsed)
                    Group {
                        if let idea = idea(at: index) {
                            Button {
                                openIdea(at: piece.id)
                            } label: {
                                bubbleSurface(
                                    Artwork(idea: idea, height: imageSize, rounded: false, thumbnail: true).equatable(),
                                    size: imageSize, morph: piece.morph, attention: attention, usesCrystal: usesCrystal
                                )
                            }
                            .buttonStyle(.plain)
                            .modifier(IdeaHeroGeometry(hero: (heroNamespace, piece.id.heroID)))
                            .accessibilityLabel(idea.title)
                            .accessibilityAddTraits(piece.id == focused ? [.isSelected] : [])
                        } else if case .ornament(let name) = entries[index] {
                            OrnamentBubble(
                                name: name, index: index, size: imageSize, drift: CGSize(width: x, height: y),
                                animated: !reduceMotion && !limitsEffects && attention > 0.30
                            )
                            .accessibilityHidden(true)
                        }
                    }
                    .scaleEffect(piece.width / imageSize * max(0.05, growth))
                    .opacity((0.025 + 0.975 * attention) * min(1, growth * 1.65))
                    .offset(x: x, y: y)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .accessibilityAdjustableAction { direction in
            let increment = direction == .increment ? 1 : -1
            let index = focused.row * columns + focused.column
            for step in 1...(columns * repeatingRows) {
                let next = index + increment * step
                let column = wrapped(next, modulo: columns)
                let slot = Slot(row: (next - column) / columns, column: column)
                if idea(at: entryIndex(for: slot)) != nil {
                    scrollRequest = center(of: slot)
                    break
                }
            }
        }

        .sensoryFeedback(.selection, trigger: focused)
    }

    private func bubbleSurface<Content: View>(
        _ content: Content, size: CGFloat, morph: CGFloat, attention: CGFloat, usesCrystal: Bool
    ) -> some View {
        content
            .frame(width: size, height: size)
            .clipped()
            .layerEffect(
                ShaderLibrary.crystalLens(.float2(Float(size), Float(size)), .float(Float(morph))),
                maxSampleOffset: CGSize(width: 32, height: 32),
                isEnabled: usesCrystal && morph > 0.01
            )
            .clipShape(Circle())
            .overlay {
                if usesCrystal && attention > 0.20 {
                    Image("OrnamentBubbleGlass")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 1.20, height: size * 1.20)
                        .frame(width: size, height: size)
                        .mask {
                            AngularGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.13),
                                    .init(color: .white, location: 0.25),
                                    .init(color: .clear, location: 0.39),
                                    .init(color: .clear, location: 0.60),
                                    .init(color: .white, location: 0.75),
                                    .init(color: .clear, location: 0.89),
                                    .init(color: .clear, location: 1)
                                ],
                                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                            )
                            .mask {
                                RadialGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.75),
                                        .init(color: .white, location: 0.94),
                                        .init(color: .white, location: 1)
                                    ],
                                    center: .center, startRadius: 0, endRadius: size / 2
                                )
                                .clipShape(Circle())
                            }
                        }
                        .opacity((attention - 0.20) * 0.46)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                Circle().strokeBorder(.white.opacity(0.08 + 0.19 * attention), lineWidth: 1)
            }
    }

    private func updateEffectBudget() {
        let info = ProcessInfo.processInfo
        limitsEffects = info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
            || info.isLowPowerModeEnabled
    }

    private func openIdea(at slot: Slot) {
        guard idea(at: entryIndex(for: slot)) != nil else { return }
        openedSlot = slot
    }
}

private struct OrnamentBubble: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    let index: Int
    let size: CGFloat
    let drift: CGSize
    let animated: Bool

    var body: some View {
        let moving = animated && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !moving)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 0.48 + Double(index)
            let motion = moving ? sin(phase) : 0
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.72, height: size * 0.72)
                .rotationEffect(.degrees(Double((index * 71) % 360) + motion * 8))
                .offset(x: reduceMotion ? 0 : -drift.width * 0.018 + motion * 4,
                        y: reduceMotion ? 0 : -drift.height * 0.014 + motion * 6)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Image("OrnamentBubbleGlass")
                .resizable()
                .scaledToFit()
                // The original PNG includes transparent padding around the shell.
                .frame(width: size * 1.20, height: size * 1.20)
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
            if abs(view.contentOffset.x - parent.midpoint) > parent.midpoint / 4
                || abs(view.contentOffset.y - parent.midpoint) > parent.midpoint / 4 {
                isRecentering = true
                origin = point
                view.contentOffset = CGPoint(x: parent.midpoint, y: parent.midpoint)
                isRecentering = false
            }
            parent.settled(point)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if !isRecentering { parent.moved(position(scrollView)) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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

    var body: some View {
        let moving = animated && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !moving)) { timeline in
            let phase = moving
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.8) / 3.8
                : 0
            let angle = Angle.degrees(phase * 360 - 120)
            Capsule()
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.18, green: 0.11, blue: 0.23))
            .frame(maxWidth: .infinity, minHeight: cardBarControlHeight)
            .background {
                Capsule().fill(LinearGradient(
                    colors: [.white, Color(red: 0.91, green: 0.95, blue: 1), .white,
                             Color(red: 1, green: 0.90, blue: 0.97), .white],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            }
            .overlay { Capsule().strokeBorder(.white.opacity(0.95)).allowsHitTesting(false) }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private struct PrimaryIdeaControl: ViewModifier {
    var animated = true

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: cardBarControlHeight)
            .background(ideaControlTint, in: Capsule())
            .modifier(GlassSurface(prominent: false, radius: cardBarControlHeight / 2))
            .overlay { CardActionHalo(animated: animated) }
            .buttonStyle(GenerateIdeaPressStyle())
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
            .sensoryFeedback(.selection, trigger: visibleID) { previous, current in
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
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CatalogFilters
    let ideas: [Trastada]
    let save: (CatalogFilters) -> Void

    init(initial: CatalogFilters, ideas: [Trastada], save: @escaping (CatalogFilters) -> Void) {
        _draft = State(initialValue: initial)
        self.ideas = ideas
        self.save = save
    }

    var body: some View {
        let count = ideas.count(where: draft.matches)
        List {
            ForEach(CatalogFilter.allCases) { group in
                Section(group.rawValue) {
                    optionRow("Cualquiera", checked: draft.selections[group] == nil) {
                        draft.selections[group] = nil
                    }
                    ForEach(group.options, id: \.self) { option in
                        optionRow(option, checked: draft.selections[group]?.contains(option) == true) {
                            draft.toggle(option, in: group)
                        }
                    }
                }
            }
            Button("Restablecer filtros") { draft = CatalogFilters() }
        }
        .navigationTitle("Filtros")
        .safeAreaInset(edge: .bottom) {
            Button {
                save(draft)
                dismiss()
            } label: {
                Text(count == 1 ? "Ver 1 trastada" : "Ver \(count) trastadas")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(GlassControl(prominent: true))
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func optionRow(_ label: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                if checked { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassControl(prominent: checked, darkInk: true))
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
                .buttonStyle(.plain)
                .accessibilityLabel("Eliminar")
            } else {
                Button(role: .destructive) { confirming = true } label: {
                    Label("Eliminar", systemImage: "trash")
                }
                .buttonStyle(GlassControl())
            }
        }
        .accessibilityHint("Quita la trastada del calendario")
        .alert("¿Seguro que quieres eliminarla?", isPresented: $confirming) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive, action: remove)
        } message: {
            Text("La trastada se quitará del calendario.")
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
                    .background(pink, in: RoundedRectangle(cornerRadius: 16))
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
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
    }

    private func image(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16))
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
    @ScaledMetric(relativeTo: .title2) private var titleSize = 32.0
    let idea: Trastada
    let height: CGFloat
    let captionInset: CGFloat
    var context: String? = nil
    var showsPlaceholder = true
    var presentsCaption = false
    var showsMetadata = false

    var body: some View {
        Artwork(idea: idea, height: height, rounded: false)
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
                .allowsHitTesting(false)
            }
            .clipped()
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    if let context {
                        Text(context)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    Text(idea.title)
                        .font(.custom("ITCGaramondStd-LtCond", fixedSize: titleSize))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    if showsMetadata {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) { metadata }
                            VStack(spacing: 4) { metadata }
                        }
                        .font(.subheadline.weight(.medium))
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
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
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
        return showsMetadata ? "\(title). \(idea.time). \(difficulty)" : title
    }

    private var difficulty: String { "Dificultad \(idea.difficulty.lowercased())" }

    @ViewBuilder private var metadata: some View {
        Label {
            Text(idea.time)
        } icon: {
            Text("🕒").accessibilityHidden(true)
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

    var body: some View {
        GeometryReader { geometry in
            if let photo = thumbnail ? Self.thumbnail(for: idea) : Self.photo(for: idea) {
                Image(uiImage: photo).resizable().scaledToFill()
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
        .clipShape(RoundedRectangle(cornerRadius: rounded ? 16 : 0))
        .accessibilityHidden(true)
    }

    private static var photoAvailability: [String: Bool] = [:]

    @MainActor static func hasPhoto(_ idea: Trastada) -> Bool {
        if let available = photoAvailability[idea.id] { return available }
        let available = photo(for: idea) != nil
        photoAvailability[idea.id] = available
        return available
    }

    static func photo(for idea: Trastada) -> UIImage? {
        UIImage(named: idea.id)
    }

    private static let thumbnailAssets: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func thumbnail(for idea: Trastada) -> UIImage? {
        let id = idea.id as NSString
        if let cached = thumbnailAssets.object(forKey: id) { return cached }
        guard let photo = photo(for: idea) else { return nil }
        let image = photo.preparingThumbnail(of: CGSize(width: 400, height: 500)) ?? photo
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        thumbnailAssets.setObject(image, forKey: id, cost: cost)
        return image
    }

    @MainActor static func shareImage(for idea: Trastada) -> Image {
        if let photo = photo(for: idea) { return Image(uiImage: photo) }
        let renderer = ImageRenderer(content: Artwork(idea: idea, height: 640).frame(width: 640))
        return renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "photo")
    }
}

private struct ChristmasFarewell: View {
    let showLastIdea: () -> Void

    @State private var email = ""
    @State private var feedback: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .accessibilityHidden(true)
            Text("¡Feliz Navidad!")
                .systemHeading(.largeTitle)
            Text("Los elfos vuelven al Polo Norte. ¿Te avisamos cuando regresen el próximo diciembre?")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
            TextField("Correo electrónico", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .multilineTextAlignment(.leading)
                .padding(12)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                .onSubmit(submit)
            Button("Avísame el próximo diciembre", action: submit)
                .modifier(PrimaryIdeaControl(animated: false))
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let feedback {
                Text(feedback)
                    .font(.footnote)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button("Ver la última trastada", action: showLastIdea)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .padding(.vertical, 4)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(.vertical, 12)
        .frame(maxWidth: 380)
    }

    private func submit() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        let valid = parts.count == 2 && !parts[0].isEmpty
            && parts[1].split(separator: ".", omittingEmptySubsequences: false).count >= 2
            && parts[1].split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty }
            && !address.contains(where: \.isWhitespace)
        feedback = valid ? "El recordatorio por correo aún no está disponible."
            : "Revisa el correo electrónico e inténtalo de nuevo."
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
            .background(pink, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

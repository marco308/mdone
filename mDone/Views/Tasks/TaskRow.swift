import SwiftUI

struct TaskRow: View {
    @Environment(AppState.self) private var appState
    #if os(iOS)
    @Environment(FocusManager.self) private var focusManager
    #endif
    let task: VTask
    
    var readOnly: Bool = false
    var showsProgress: Bool = false
    
    @State private var showDetail = false
    @AppStorage("calmMode") private var calmMode = false
    @AppStorage("currentStallDays") private var stallDays = 7
    
    // LEEMOS EL ESTILO DESDE LOS AJUSTES (Por defecto arranca en el original)
    @AppStorage("taskRowStyle") private var taskRowStyle = TaskRowStyle.standard.rawValue

    private static let progressSteps = [0, 25, 50, 75, 100]

    #if os(iOS)
    private var isFocused: Bool {
        focusManager.focusedTaskId == task.id
    }
    #endif
    
    private var currentStyle: TaskRowStyle {
        TaskRowStyle(rawValue: taskRowStyle) ?? .standard
    }

    var body: some View {
        rowContent
        #if os(iOS)
        .contentShape(Rectangle())
        .onTapGesture { if !readOnly { showDetail = true } }
        // Adaptamos el fondo de la lista al estilo elegido
        .listRowBackground(currentStyle == .fullCard ? (isFocused ? Color.orange.opacity(0.08) : Color.clear) : (isFocused ? Color.orange.opacity(0.08) : nil))
        #endif
        .swipeActions(edge: .leading) {
            if !readOnly {
                #if os(iOS)
                if !task.done {
                    Button {
                        Task { await appState.postponeTask(task, byHours: 24) }
                    } label: {
                        Label("+24h", systemImage: "clock.arrow.circlepath")
                    }
                    .tint(.blue)
                }

                Button {
                    if isFocused {
                        focusManager.endFocus()
                    } else {
                        let projectName = appState.projects.first(where: { $0.id == task.projectId })?.title ?? "Inbox"
                        focusManager.switchFocus(task: task, projectName: projectName)
                    }
                } label: {
                    Label(isFocused ? "End Focus" : "Start Focus", systemImage: "scope")
                }
                .tint(.orange)
                #endif

                Button {
                    Task { await appState.toggleTaskDone(task) }
                } label: {
                    Label(task.done ? "Undo" : "Done", systemImage: task.done ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !readOnly {
                Button(role: .destructive) {
                    Task { await appState.deleteTask(task) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if !readOnly {
                if !task.done {
                    Menu {
                        ForEach(QuickSchedule.options()) { option in
                            Button {
                                guard let date = option.resolvedDate() else { return }
                                Task { await appState.rescheduleTask(task, to: date) }
                            } label: {
                                Label(option.label, systemImage: option.systemImage)
                            }
                        }
                    } label: {
                        Label("Schedule", systemImage: "calendar")
                    }
                }

                #if os(iOS)
                if isFocused {
                    Button {
                        focusManager.endFocus()
                    } label: {
                        Label("End Focus", systemImage: "scope")
                    }
                } else {
                    Button {
                        let projectName = appState.projects.first(where: { $0.id == task.projectId })?.title ?? "Inbox"
                        focusManager.switchFocus(task: task, projectName: projectName)
                    } label: {
                        Label("Start Focus", systemImage: "scope")
                    }
                }
                #endif

                Button {
                    Task { await appState.toggleCurrent(task) }
                } label: {
                    Label(
                        appState.isCurrent(task) ? "Remove from Current" : "Mark as Current",
                        systemImage: appState.isCurrent(task) ? "pin.slash" : "pin"
                    )
                }

                if appState.isCurrent(task) {
                    Menu {
                        ForEach(Self.progressSteps, id: \.self) { pct in
                            Button("\(pct)%") {
                                Task { await appState.setProgress(task, percent: Double(pct) / 100) }
                            }
                        }
                    } label: {
                        Label("Set Progress", systemImage: "chart.bar")
                    }
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showDetail) {
            TaskDetailSheet(task: task)
        }
        #endif
    }

    // EL SELECTOR MAESTRO DE ESTILOS
    @ViewBuilder
    private var rowContent: some View {
        switch currentStyle {
        case .standard:
            standardView
        case .colorCircle:
            colorCircleView
        case .fullCard:
            fullCardView
        }
    }
    
    // --------------------------------------------------------
    // 1. ESTILO ORIGINAL (STANDARD)
    // --------------------------------------------------------
    private var standardView: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor)
                .frame(width: 4, height: 36)
                .accessibilityHidden(true)

            Button {
                Task { await appState.toggleTaskDone(task) }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? .green : standardCheckboxColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(readOnly)
            .accessibilityLabel(task.done ? "Mark \(task.title) as incomplete" : "Mark \(task.title) as complete")
            .accessibilityAddTraits(.isToggle)

            taskDetailsColumn

            Spacer()

            if task.priority > 0 { PriorityBadge(priority: task.priorityLevel) }
            focusIcon
        }
        .padding(.vertical, 4)
        .opacity(task.done ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskAccessibilityLabel)
    }
    
    // --------------------------------------------------------
    // 2. ESTILO CIRCULO DE COLOR (Nuestra primera modificación)
    // --------------------------------------------------------
    private var colorCircleView: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor)
                .frame(width: 4, height: 36)
                .accessibilityHidden(true)

            Button {
                Task { await appState.toggleTaskDone(task) }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? ((task.hexColor != nil && task.hexColor != "") ? vikunjaColor.opacity(0.5) : .green) : vikunjaColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(readOnly)
            .accessibilityLabel(task.done ? "Mark \(task.title) as incomplete" : "Mark \(task.title) as complete")
            .accessibilityAddTraits(.isToggle)

            taskDetailsColumn

            Spacer()

            if task.priority > 0 { PriorityBadge(priority: task.priorityLevel) }
            focusIcon
        }
        .padding(.vertical, 4)
        .opacity(task.done ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskAccessibilityLabel)
    }
    
    // --------------------------------------------------------
    // 3. ESTILO FULL CARD (Tarjeta completa tipo Vikunja iOS)
    // --------------------------------------------------------
    private var fullCardView: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(vikunjaColor)
                .frame(width: 4, height: 40)
                .accessibilityHidden(true)

            taskDetailsColumn

            Spacer()

            if task.priority > 0 { PriorityBadge(priority: task.priorityLevel) }
            focusIcon

            Button {
                Task { await appState.toggleTaskDone(task) }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.done ? vikunjaColor.opacity(0.5) : vikunjaColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(readOnly)
            .accessibilityLabel(task.done ? "Mark \(task.title) as incomplete" : "Mark \(task.title) as complete")
            .accessibilityAddTraits(.isToggle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: vikunjaColor.opacity(0.25), location: 0.0),
                            .init(color: vikunjaColor.opacity(0.0), location: 0.7)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(vikunjaColor.opacity(0.3), lineWidth: 1)
        }
        #if os(macOS)
        .listRowBackground(Color.clear)
        #endif
        .padding(.vertical, 4)
        .opacity(task.done ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskAccessibilityLabel)
    }

    // --------------------------------------------------------
    // COLUMNA CENTRAL (Compartida por todos los estilos para no duplicar código)
    // --------------------------------------------------------
    private var taskDetailsColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.body)
                .fontWeight(currentStyle == .fullCard ? .medium : .regular)
                .strikethrough(task.done)
                .foregroundStyle(task.done ? .secondary : .primary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let dueDate = task.effectiveDueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        if task.hasSpecificTime {
                            Text(dueDate, format: .dateTime.month().day().year().hour().minute())
                        } else {
                            Text(dueDate, style: .date)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(task.isOverdue && !calmMode ? .red : .secondary)
                }

                if task.isRepeating {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                        if let desc = task.repeatDescription {
                            Text(desc)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let labels = task.labels, !labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(labels.prefix(3)) { label in
                            LabelChip(label: label)
                        }
                    }
                }
            }

            if showsProgress {
                CurrentProgressIndicator(percent: task.percentDone ?? 0, stalledDays: stalledDays)
            }
        }
    }
    
    // Icono de enfoque de iOS extraído para evitar repeticiones
    @ViewBuilder
    private var focusIcon: some View {
        #if os(iOS)
        if isFocused {
            Image(systemName: "scope")
                .font(.caption)
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
                .accessibilityLabel("Focused")
        }
        #endif
    }

    // --------------------------------------------------------
    // MÉTODOS DE SOPORTE DE ACCESIBILIDAD Y COLORES
    // --------------------------------------------------------
    private var taskAccessibilityLabel: String {
        var parts: [String] = []
        parts.append(task.title)
        if task.done { parts.append("completed") }
        if task.priority > 0 { parts.append("priority \(task.priorityLevel.label)") }
        if let dueDate = task.effectiveDueDate {
            if task.isOverdue { parts.append("overdue") }
            parts.append("due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        if task.isRepeating, let desc = task.repeatDescription { parts.append("repeats \(desc)") }
        if let labels = task.labels, !labels.isEmpty {
            let labelNames = labels.prefix(3).map(\.title).joined(separator: ", ")
            parts.append("labels: \(labelNames)")
        }
        return parts.joined(separator: ", ")
    }

    private var stalledDays: Int? {
        guard let updated = task.updated else { return nil }
        let days = Calendar.current.dateComponents([.day], from: updated, to: Date()).day ?? 0
        return days >= stallDays ? days : nil
    }

    private var priorityColor: Color {
        switch task.priorityLevel {
        case .critical, .urgent: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        case .none: .clear
        }
    }

    private var standardCheckboxColor: Color {
        task.priorityLevel == .none ? .gray : priorityColor
    }

    private var vikunjaColor: Color {
        if let hexString = task.hexColor, !hexString.isEmpty {
            return Color(hex: hexString)
        }
        return standardCheckboxColor
    }
}

struct CurrentProgressIndicator: View {
    let percent: Double
    let stalledDays: Int?

    private var percentText: String {
        "\(Int((percent * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: min(max(percent, 0), 1))
                .progressViewStyle(.linear)
                .tint(.accentColor)

            Text(percentText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if let stalledDays {
                Label("Idle \(stalledDays)d", systemImage: "zzz")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(Int((percent * 100).rounded())) percent complete"]
        if let stalledDays { parts.append("idle \(stalledDays) days") }
        return parts.joined(separator: ", ")
    }
}

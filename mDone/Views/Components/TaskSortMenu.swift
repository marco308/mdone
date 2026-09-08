import SwiftUI

/// The toolbar sort menu shared by the iOS and Mac task lists. Picks from
/// the orders the list supports (Manual only inside a project), flips the
/// direction when the current order is picked again, and stores the choice
/// through `AppState` so it sticks per list.
struct TaskSortMenu: View {
    @Environment(AppState.self) private var appState
    let scope: TaskSortScope

    private var preference: TaskSortPreference {
        appState.sortPreference(for: scope)
    }

    var body: some View {
        Menu {
            ForEach(scope.availableOrders) { order in
                Button {
                    appState.setSortPreference(preference.selecting(order), for: scope)
                } label: {
                    HStack {
                        Text(order.label)
                        if preference.order == order {
                            if order.supportsDirection {
                                Image(systemName: preference.ascending ? "chevron.up" : "chevron.down")
                            } else {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .help("Sort tasks")
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard preference.order.supportsDirection else {
            return String(localized: "Sort by \(preference.order.label)")
        }
        return preference.ascending
            ? String(localized: "Sort by \(preference.order.label), ascending")
            : String(localized: "Sort by \(preference.order.label), descending")
    }
}

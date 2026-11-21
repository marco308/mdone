import SwiftUI

/// A star that adds the task to Favorites or takes it out (#16). It reads the
/// task's live copy from `AppState`, since a detail view holds a snapshot
/// taken when it opened, and saves straight away rather than with the form.
struct TaskFavoriteButton: View {
    @Environment(AppState.self) private var appState
    let task: VTask

    private var isFavorite: Bool {
        (appState.tasks.first(where: { $0.id == task.id }) ?? task).isFavorite == true
    }

    var body: some View {
        Button {
            let favorite = !isFavorite
            Task { await appState.setFavorite(task, favorite) }
        } label: {
            Label(
                isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "star.fill" : "star"
            )
        }
        .tint(isFavorite ? .yellow : nil)
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }
}

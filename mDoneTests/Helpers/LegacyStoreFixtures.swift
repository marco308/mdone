import Foundation
import SwiftData

/// A store written before `CachedTask` had its current shape: `title` is typed
/// differently, which SwiftData cannot migrate automatically. Used to prove the
/// recovery path in issue #155 salvages offline work from a store the app's own
/// schema rejects.
///
/// SwiftData keys entities off the unqualified class name, so nesting this keeps
/// it out of the way of the app's `CachedTask` in Swift while still colliding
/// with it in the store.
enum LegacyStore {
    @Model
    final class CachedTask {
        @Attribute(.unique) var id: Int64
        var title: Int64

        init(id: Int64, title: Int64) {
            self.id = id
            self.title = title
        }
    }
}

import Foundation

/// A project together with its ordered sub-projects, forming one node in the
/// project hierarchy tree that the sidebar and project list render.
struct ProjectNode: Identifiable, Hashable {
    let project: Project
    var children: [ProjectNode]

    var id: Int64 {
        project.id
    }
}

/// One flattened row of the project tree: a project plus the metadata the list
/// needs to draw it (indent depth and whether it has collapsible children).
struct ProjectTreeRow: Identifiable {
    let project: Project
    let depth: Int
    let hasChildren: Bool

    var id: Int64 {
        project.id
    }
}

extension [Project] {
    /// Builds an ordered hierarchy from this flat list of projects.
    ///
    /// Vikunja returns parent and sub-projects intermixed in one flat list; this
    /// reconstructs the tree via `parentProjectId`. A project is treated as a
    /// root when its parent is `nil`, `0`, or simply not present in this list
    /// (e.g. the parent is archived or filtered out), so no project is ever lost.
    ///
    /// Every level is sorted by `position` ascending, falling back to a
    /// case-insensitive title compare (then `id`) so ordering stays stable when
    /// positions are equal or missing. Parent cycles are broken defensively:
    /// any project trapped in a cycle is surfaced as a root rather than dropped.
    func projectHierarchy() -> [ProjectNode] {
        let byId = Dictionary(uniqueKeysWithValues: map { ($0.id, $0) })
        var childrenByParent: [Int64: [Project]] = [:]
        var roots: [Project] = []
        for project in self {
            if let parentId = project.parentProjectId, parentId != 0, byId[parentId] != nil {
                childrenByParent[parentId, default: []].append(project)
            } else {
                roots.append(project)
            }
        }

        var visited: Set<Int64> = []
        func build(_ project: Project) -> ProjectNode {
            visited.insert(project.id)
            let children = (childrenByParent[project.id] ?? [])
                .filter { !visited.contains($0.id) } // cycle guard
                .sorted(by: Self.ordersBefore)
                .map(build)
            return ProjectNode(project: project, children: children)
        }

        var nodes = roots.sorted(by: Self.ordersBefore).map(build)

        // Any project trapped in a parent cycle was never reached from a root;
        // surface those as roots too so nothing disappears from the list. Skip
        // ones already emitted (a cycle member reached while building another).
        for project in sorted(by: Self.ordersBefore) where !visited.contains(project.id) {
            nodes.append(build(project))
        }
        return nodes
    }

    /// Orders two projects for display: by `position`, then title, then id.
    private static func ordersBefore(_ lhs: Project, _ rhs: Project) -> Bool {
        let lp = lhs.position ?? 0
        let rp = rhs.position ?? 0
        if lp != rp { return lp < rp }
        let byTitle = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if byTitle != .orderedSame { return byTitle == .orderedAscending }
        return lhs.id < rhs.id
    }
}

extension [ProjectNode] {
    /// Depth-first flatten of the tree into display rows, skipping the children
    /// of any node the caller reports as collapsed. `isExpanded` is queried per
    /// project id so callers can back it with persisted collapse state.
    func flattened(isExpanded: (Int64) -> Bool) -> [ProjectTreeRow] {
        var rows: [ProjectTreeRow] = []
        func walk(_ nodes: [ProjectNode], depth: Int) {
            for node in nodes {
                let hasChildren = !node.children.isEmpty
                rows.append(ProjectTreeRow(project: node.project, depth: depth, hasChildren: hasChildren))
                if hasChildren, isExpanded(node.project.id) {
                    walk(node.children, depth: depth + 1)
                }
            }
        }
        walk(self, depth: 0)
        return rows
    }
}

import XCTest
@testable import mDone

final class ProjectHierarchyTests: XCTestCase {
    // MARK: - projectHierarchy

    func testRootsSortedByPosition() {
        let projects = [
            Project(id: 3, title: "C", position: 30),
            Project(id: 1, title: "A", position: 10),
            Project(id: 2, title: "B", position: 20),
        ]
        let tree = projects.projectHierarchy()
        XCTAssertEqual(tree.map(\.project.id), [1, 2, 3])
        XCTAssertTrue(tree.allSatisfy(\.children.isEmpty))
    }

    func testSubProjectsNestUnderParentAndSortByPosition() {
        // Deliberately shuffled input, mirroring the issue's example.
        let projects = [
            Project(id: 22, title: "Subproject B2", position: 22, parentProjectId: 20),
            Project(id: 21, title: "Subproject B1", position: 21, parentProjectId: 20),
            Project(id: 10, title: "Project A", position: 10),
            Project(id: 30, title: "Project C", position: 30),
            Project(id: 20, title: "Project B", position: 20),
        ]
        let tree = projects.projectHierarchy()
        XCTAssertEqual(tree.map(\.project.id), [10, 20, 30])
        let projectB = tree.first { $0.project.id == 20 }
        XCTAssertEqual(projectB?.children.map(\.project.id), [21, 22])
    }

    func testDeepNestingPreservesOrder() {
        let projects = [
            Project(id: 1, title: "Root", position: 1),
            Project(id: 2, title: "Child", position: 1, parentProjectId: 1),
            Project(id: 3, title: "Grandchild", position: 1, parentProjectId: 2),
        ]
        let tree = projects.projectHierarchy()
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].children.first?.project.id, 2)
        XCTAssertEqual(tree[0].children.first?.children.first?.project.id, 3)
    }

    func testMissingParentPromotesChildToRoot() {
        // Parent 99 isn't in the list (e.g. archived/favorited): child must survive.
        let projects = [
            Project(id: 1, title: "A", position: 10),
            Project(id: 2, title: "Orphan", position: 20, parentProjectId: 99),
        ]
        let tree = projects.projectHierarchy()
        XCTAssertEqual(tree.map(\.project.id), [1, 2])
    }

    func testParentIdZeroTreatedAsRoot() {
        let projects = [
            Project(id: 1, title: "A", position: 10, parentProjectId: 0),
            Project(id: 2, title: "B", position: 20, parentProjectId: nil),
        ]
        let tree = projects.projectHierarchy()
        XCTAssertEqual(tree.map(\.project.id), [1, 2])
        XCTAssertTrue(tree.allSatisfy(\.children.isEmpty))
    }

    func testEqualPositionsFallBackToTitleThenId() {
        let projects = [
            Project(id: 2, title: "banana", position: 5),
            Project(id: 1, title: "Apple", position: 5),
            Project(id: 3, title: "apple", position: 5),
        ]
        let tree = projects.projectHierarchy()
        // "Apple"/"apple" tie on case-insensitive title, broken by id (1 before 3),
        // then "banana".
        XCTAssertEqual(tree.map(\.project.id), [1, 3, 2])
    }

    func testMissingPositionsTreatedAsZero() {
        let projects = [
            Project(id: 1, title: "Zeta"),
            Project(id: 2, title: "Alpha"),
        ]
        let tree = projects.projectHierarchy()
        // Both position nil (== 0) -> sorted by title: Alpha before Zeta.
        XCTAssertEqual(tree.map(\.project.id), [2, 1])
    }

    func testCycleDoesNotLoseProjectsOrRecurseForever() {
        // 1 -> 2 -> 1 mutual parenting. Neither is a natural root; both must still appear.
        let projects = [
            Project(id: 1, title: "One", position: 1, parentProjectId: 2),
            Project(id: 2, title: "Two", position: 2, parentProjectId: 1),
        ]
        let tree = projects.projectHierarchy()
        let allIds = flatten(tree).map(\.project.id).sorted()
        XCTAssertEqual(allIds, [1, 2])
    }

    func testEmptyListYieldsEmptyTree() {
        XCTAssertTrue([Project]().projectHierarchy().isEmpty)
    }

    // MARK: - flattened

    func testFlattenExpandedIncludesChildrenWithDepth() {
        let projects = [
            Project(id: 10, title: "A", position: 10),
            Project(id: 20, title: "B", position: 20),
            Project(id: 21, title: "B1", position: 21, parentProjectId: 20),
            Project(id: 22, title: "B2", position: 22, parentProjectId: 20),
            Project(id: 30, title: "C", position: 30),
        ]
        let rows = projects.projectHierarchy().flattened { _ in true }
        XCTAssertEqual(rows.map(\.project.id), [10, 20, 21, 22, 30])
        XCTAssertEqual(rows.map(\.depth), [0, 0, 1, 1, 0])
        XCTAssertEqual(rows.first { $0.project.id == 20 }?.hasChildren, true)
        XCTAssertEqual(rows.first { $0.project.id == 10 }?.hasChildren, false)
    }

    func testFlattenCollapsedHidesChildrenButKeepsParent() {
        let projects = [
            Project(id: 20, title: "B", position: 20),
            Project(id: 21, title: "B1", position: 21, parentProjectId: 20),
            Project(id: 30, title: "C", position: 30),
        ]
        // Collapse project 20.
        let rows = projects.projectHierarchy().flattened { $0 != 20 }
        XCTAssertEqual(rows.map(\.project.id), [20, 30])
        XCTAssertEqual(rows.first { $0.project.id == 20 }?.hasChildren, true)
    }

    // MARK: - descendantIDs

    func testDescendantIDsReturnsTransitiveChildren() {
        let projects = [
            Project(id: 1, title: "Root"),
            Project(id: 2, title: "Child", parentProjectId: 1),
            Project(id: 3, title: "Grandchild", parentProjectId: 2),
            Project(id: 4, title: "Sibling", parentProjectId: 1),
            Project(id: 9, title: "Unrelated"),
        ]
        XCTAssertEqual(projects.descendantIDs(of: 1), [2, 3, 4])
        XCTAssertEqual(projects.descendantIDs(of: 2), [3])
        XCTAssertEqual(projects.descendantIDs(of: 9), [])
    }

    func testDescendantIDsIsCycleSafe() {
        let projects = [
            Project(id: 1, title: "One", parentProjectId: 2),
            Project(id: 2, title: "Two", parentProjectId: 1),
        ]
        // Must terminate; each node's descendants exclude itself.
        XCTAssertEqual(projects.descendantIDs(of: 1), [2])
        XCTAssertEqual(projects.descendantIDs(of: 2), [1])
    }

    // MARK: - Helpers

    private func flatten(_ nodes: [ProjectNode]) -> [ProjectNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }
}

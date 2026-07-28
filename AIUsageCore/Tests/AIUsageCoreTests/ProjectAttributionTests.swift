//
//  ProjectAttributionTests.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import XCTest
@testable import AIUsageCore

final class ProjectAttributionTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aiusage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        ProjectResolver.resetCacheForTesting()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        ProjectResolver.resetCacheForTesting()
    }

    private func event(_ project: String, cost: Double, at ts: Date = Date()) -> UsageEvent {
        UsageEvent(key: UUID().uuidString, ts: ts, model: "claude-opus-5",
                   input: 10, output: 5, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0,
                   cost: cost, project: project)
    }

    // MARK: - Resolver

    func testResolvesSubdirectoryToRepositoryRoot() throws {
        let repo = tmp.appendingPathComponent("MyRepo", isDirectory: true)
        let nested = repo.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)

        XCTAssertEqual(ProjectResolver.root(for: nested.path), repo.path,
                       "un cwd dentro del repo se agrupa bajo la raíz del repo")
        XCTAssertEqual(ProjectResolver.root(for: repo.path), repo.path)
    }

    func testResolvesWorktreeWhereDotGitIsAFile() throws {
        // En worktrees y submódulos .git es un fichero que apunta al repo real.
        let repo = tmp.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try "gitdir: /elsewhere/.git/worktrees/wt\n"
            .write(to: repo.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        XCTAssertEqual(ProjectResolver.root(for: repo.path), repo.path)
    }

    func testFallsBackToCwdOutsideARepository() throws {
        let loose = tmp.appendingPathComponent("no-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)

        XCTAssertEqual(ProjectResolver.root(for: loose.path), loose.path)
    }

    func testEmptyCwdMeansNoProject() {
        XCTAssertEqual(ProjectResolver.root(for: ""), "")
        XCTAssertEqual(ProjectResolver.displayName(for: ""), L.t("no_project"))
    }

    func testDisplayNameIsTheLastPathComponent() {
        XCTAssertEqual(ProjectResolver.displayName(for: "/Users/x/iOS/AIUsage"), "AIUsage")
    }

    // MARK: - Aggregation

    func testGroupsCostByProjectSortedByCostDescending() {
        let snap = Aggregator.snapshot(from: [
            event("/repos/alpha", cost: 1.0),
            event("/repos/beta", cost: 5.0),
            event("/repos/alpha", cost: 2.0),
        ])

        XCTAssertEqual(snap.projects.map(\.path), ["/repos/beta", "/repos/alpha"])
        XCTAssertEqual(snap.projects[0].totals.cost, 5.0, accuracy: 0.0001)
        XCTAssertEqual(snap.projects[1].totals.cost, 3.0, accuracy: 0.0001)
        XCTAssertEqual(snap.projects[1].totals.messages, 2)
    }

    func testProjectTotalsMatchTheGlobalTotal() {
        let snap = Aggregator.snapshot(from: [
            event("/repos/alpha", cost: 1.5),
            event("", cost: 0.5),
        ])

        let summed = snap.projects.reduce(0) { $0 + $1.totals.cost }
        XCTAssertEqual(summed, snap.last30.cost, accuracy: 0.0001,
                       "la suma por proyecto debe cuadrar con el total de 30 días")
    }

    func testDisambiguatesProjectsThatShareAFolderName() {
        // Caso real: ~/AIUsage y ~/iOS/AIUsage son repos distintos.
        let snap = Aggregator.snapshot(from: [
            event("/Users/x/AIUsage", cost: 1.0),
            event("/Users/x/iOS/AIUsage", cost: 2.0),
            event("/Users/x/other", cost: 3.0),
        ])

        let names = Dictionary(uniqueKeysWithValues: snap.projects.map { ($0.path, $0.name) })
        XCTAssertEqual(names["/Users/x/AIUsage"], "x/AIUsage")
        XCTAssertEqual(names["/Users/x/iOS/AIUsage"], "iOS/AIUsage")
        XCTAssertEqual(names["/Users/x/other"], "other", "los que no colisionan no se ensanchan")
    }

    func testUsageWithoutAProjectIsKeptUnderAnEmptyPath() {
        let snap = Aggregator.snapshot(from: [event("", cost: 2.0)])

        XCTAssertEqual(snap.projects.count, 1)
        XCTAssertEqual(snap.projects[0].path, "")
        XCTAssertEqual(snap.projects[0].name, L.t("no_project"))
    }
}

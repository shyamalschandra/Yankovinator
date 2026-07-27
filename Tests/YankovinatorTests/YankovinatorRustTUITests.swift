// Copyright (C) 2025, Shyamal Suhana Chandra

import XCTest
@testable import Yankovinator

final class YankovinatorRustTUITests: XCTestCase {

    func testPathLookupFindsHomebrewOrLocalTUIWhenPresent() {
        let hits = YankovinatorRustTUI.pathLookup(executable: "yankovinator-tui")
        // Not required on CI without install — just ensure API is stable.
        for path in hits {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path), path)
            XCTAssertTrue(path.hasSuffix("yankovinator-tui"))
        }
    }

    func testLocateRespectsExplicitOverride() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-tui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fake = dir.appendingPathComponent("yankovinator-tui")
        try "#!/bin/sh\necho ok\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let previous = ProcessInfo.processInfo.environment["YANKOVINATOR_TUI_PATH"]
        setenv("YANKOVINATOR_TUI_PATH", fake.path, 1)
        defer {
            if let previous {
                setenv("YANKOVINATOR_TUI_PATH", previous, 1)
            } else {
                unsetenv("YANKOVINATOR_TUI_PATH")
            }
        }

        XCTAssertEqual(YankovinatorRustTUI.locateExecutable(), fake.path)
    }
}

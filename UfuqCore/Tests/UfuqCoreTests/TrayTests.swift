import XCTest
@testable import UfuqCore

final class TrayStoreTests: XCTestCase {
    private final class Disk: @unchecked Sendable { var data: Data? }

    private func store(_ disk: Disk) -> TrayStore {
        TrayStore(reader: { disk.data }, writer: { disk.data = $0 })
    }

    func testAddDedupRemoveClear() {
        let s = store(Disk())
        XCTAssertTrue(s.add(TrayItem(path: "/a/x.png")))
        XCTAssertFalse(s.add(TrayItem(path: "/a/x.png")))
        XCTAssertTrue(s.add(TrayItem(path: "/a/y.png")))
        XCTAssertEqual(s.items.map(\.name), ["x.png", "y.png"])
        s.remove(id: s.items[0].id)
        XCTAssertEqual(s.items.count, 1)
        s.clear()
        XCTAssertTrue(s.items.isEmpty)
    }

    func testReorder() {
        let s = store(Disk())
        for n in ["a", "b", "c", "d"] { s.add(TrayItem(path: "/\(n)")) }
        s.move(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(s.items.map(\.name), ["b", "c", "a", "d"])
        s.move(from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(s.items.map(\.name), ["d", "b", "c", "a"])
    }

    func testPersistRoundTrip() throws {
        let disk = Disk()
        let s = store(disk)
        s.add(TrayItem(path: "/a/x.png", size: 12, addedAt: Date(timeIntervalSince1970: 1_700_000_000), kind: .file))
        s.add(TrayItem(path: "/a/dir", addedAt: Date(timeIntervalSince1970: 1_700_000_100), kind: .folder))
        s.pin(folder: "/Users/me/Desktop")
        XCTAssertFalse(s.pin(folder: "/Users/me/Desktop"))
        try s.save()

        let loaded = store(disk)
        loaded.load()
        XCTAssertEqual(loaded.items, s.items)
        XCTAssertEqual(loaded.pinnedFolders, ["/Users/me/Desktop"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(disk.data)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
    }

    func testOldVersionAndGarbageTolerated() {
        let disk = Disk()
        disk.data = Data(#"{"items":[{"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","path":"/a/x","name":"x","addedAt":"2024-01-01T00:00:00Z","kind":"file"}]}"#.utf8)
        let s = store(disk)
        s.load()
        XCTAssertEqual(s.items.count, 1)
        XCTAssertTrue(s.pinnedFolders.isEmpty)

        disk.data = Data("garbage".utf8)
        let g = store(disk)
        g.load()
        XCTAssertTrue(g.items.isEmpty)
        // An unreadable file is never overwritten.
        g.add(TrayItem(path: "/a/y"))
        XCTAssertThrowsError(try g.save())
        XCTAssertEqual(disk.data, Data("garbage".utf8))

        disk.data = Data(#"{"version":99,"items":[]}"#.utf8)
        let n = store(disk)
        n.load()
        XCTAssertThrowsError(try n.save())
    }
}

final class TrayActionsTests: XCTestCase {
    func testZipUniqueName() {
        let existing: Set<String> = ["/d/Archive.zip", "/d/Archive 2.zip"]
        let actions = TrayActions(fileExists: { existing.contains($0) })
        let cmd = actions.zip("/d/Archive")
        XCTAssertEqual(cmd.executable, "/usr/bin/ditto")
        XCTAssertEqual(cmd.arguments, ["-c", "-k", "--sequesterRsrc", "--keepParent", "/d/Archive", "/d/Archive 3.zip"])
        XCTAssertEqual(cmd.output, "/d/Archive 3.zip")
        XCTAssertEqual(TrayActions(fileExists: { _ in false }).zip("/d/Photos").output, "/d/Photos.zip")
        XCTAssertEqual(actions.archivePath(in: "/d"), "/d/Archive 3.zip")
    }

    func testConvertImage() {
        let actions = TrayActions(fileExists: { $0 == "/d/pic.jpg" })
        let cmd = actions.convertImage("/d/pic.png", to: .jpeg)
        XCTAssertEqual(cmd.executable, "/usr/bin/sips")
        XCTAssertEqual(cmd.arguments, ["-s", "format", "jpeg", "/d/pic.png", "--out", "/d/pic 2.jpg"])
        XCTAssertEqual(TrayActions(fileExists: { _ in false }).convertImage("/d/a.heic", to: .png).output, "/d/a.png")
    }

    func testRenameValidation() {
        let actions = TrayActions(fileExists: { $0 == "/d/taken.txt" })
        XCTAssertEqual(actions.rename("/d/a.txt", to: "b.txt"), .success("/d/b.txt"))
        XCTAssertEqual(actions.rename("/d/a.txt", to: ""), .failure(.emptyName))
        XCTAssertEqual(actions.rename("/d/a.txt", to: "  "), .failure(.emptyName))
        XCTAssertEqual(actions.rename("/d/a.txt", to: "x/y"), .failure(.invalidCharacter("/")))
        XCTAssertEqual(actions.rename("/d/a.txt", to: ":x"), .failure(.leadingColon))
        XCTAssertEqual(actions.rename("/d/a.txt", to: String(repeating: "a", count: 256)), .failure(.tooLong))
        XCTAssertEqual(actions.rename("/d/a.txt", to: String(repeating: "é", count: 128)), .failure(.tooLong))
        XCTAssertEqual(actions.rename("/d/a.txt", to: "a.txt"), .failure(.unchanged))
        XCTAssertEqual(actions.rename("/d/a.txt", to: "taken.txt"), .failure(.destinationExists("/d/taken.txt")))
        XCTAssertEqual(actions.rename("/d/a.txt", to: "a:b.txt"), .success("/d/a:b.txt"))
    }
}

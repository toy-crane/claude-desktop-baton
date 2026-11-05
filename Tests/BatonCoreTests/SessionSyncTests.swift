import Foundation
import Testing
@testable import BatonCore

private let A = SyncFixture.folderA
private let B = SyncFixture.folderB
private let s1 = "11111111-1111-4111-8111-111111111111"
private let s2 = "22222222-2222-4222-8222-222222222222"
private let s3 = "33333333-3333-4333-8333-333333333333"

@Suite("Session sync at switch time")
struct SessionSyncTests {

    // AC2
    @Test func activeSessionIsCopiedToEveryOtherFolderRegardlessOfAge() throws {
        let f = try SyncFixture()
        let original = try f.writeRecord(A, s1, daysAgo: 200, archived: false)

        let report = f.sync()

        #expect(f.read(B, s1) == original)
        #expect(report.created == 1)
    }

    // AC2
    @Test func archivedSessionActiveWithinThirtyDaysIsCopied() throws {
        let f = try SyncFixture()
        try f.writeRecord(A, s1, daysAgo: 29, archived: true)

        f.sync()

        #expect(f.read(B, s1) != nil)
    }

    // AC2
    @Test func archivedSessionOlderThanThirtyDaysIsNotCopied() throws {
        let f = try SyncFixture()
        try f.writeRecord(A, s1, daysAgo: 31, archived: true)

        let report = f.sync()

        #expect(f.read(B, s1) == nil)
        #expect(report.created == 0)
    }

    // AC3
    @Test func copyWithLatestActivityReplacesOlderCopies() throws {
        let f = try SyncFixture()
        try f.writeRecord(A, s1, daysAgo: 3, title: "older")
        try f.writeRecord(B, s1, daysAgo: 1, title: "newer")

        let report = f.sync()

        #expect(f.title(A, s1) == "newer")
        #expect(f.title(B, s1) == "newer")
        #expect(report.updated == 1)
    }

    // AC3
    @Test func equalActivityIsSettledByNewestModificationTime() throws {
        let f = try SyncFixture()
        try f.writeRecord(A, s1, daysAgo: 2, title: "saved later", modifiedDaysAgo: 1)
        try f.writeRecord(B, s1, daysAgo: 2, title: "saved earlier", modifiedDaysAgo: 2)

        f.sync()

        #expect(f.title(B, s1) == "saved later")
    }

    // AC4
    @Test func sessionDeletedUnderOneAccountIsMovedToTrashEverywhereElse() throws {
        let f = try SyncFixture()
        try f.markDeleted(A, s1)
        try f.writeRecord(B, s1, daysAgo: 1)

        let report = f.sync()

        #expect(f.read(B, s1) == nil)
        #expect(f.read(A, s1) == nil)
        #expect(f.trashedCopies(of: s1).count == 1)
        #expect(report.trashed == 1)
    }

    // AC4: a deletion applies whatever the session's age, and the session is never copied back.
    @Test func deletedOldArchivedSessionIsTrashedAndNotRecreated() throws {
        let f = try SyncFixture(folders: [A, B, "cccccccc-0000-4000-8000-000000000003/\(SyncFixture.org)"])
        let C = "cccccccc-0000-4000-8000-000000000003/\(SyncFixture.org)"
        try f.markDeleted(A, s1)
        try f.writeRecord(B, s1, daysAgo: 90, archived: true)

        f.sync()

        #expect(f.read(B, s1) == nil)
        #expect(f.read(C, s1) == nil)
        #expect(f.trashedCopies(of: s1).count == 1)
    }

    // AC5
    @Test func recordMissingWithoutMarkerIsFilledBackFromAnotherFolder() throws {
        let f = try SyncFixture()
        let original = try f.writeRecord(A, s1, daysAgo: 1)
        try f.writeRecord(B, s2, daysAgo: 1)

        f.sync()

        #expect(f.read(B, s1) == original)
        #expect(f.read(A, s2) != nil)
    }

    // Safety: copies land as complete ordinary files with the winner's time and private mode.
    @Test func copiesKeepTheWinnersModificationTimeAndPrivateMode() throws {
        let f = try SyncFixture()
        try f.writeRecord(A, s1, daysAgo: 1, modifiedDaysAgo: 4)

        f.sync()

        #expect(f.modified(B, s1) == f.modified(A, s1))
        #expect(f.mode(B, s1) == 0o600)
        #expect(f.files(B) == ["local_\(s1).json"])
    }

    // Safety: records Claude would not load, or that may be someone else's, are neither sources nor targets.
    @Test func unreadableRecordsAreLeftAlone() throws {
        let f = try SyncFixture()
        try f.writeRaw(A, name: "local_\(s1).json", "{not json")
        try f.writeRecord(B, s1, daysAgo: 1, title: "good")
        try f.writeRaw(A, name: "local_\(s2).json", #"{"sessionId":"local_\#(s3)","lastActivityAt":1,"isArchived":false}"#)
        try f.writeRecord(B, s3, daysAgo: 1)
        try f.writeRecord(A, s3, daysAgo: 2)

        let report = f.sync()

        #expect(String(decoding: f.read(A, s1) ?? Data(), as: UTF8.self) == "{not json")
        #expect(f.read(B, s2) == nil)
        #expect(!report.notes.isEmpty)
    }

    // Safety: a symlinked record is never followed or replaced.
    @Test func linkedRecordIsLeftAlone() throws {
        let f = try SyncFixture()
        let outside = f.root.appendingPathComponent("outside.json")
        try Data(#"{"sessionId":"local_\#(s1)","lastActivityAt":1,"isArchived":false}"#.utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: f.recordURL(A, s1), withDestinationURL: outside)
        try f.writeRecord(B, s1, daysAgo: 1, title: "newer")

        f.sync()

        let attributes = try FileManager.default.attributesOfItem(atPath: f.recordURL(A, s1).path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(String(decoding: try Data(contentsOf: outside), as: UTF8.self).contains("\"lastActivityAt\":1"))
    }

    // Safety: an unfamiliar layout stops the pass before any change.
    @Test func mostlyUnreadableRecordsStopThePassWithoutChanges() throws {
        let f = try SyncFixture()
        try f.writeRaw(A, name: "local_\(s1).json", "garbage")
        try f.writeRaw(A, name: "local_\(s2).json", "garbage")
        try f.writeRecord(B, s3, daysAgo: 1)

        let report = f.sync()

        #expect(report.aborted != nil)
        #expect(f.read(A, s3) == nil)
    }

    // Safety: Claude's archived-session hint keeps matching the folder's records when it exists.
    @Test func archivedHintIsUpdatedOnlyWhereItAlreadyExists() throws {
        let f = try SyncFixture()
        try f.writeRecord(A, s1, daysAgo: 1, archived: true)
        try f.writeRecord(A, s2, daysAgo: 1, archived: false)
        try f.writeRaw(B, name: "archived-sessions.idx", #"{"v":1,"archived":[]}"#)

        f.sync()

        #expect(f.archivedHint(B) == ["local_\(s1)"])
        #expect(f.archivedHint(A) == nil)
    }

    // Safety (bug found in review of the first implementation): a trashed archived session leaves the hint too.
    @Test func trashedArchivedSessionIsRemovedFromTheArchivedHint() throws {
        let f = try SyncFixture()
        try f.markDeleted(A, s1)
        try f.writeRecord(B, s1, daysAgo: 1, archived: true)
        try f.writeRaw(B, name: "archived-sessions.idx", #"{"v":1,"archived":["local_\#(s1)"]}"#)

        f.sync()

        #expect(f.archivedHint(B) == [])
    }

    // Runtime evidence on real data: a preview counts what a switch would change and changes nothing.
    @Test func previewCountsChangesWithoutTouchingAnyFolder() throws {
        let f = try SyncFixture()
        try f.writeRecord(A, s1, daysAgo: 1)
        try f.writeRecord(B, s2, daysAgo: 1, title: "older")
        try f.writeRecord(A, s2, daysAgo: 0.5, title: "newer")
        try f.markDeleted(A, s3)
        try f.writeRecord(B, s3, daysAgo: 1)

        let report = SessionSync.run(f.locations, now: f.now, preview: true)

        #expect(report.created == 1 && report.updated == 1 && report.trashed == 1)
        #expect(f.read(B, s1) == nil)
        #expect(f.title(B, s2) == "older")
        #expect(f.read(B, s3) != nil)
        #expect(!FileManager.default.fileExists(atPath: f.locations.stagingDir.path))
    }

    // Safety: a second pass over an already matching layout changes nothing.
    @Test func matchingFoldersNeedNoChanges() throws {
        let f = try SyncFixture()
        try f.writeRecord(A, s1, daysAgo: 1)
        f.sync()

        let report = f.sync()

        #expect(report.created == 0 && report.updated == 0 && report.trashed == 0)
    }
}

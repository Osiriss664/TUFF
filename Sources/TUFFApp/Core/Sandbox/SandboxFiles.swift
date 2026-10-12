#if os(macOS)
import Foundation

/// Reads the chosen search folders through the files sandbox: it lists the
/// files and turns them into passages (`/v1/files/list`, `/v1/files/passages`),
/// and the app gets only a list of paths and plain text. The app still
/// decides what is indexed: every path, size and stamp the sandbox reports is
/// checked here, and the file is looked at on the Mac again before and after
/// it is read (see `AppLocalIndexer.update`).
struct SandboxFileReader: AppLocalFileReading {
    /// A page of the file list holds at most this many entries.
    static let listPageSize = 1_000
    /// The most pages one folder's list may take (20,000 files at 1,000 a page
    /// with room to spare for pages the walk filled only partly).
    static let maximumListPages = 200
    /// Passage text the server may send for one passage.
    static let maximumPassageCharacters = 2_600
    static let maximumPassages = 5_000
    /// 5,000 passages of 2,500 characters, spelled in JSON.
    static let passageAnswerLimit = 48 * 1_024 * 1_024
    static let listAnswerLimit = 2 * 1_024 * 1_024
    static let maximumPathCharacters = 1_024

    let access: SandboxWebAccess

    // MARK: Requests and answers

    private struct ListRequest: Encodable {
        let folder: String
        let cursor: String?
        let limit: Int
    }

    private struct ListAnswer: Decodable {
        struct Entry: Decodable {
            let path: String
            let size: Int
            let mtime: Double
        }
        let entries: [Entry]
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case entries
            case nextCursor = "next_cursor"
        }
    }

    private struct PassagesRequest: Encodable {
        let folder: String
        let path: String
    }

    private struct PassagesAnswer: Decodable {
        struct Passage: Decodable {
            let page: Int?
            let lineStart: Int?
            let lineEnd: Int?
            let text: String

            enum CodingKeys: String, CodingKey {
                case page, text
                case lineStart = "line_start"
                case lineEnd = "line_end"
            }
        }
        let size: Int
        let mtime: Double
        let passages: [Passage]
    }

    // MARK: Scan

    func scan(_ folder: AppSearchFolder, limits: AppLocalIndexLimits,
              previouslyIndexed: Bool) async throws
        -> (files: [AppLocalIndexer.FoundFile], reachedLimit: Bool) {
        guard SandboxFolderMount.isMountable(folder.path) else {
            throw AppLocalSearchError.index(SandboxFilesFailure.unmountable)
        }
        guard !SandboxFolderMount.isTooBroad(folder.path) else {
            throw AppLocalSearchError.index(SandboxFilesFailure.tooBroad)
        }
        guard let canonicalRoot = canonicalPath(folder.path) else {
            throw AppLocalSearchError.index("The folder could not be read.")
        }
        let rootPath = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        let id = folder.id.uuidString.lowercased()
        var files: [AppLocalIndexer.FoundFile] = []
        var seen = Set<String>()
        var packages: [String: Bool] = [:]
        var cursor: String?
        // What the Mac itself sees in the folder tells an empty answer that
        // is true from one that macOS caused by refusing the sandbox access.
        func emptyAnswerIsSuspicious() -> Bool {
            Self.macSeesIndexableFiles(in: canonicalRoot)
                || (previouslyIndexed && Self.macSeesAnyEntry(in: canonicalRoot))
        }
        for _ in 0..<Self.maximumListPages {
            try Task.checkCancellation()
            let request = ListRequest(folder: id, cursor: cursor, limit: Self.listPageSize)
            let data: Data
            do {
                data = try await access.withClient(confirmFirst: false) { client in
                    try await client.post("/v1/files/list", body: request,
                                          answerLimit: Self.listAnswerLimit, timeout: 60)
                }
            } catch {
                throw SandboxFilesFailure.map(error)
            }
            let answer: ListAnswer
            do {
                answer = try JSONDecoder().decode(ListAnswer.self, from: data)
            } catch {
                throw SandboxFilesFailure.malformed
            }
            guard answer.entries.count <= Self.listPageSize else { throw SandboxFilesFailure.malformed }
            for entry in answer.entries {
                guard let found = Self.accept(entry.path, size: entry.size, mtime: entry.mtime,
                                              rootPath: rootPath, limits: limits, packages: &packages),
                      seen.insert(found.path).inserted else { continue }
                files.append(found)
                if files.count >= limits.maximumFilesPerFolder { return (files, true) }
            }
            guard let next = answer.nextCursor else {
                if files.isEmpty, emptyAnswerIsSuspicious() {
                    throw AppLocalSearchError.index(SandboxError.folderAccessDenied.description)
                }
                return (files, false)
            }
            // The walk must move forward, or a faulty sandbox would keep it
            // here for ever.
            guard next != cursor, Self.isValidCursor(next) else { throw SandboxFilesFailure.malformed }
            cursor = next
        }
        // A folder with more entries than the pages allow (many pictures or
        // package contents the app does not index): index what was found,
        // as with the file limit.
        return (files, true)
    }

    /// The app's own rules for what to index, applied to what the sandbox
    /// listed: the same ones `AppLocalIndexer.scan` applies, so a sandbox that
    /// lists more (or other) files than it should cannot widen what is read.
    static func accept(_ relative: String, size: Int, mtime: Double, rootPath: String,
                       limits: AppLocalIndexLimits,
                       packages: inout [String: Bool]) -> AppLocalIndexer.FoundFile? {
        guard isValidRelativePath(relative), size >= 0, mtime.isFinite else { return nil }
        let components = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // The folder's own children are level 1; the scan walks directories
        // down to `maximumDepth`, so their files sit one level deeper.
        guard components.count <= limits.maximumDepth + 1 else { return nil }
        guard components.allSatisfy({ !$0.hasPrefix(".") }) else { return nil }
        let directories = components.dropLast()
        guard !directories.contains(where: { skippedDirectoryNames.contains($0) }) else { return nil }
        let path = rootPath + relative
        let url = URL(fileURLWithPath: path)
        guard DocumentTextExtractor.canExtract(from: url), !url.pathExtension.isEmpty
                || url.lastPathComponent.lowercased().hasPrefix("readme") else { return nil }
        // Packages (such as .app or .pages), directories the system marks
        // hidden and links are not entered by the app's own scan; the
        // sandbox does not know about them. Each directory is looked at on
        // the Mac, once.
        var prefix = String(rootPath.dropLast())
        for directory in directories {
            prefix += "/" + directory
            let blocked: Bool
            if let known = packages[prefix] {
                blocked = known
            } else {
                let values = try? URL(fileURLWithPath: prefix, isDirectory: true)
                    .resourceValues(forKeys: [.isPackageKey, .isHiddenKey, .isSymbolicLinkKey])
                blocked = values?.isPackage == true || values?.isHidden == true
                    || values?.isSymbolicLink == true
                packages[prefix] = blocked
            }
            if blocked { return nil }
        }
        if (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true { return nil }
        return AppLocalIndexer.FoundFile(
            path: path, size: size,
            mtime: Date(timeIntervalSince1970: mtime).timeIntervalSinceReferenceDate)
    }

    /// A path relative to the folder, as the server takes and gives it: not
    /// empty, not long, no empty, `.` or `..` part, no control character.
    static func isValidRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.unicodeScalars.count <= maximumPathCharacters,
              !path.hasPrefix("/") else { return false }
        guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// A cursor is the last path the sandbox looked at, listed or not, so
    /// it may be a name the app would never accept as a file (a hidden or
    /// oddly named one). It is sent back unchanged; it only has to be a
    /// plausible relative path.
    static func isValidCursor(_ cursor: String) -> Bool {
        guard !cursor.isEmpty, cursor.unicodeScalars.count <= 8_192, !cursor.hasPrefix("/"),
              !cursor.unicodeScalars.contains(where: { $0.value == 0 }) else { return false }
        return !cursor.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Whether the folder has any entry that is not hidden.
    static func macSeesAnyEntry(in root: String) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).contains { !$0.hasPrefix(".") }
    }

    /// Whether the Mac itself sees a file the app would index in the folder
    /// or one level below. If the sandbox listed nothing while this is so,
    /// macOS most likely blocked the sandbox from reading the folder.
    static func macSeesIndexableFiles(in root: String) -> Bool {
        let manager = FileManager.default
        func indexable(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, values.isRegularFile == true else { return false }
            return DocumentTextExtractor.canExtract(from: url) && (!url.pathExtension.isEmpty
                || url.lastPathComponent.lowercased().hasPrefix("readme"))
        }
        let top = ((try? manager.contentsOfDirectory(atPath: root)) ?? []).filter { !$0.hasPrefix(".") }
        for name in top.prefix(200) {
            let url = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(name)
            if indexable(url) { return true }
            guard !skippedDirectoryNames.contains(name),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let inner = ((try? manager.contentsOfDirectory(atPath: url.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
            if inner.prefix(50).contains(where: { indexable(url.appendingPathComponent($0)) }) { return true }
        }
        return false
    }

    // MARK: Passages

    func passages(for file: AppLocalIndexer.FoundFile, in folder: AppSearchFolder,
                  limits: AppLocalIndexLimits) async throws -> [(Int?, Int?, Int?, String)] {
        let url = URL(fileURLWithPath: file.path)
        let isPDF = url.pathExtension.lowercased() == "pdf"
        if file.size > (isPDF ? limits.maximumPDFBytes : limits.maximumTextFileBytes) {
            throw AppLocalFileSkip(reason: "larger than the indexing limit")
        }
        guard let canonicalRoot = canonicalPath(folder.path) else {
            throw AppLocalSearchError.index("The folder could not be read.")
        }
        let rootPath = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        guard file.path.hasPrefix(rootPath) else {
            throw AppLocalFileSkip(reason: "outside the folder")
        }
        let relative = String(file.path.dropFirst(rootPath.count))
        guard Self.isValidRelativePath(relative) else {
            throw AppLocalFileSkip(reason: "the path cannot be sent to the sandbox")
        }
        let request = PassagesRequest(folder: folder.id.uuidString.lowercased(), path: relative)
        let data: Data
        do {
            data = try await access.withClient(confirmFirst: false) { client in
                try await client.post("/v1/files/passages", body: request,
                                      answerLimit: Self.passageAnswerLimit,
                                      timeout: isPDF ? 150 : 40)
            }
        } catch SandboxClientError.remote(_, let code, _) where code == "changed_while_reading" {
            throw AppLocalFileChanged()
        } catch SandboxClientError.remote(_, let code, let message)
                    where SandboxFilesFailure.skipCodes.contains(code) {
            throw AppLocalFileSkip(reason: SandboxFilesFailure.skipReason(code: code, message: message))
        } catch {
            throw SandboxFilesFailure.map(error)
        }
        let answer: PassagesAnswer
        do {
            answer = try JSONDecoder().decode(PassagesAnswer.self, from: data)
        } catch {
            throw SandboxFilesFailure.malformed
        }
        // The file the sandbox read must be the one the app saw.
        guard answer.size == file.size,
              abs(Date(timeIntervalSince1970: answer.mtime).timeIntervalSinceReferenceDate - file.mtime) < 0.001
        else { throw AppLocalFileChanged() }
        guard answer.passages.count <= Self.maximumPassages else { throw SandboxFilesFailure.malformed }
        var passages: [(Int?, Int?, Int?, String)] = []
        for passage in answer.passages {
            if isPDF {
                guard let page = passage.page, (1...max(1, limits.maximumPDFPages)).contains(page),
                      passage.lineStart == nil, passage.lineEnd == nil else {
                    throw SandboxFilesFailure.malformed
                }
            } else {
                guard passage.page == nil, let start = passage.lineStart, let end = passage.lineEnd,
                      start >= 1, start <= end, end <= limits.maximumTextFileBytes + 1 else {
                    throw SandboxFilesFailure.malformed
                }
            }
            // The text is data from a program that read untrusted files:
            // control and invisible characters go before it can be indexed.
            let text = SandboxWebText.clean(passage.text, limit: Self.maximumPassageCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            passages.append((passage.page, passage.lineStart, passage.lineEnd, text))
        }
        guard !passages.isEmpty else { throw AppLocalFileSkip(reason: "it has no text") }
        return passages
    }
}

/// How the files sandbox's failures read in the folder list of the settings.
enum SandboxFilesFailure {
    static let malformed = AppLocalSearchError.index("The file sandbox's answer was not what was expected.")
    static let unmountable = "This folder's path has a comma or a line break in it, which the container tool "
        + "cannot mount. Rename the folder to use it with the file sandbox."
    static let tooBroad = "Your home folder, or a folder that contains it, is too broad for the file sandbox: "
        + "it would give the sandbox your keys and app data. Add the folders inside it instead."

    /// Codes of the sandbox's own refusals that mean "this one file cannot be
    /// indexed". Anything else stops the update of the folder.
    static let skipCodes: Set<String> = [
        "oversized", "unreadable", "empty", "too_many_passages", "not_a_file", "not_found",
        "invalid_path", "timed_out",
    ]

    static func skipReason(code: String, message: String) -> String {
        switch code {
        case "oversized": "larger than the indexing limit"
        case "empty": "it has no text"
        case "timed_out": "reading it took too long"
        case "too_many_passages": "it has too much text"
        case "not_a_file": "not a regular file"
        case "not_found": "the file is gone"
        // The wording of anything else came from the sandbox; it is not shown.
        default: "the sandbox could not read it (\(SandboxText.oneLine(code, limit: 30)))"
        }
    }

    /// Errors as the settings and the index show them: the app's own search
    /// errors keep their text, everything else gets a sentence.
    static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if error is AppLocalSearchError || error is SandboxError { return error }
        if case SandboxClientError.remote(_, "not_found", _) = error {
            return AppLocalSearchError.index(
                "The file sandbox does not have this folder. It was probably added after the sandbox started, "
                    + "or macOS did not let the sandbox open it (see System Settings > Privacy & Security > "
                    + "Files and Folders for \u{201C}container-runtime-linux\u{201D}).")
        }
        if let error = error as? SandboxClientError {
            return AppLocalSearchError.index(sentence(error.description))
        }
        return AppLocalSearchError.index(sentence(SandboxText.oneLine(error.localizedDescription)))
    }

    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".!?".contains(last) else { return text }
        return text + "."
    }
}

/// The files sandbox as the rest of the app uses it: one controller of the
/// `files` profile, started with the folders to read mounted, and started
/// again when the folders change.
@MainActor
final class SandboxFilesService {
    let controller: SandboxController
    let access: SandboxWebAccess
    private var mounted: [SandboxFolderMount] = []

    init(controller: SandboxController, access: SandboxWebAccess) {
        self.controller = controller
        self.access = access
    }

    /// The folders that can be mounted: they exist, resolve to a path with no
    /// comma or line break, and are listed once. Sorted by id.
    static func mounts(for folders: [AppSearchFolder]) -> [SandboxFolderMount] {
        var seen = Set<String>()
        let mounts = folders.compactMap { folder -> SandboxFolderMount? in
            guard let path = canonicalPath(folder.path), path != "/",
                  SandboxFolderMount.isMountable(path),
                  !SandboxFolderMount.isTooBroad(path) else { return nil }
            let id = folder.id.uuidString.lowercased()
            return seen.insert(id).inserted ? SandboxFolderMount(id: id, path: path) : nil
        }.sorted { $0.id < $1.id }
        return Array(mounts.prefix(SandboxFolderMount.maximumCount))
    }

    /// Makes the sandbox run with exactly these folders mounted: nothing is
    /// done when it already does, otherwise it is stopped and started again.
    /// Throws what the person should read when it cannot be. With no folder
    /// that can be mounted it only makes sure no sandbox runs.
    func ensureRunning(for folders: [AppSearchFolder]) async throws {
        let desired = Self.mounts(for: folders)
        if desired.isEmpty {
            await controller.stop()
            mounted = []
            return
        }
        if controller.state == .ready, mounted == desired, controller.activeMountIDs == desired.map(\.id) {
            return
        }
        // An indexing run that was cancelled meanwhile (the person turned the
        // setting off, or changed the folders) must not bring the VM back.
        try Task.checkCancellation()
        if controller.state.isBusy, mounted == desired {
            // A start for these folders is under way: wait for it.
            await controller.start()
        } else {
            await controller.stop()
            try Task.checkCancellation()
            controller.folderMounts = desired
            mounted = desired
            await controller.start()
        }
        try Task.checkCancellation()
        switch controller.state {
        case .ready: return
        case .failed(let message): throw AppLocalSearchError.index(message)
        default: throw SandboxError.notReady
        }
    }

    func stop() async {
        await controller.stop()
        mounted = []
    }
}
#endif

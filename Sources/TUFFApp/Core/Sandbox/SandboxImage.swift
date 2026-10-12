#if os(macOS)
import Foundation

/// The sandbox image TUFF will run, named by the digest of its content. The
/// digest is part of the app, so a changed image on the registry is never
/// run: the pull asks for exactly this content, and the result is checked
/// again after the pull.
struct SandboxImagePin: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// Pulled from a registry as `reference@digest`.
        case registry
        /// Already in the local image store under `reference`, such as the
        /// image a developer built from `Sandbox/`. It is never pulled.
        case local
    }

    let reference: String
    let digest: String
    let source: Source

    /// What `container run` is given.
    var runReference: String {
        source == .registry ? "\(reference)@\(digest)" : reference
    }

    /// The digest is `sha256:` and 64 lowercase hexadecimal digits.
    static func isWellFormed(_ digest: String) -> Bool {
        digest.wholeMatch(of: #/sha256:[0-9a-f]{64}/#) != nil
    }

    static let placeholderDigest = "sha256:" + String(repeating: "0", count: 64)

    /// True until the first image has been published and its digest put here.
    var isPlaceholder: Bool { digest == Self.placeholderDigest }

    /// The image this version of TUFF runs. The maintainer's workflow
    /// (`.github/workflows/sandbox-image.yml`) publishes it; its digest
    /// replaces the placeholder in a small follow-up change, and until then
    /// the sandbox says that no image has been published.
    static let release = SandboxImagePin(
        reference: "ghcr.io/rexmhall09/tuff-sandbox", digest: placeholderDigest, source: .registry)
}

/// Makes sure the pinned image is in the local image store.
struct SandboxImageProvisioner: Sendable {
    let tool: ContainerTool

    /// Pulls the image unless it is already there with the pinned digest,
    /// then checks the digest. `progress` gets a short sentence before a
    /// download, which can take a while on a first start.
    func ensure(_ pin: SandboxImagePin, progress: @Sendable (String) -> Void) async throws {
        guard SandboxImagePin.isWellFormed(pin.digest), !pin.isPlaceholder else {
            throw SandboxError.imageNotPublished
        }
        if let present = await tool.inspectImage(pin.runReference),
           Self.digests(in: present).contains(pin.digest) {
            return
        }
        guard pin.source == .registry else {
            throw SandboxError.digestMismatch(expected: pin.digest, found: nil)
        }
        progress("Downloading the sandbox image")
        try await tool.pullImage(pin.runReference)
        guard let pulled = await tool.inspectImage(pin.runReference) else {
            throw SandboxError.digestMismatch(expected: pin.digest, found: nil)
        }
        let found = Self.digests(in: pulled)
        guard found.contains(pin.digest) else {
            throw SandboxError.digestMismatch(expected: pin.digest, found: found.sorted().first)
        }
    }

    /// Every `sha256:` digest in the output of `container image inspect`.
    /// This is a plausibility check, not the guarantee: the guarantee is that
    /// `container image pull ref@digest` fetches exactly that content.
    static func digests(in output: String) -> Set<String> {
        Set(output.matches(of: #/sha256:[0-9a-f]{64}/#).map { String($0.output) })
    }
}
#endif

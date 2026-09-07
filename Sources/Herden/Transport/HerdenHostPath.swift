import Foundation

/// Where `herden` actually lives on Hosts that install it via Homebrew,
/// linuxbrew, cargo, or a user-local prefix.
///
/// SSH exec is not a login shell: sshd's default `PATH` is typically
/// `/usr/bin:/bin`, so a Host that can run `herden` interactively still
/// answers `exec: herden: not found` (exit 127) on Attach. The API socket
/// path does not need the binary — that is why the Console can list Agents
/// while the PTY Attach dies (#206).
///
/// Extra prefixes are appended after the session `PATH` so an existing
/// `herden` keeps priority. There is no separate probe to discover the
/// `herden` path; the agent-availability probe reuses this export in its
/// shell body instead of adding another SSH round trip.
///
/// Two ways the prefixes get onto a command, pick by how `herden` is spelled:
/// - ``wrappingBareHerden(_:)`` at the exec site when the command *word* is
///   still an unpathed `herden` (session list, plugin list, and those
///   overrides).
/// - Bake ``pathExport`` into an existing `/bin/sh -c` body when a bare
///   `herden` or an agent probe lives inside that body. The default plugin
///   config-dir and agent-discovery commands use this form. Wrapping looks
///   only at the command word, so it cannot see an inner `herden`.
enum HerdenHostPath: Sendable {
    /// Directories appended to `PATH` on herden CLI and Agent discovery
    /// execs. `$HOME` is expanded by the remote `/bin/sh`, not by Swift.
    static let extraPATH =
        "$HOME/.local/bin:$HOME/.linuxbrew/bin:$HOME/.cargo/bin:$HOME/.bun/bin:"
        + "/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin"

    static var pathAssignment: String {
        "PATH=\"$PATH:\(extraPATH)\""
    }

    static var pathExport: String {
        "export \(pathAssignment)"
    }

    /// True when `command` invokes an unpathed `herden` as its command word.
    /// Leading `NAME=value` assignments are skipped, so `HERDR_X=1 herden …`
    /// still counts. Quoted literals (`'herden: not json'`), `ENV=herden` in
    /// front of another command, and absolute injectables (`/opt/herden-wake`,
    /// `/nonexistent/herden`) stay false.
    static func isBareHerdenCommand(_ command: String) -> Bool {
        commandWord(in: command) == "herden"
    }

    /// Wraps a still-bare `herden …` in `/bin/sh` so the extra prefixes are
    /// visible even when the account shell is fish (`$PATH` is a list there).
    /// The wrap therefore runs under POSIX sh, not the login shell: a `herden`
    /// that exists only as a shell function or alias is not visible.
    /// Injectable commands whose command word is not `herden` are unchanged.
    /// Embedded single quotes are escaped with `'\''` so a per-Host override
    /// such as `herden --config '/x/y' session list` still gets the PATH fix.
    static func wrappingBareHerden(_ command: String) -> String {
        guard isBareHerdenCommand(command) else { return command }
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        return "/bin/sh -c '\(pathExport); exec \(escaped)'"
    }

    /// Exit 127 from a still-bare `herden` is the PATH miss (#206). Any other
    /// status, or an injectable command, is left for the caller.
    static func missingBinaryError(
        exitStatus: Int32, command: String
    ) -> TransportError? {
        guard exitStatus == 127, isBareHerdenCommand(command) else { return nil }
        return .herdenBinaryNotFound
    }

    private static func commandWord(in command: String) -> Substring? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(whereSeparator: \.isWhitespace)
            .first { !isEnvironmentAssignment($0) }
    }

    /// POSIX `NAME=value` words a shell would consume before the command.
    private static func isEnvironmentAssignment(_ word: Substring) -> Bool {
        guard let separator = word.firstIndex(of: "="), separator > word.startIndex else {
            return false
        }
        let name = word[..<separator]
        guard let first = name.first, first.isASCII else { return false }
        guard first.isLetter || first == "_" else { return false }
        return name.dropFirst().allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber || character == "_")
        }
    }
}

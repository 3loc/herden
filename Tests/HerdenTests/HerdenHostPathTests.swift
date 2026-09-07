import Foundation
import Testing

@testable import Herden

@Suite("Herden host PATH")
struct HerdenHostPathTests {
    @Test func extraPATHIncludesHomebrewAndLinuxbrewPrefixes() {
        #expect(HerdenHostPath.extraPATH.contains("$HOME/.local/bin"))
        #expect(HerdenHostPath.extraPATH.contains("/opt/homebrew/bin"))
        #expect(HerdenHostPath.extraPATH.contains("/home/linuxbrew/.linuxbrew/bin"))
        #expect(HerdenHostPath.extraPATH.contains("$HOME/.linuxbrew/bin"))
        #expect(HerdenHostPath.extraPATH.contains("$HOME/.cargo/bin"))
        #expect(HerdenHostPath.extraPATH.contains("$HOME/.bun/bin"))
        #expect(HerdenHostPath.extraPATH.contains("/usr/local/bin"))
        // Existing PATH entries keep priority over the extra prefixes.
        #expect(HerdenHostPath.pathExport.hasPrefix("export PATH=\"$PATH:"))
    }

    @Test func agentDiscoveryExportsExtraPATHBeforeProbing() {
        let command = SSHTransportSettings.defaultAgentDiscoveryCommand
        #expect(command.hasPrefix("/bin/sh -c '\(HerdenHostPath.pathExport); "))
    }

    @Test func bareHerdenIsOnlyTheCommandWord() {
        #expect(HerdenHostPath.isBareHerdenCommand("herden agent attach"))
        #expect(HerdenHostPath.isBareHerdenCommand("herden session list --json"))
        #expect(HerdenHostPath.isBareHerdenCommand("herden plugin list --json"))
        #expect(HerdenHostPath.isBareHerdenCommand("  herden remote-client-bridge"))
        #expect(HerdenHostPath.isBareHerdenCommand("HERDR_X=1 herden session list --json"))
        #expect(HerdenHostPath.isBareHerdenCommand("FOO=bar BAZ=qux herden plugin list --json"))
        #expect(HerdenHostPath.isBareHerdenCommand("herden --config '/tmp/x y' session list"))
        #expect(!HerdenHostPath.isBareHerdenCommand("/opt/herden-wake --foreground"))
        #expect(!HerdenHostPath.isBareHerdenCommand("/nonexistent/herden plugin list --json"))
        #expect(!HerdenHostPath.isBareHerdenCommand("/bin/sh /tmp/fake-attach.sh"))
        // Assignment whose *value* is "herden", then a different command word.
        #expect(!HerdenHostPath.isBareHerdenCommand("ENV=herden /bin/sh -c 'true'"))
        #expect(!HerdenHostPath.isBareHerdenCommand("herden=1 session list --json"))
        // Quoted literals must not count as the command word (#206 review).
        #expect(!HerdenHostPath.isBareHerdenCommand("printf '%s' 'herden: not json'"))
        #expect(
            !HerdenHostPath.isBareHerdenCommand(
                SSHTransportSettings.defaultNotificationConfigDirCommand))
    }

    @Test func wrappingBareHerdenUsesPOSIXShAndLeavesInjectablesAlone() {
        let wrapped = HerdenHostPath.wrappingBareHerden("herden session list --json")
        #expect(wrapped.hasPrefix("/bin/sh -c '\(HerdenHostPath.pathExport); exec herden "))
        #expect(wrapped.contains("exec herden session list --json"))

        #expect(
            HerdenHostPath.wrappingBareHerden("/opt/herden-wake --foreground")
                == "/opt/herden-wake --foreground")
        #expect(
            HerdenHostPath.wrappingBareHerden("/nonexistent/herden plugin list --json")
                == "/nonexistent/herden plugin list --json")
        #expect(
            HerdenHostPath.wrappingBareHerden("printf '%s' 'herden: not json'")
                == "printf '%s' 'herden: not json'")
    }

    @Test func wrappingKeepsAQuotedOverrideOnThePATHFix() {
        let wrapped = HerdenHostPath.wrappingBareHerden(
            "herden --config '/tmp/x y' session list --json")
        #expect(wrapped.hasPrefix("/bin/sh -c '\(HerdenHostPath.pathExport); exec herden "))
        #expect(wrapped.contains(#"exec herden --config '\''/tmp/x y'\'' session list --json"#))
    }

    @Test func wrappingKeepsLeadingEnvironmentAssignments() {
        let wrapped = HerdenHostPath.wrappingBareHerden("HERDR_X=1 herden session list --json")
        #expect(wrapped.contains("exec HERDR_X=1 herden session list --json"))
        #expect(wrapped.contains(HerdenHostPath.pathExport))
    }

    @Test func wrappingUsesPOSIXShBecauseFishTreatsPATHAsAList() {
        // fish joins `"$PATH"` with spaces, not colons. The wrap therefore
        // never lets the account shell expand PATH: POSIX sh does it.
        let wrapped = HerdenHostPath.wrappingBareHerden("herden session list --json")
        #expect(wrapped.hasPrefix("/bin/sh -c '"))
        #expect(HerdenHostPath.pathExport.contains("\"$PATH:"))
        #expect(!wrapped.hasPrefix("PATH="))
        #expect(!wrapped.hasPrefix("export PATH="))
    }

    @Test func missingBinaryErrorIsOnlyBareHerdenExit127() {
        #expect(
            HerdenHostPath.missingBinaryError(
                exitStatus: 127, command: "herden session list --json")
                == .herdenBinaryNotFound)
        #expect(
            HerdenHostPath.missingBinaryError(
                exitStatus: 127, command: "HERDR_X=1 herden session list --json")
                == .herdenBinaryNotFound)
        #expect(
            HerdenHostPath.missingBinaryError(
                exitStatus: 127, command: "/nonexistent/herden plugin list --json")
                == nil)
        #expect(
            HerdenHostPath.missingBinaryError(
                exitStatus: 1, command: "herden session list --json")
                == nil)
    }

    @Test func notificationConfigDirDefaultExportsTheExtraPATH() {
        let command = SSHTransportSettings.defaultNotificationConfigDirCommand
        #expect(command.contains(HerdenHostPath.pathExport))
        #expect(command.contains("/home/linuxbrew/.linuxbrew/bin"))
        // Command substitution would swallow a 127; do not pretend to classify it.
        #expect(!HerdenHostPath.isBareHerdenCommand(command))
        #expect(HerdenHostPath.wrappingBareHerden(command) == command)
    }

    @Test func attachExecExportsTheExtraPATHBeforeExec() throws {
        let command = try HerdenSSHTransport.attachExecCommand(
            attachCommand: "herden agent attach",
            request: TerminalAttachRequest(target: "w1:p1", cols: 80, rows: 24),
            socketPath: "/tmp/fake.sock")
        #expect(command.contains(HerdenHostPath.pathExport))
        #expect(command.contains("/home/linuxbrew/.linuxbrew/bin"))
        #expect(command.contains("export PATH=\"$PATH:"))
        #expect(command.contains("exec herden agent attach"))
    }

    @Test func attachExecKeepsAnInjectableAbsoluteCommand() throws {
        let command = try HerdenSSHTransport.attachExecCommand(
            attachCommand: "/home/linuxbrew/.linuxbrew/bin/herden agent attach",
            request: TerminalAttachRequest(target: "w1:p1", cols: 80, rows: 24),
            socketPath: "/tmp/fake.sock")
        #expect(
            command.contains("exec /home/linuxbrew/.linuxbrew/bin/herden agent attach"))
        #expect(
            !HerdenHostPath.isBareHerdenCommand(
                "/home/linuxbrew/.linuxbrew/bin/herden agent attach"))
    }
}

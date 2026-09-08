import Testing

@testable import Herden

// Pure path computation; resolving the home directory itself is exercised
// end-to-end in SSHTransportE2ETests.
@Suite struct HerdenSocketLocationTests {
    @Test func defaultSessionLivesUnderConfigDir() {
        let path = HerdenSocketLocation.defaultSession.path(homeDirectory: "/home/u")

        #expect(path == "/home/u/.config/herden/herden.sock")
    }

    @Test func namedSessionLivesUnderSessionsDir() {
        let path = HerdenSocketLocation.namedSession("work").path(homeDirectory: "/home/u")

        #expect(path == "/home/u/.config/herden/sessions/work/herden.sock")
    }

    @Test func absolutePathIgnoresHomeDirectory() {
        let path = HerdenSocketLocation.absolutePath("/tmp/custom.sock")
            .path(homeDirectory: "/home/u")

        #expect(path == "/tmp/custom.sock")
    }

    @Test func trailingSlashOnHomeDoesNotDoubleTheSeparator() {
        let path = HerdenSocketLocation.defaultSession.path(homeDirectory: "/home/u/")

        #expect(path == "/home/u/.config/herden/herden.sock")
    }

    @Test func defaultSessionOffersHerdenThenLegacyHerdr() {
        #expect(
            HerdenSocketLocation.defaultSession.candidatePaths(homeDirectory: "/home/u")
                == [
                    "/home/u/.config/herden/herden.sock",
                    "/home/u/.config/herdr/herdr.sock",
                ])
    }

    @Test func namedSessionOffersMatchingLegacySession() {
        #expect(
            HerdenSocketLocation.namedSession("work").candidatePaths(
                homeDirectory: "/home/u/")
                == [
                    "/home/u/.config/herden/sessions/work/herden.sock",
                    "/home/u/.config/herdr/sessions/work/herdr.sock",
                ])
    }

    @Test func absolutePathHasNoImplicitFallback() {
        #expect(
            HerdenSocketLocation.absolutePath("/tmp/custom.sock").candidatePaths(
                homeDirectory: "/home/u") == ["/tmp/custom.sock"])
    }

    @Test func selectionCommandPassesPathsAsQuotedArguments() throws {
        let command = try HerdenSSHTransport.socketSelectionCommand(
            candidates: [
                "/home/u/My Config/herden.sock",
                "/home/u/Legacy Config/herdr.sock",
            ])

        #expect(command.contains("test -S \"$1\""))
        #expect(command.contains("test -S \"$2\""))
        #expect(command.contains("__HERDEN_SOCKET__=%s"))
        #expect(command.contains("'/home/u/My Config/herden.sock'"))
        #expect(command.contains("'/home/u/Legacy Config/herdr.sock'"))
    }
}

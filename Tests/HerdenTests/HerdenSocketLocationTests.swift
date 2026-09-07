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
}

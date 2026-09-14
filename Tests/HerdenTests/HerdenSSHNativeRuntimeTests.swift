import HerdenSSH
import Testing

@Suite("HerdenSSH Native Runtime")
struct HerdenSSHNativeRuntimeTests {
    @Test("libssh2 initializes at runtime")
    func initializesLibSSH2() {
        #expect(NativeRuntime.smokeTest())
    }
}

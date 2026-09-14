import HerdenSSH
import Testing

@testable import Herden

/// Exercises the real connect-time and post-connect mappers (#133).
@Suite("HerdenSSH error mapping")
struct HerdenSSHErrorMappingTests {
    @Test func connectAndOperationMappersAgreeOnForwardingDenied() {
        let error = SSHError.forwardingDenied
        #expect(
            HerdenSSHTransport.mapConnectForTesting(error)
                == .tcpForwardingUnavailable)
        #expect(
            HerdenSSHTransport.mapOperationForTesting(error)
                == .tcpForwardingUnavailable)
    }

    @Test func connectAndOperationMappersAgreeOnAuthTimeoutAndCancel() {
        #expect(
            HerdenSSHTransport.mapConnectForTesting(SSHError.authenticationFailed)
                == .authenticationFailed)
        #expect(
            HerdenSSHTransport.mapOperationForTesting(SSHError.authenticationFailed)
                == .authenticationFailed)

        #expect(HerdenSSHTransport.mapConnectForTesting(SSHError.timedOut) == .timedOut)
        #expect(HerdenSSHTransport.mapOperationForTesting(SSHError.timedOut) == .timedOut)

        #expect(HerdenSSHTransport.mapConnectForTesting(SSHError.cancelled) == .cancelled)
        #expect(HerdenSSHTransport.mapOperationForTesting(SSHError.cancelled) == .cancelled)
    }

    @Test func pathSpecificMappersStillDivergeWhereIntended() {
        // Connect treats a dead connection as unreachable; operations treat it
        // as a reusable-connection loss with its own copy.
        #expect(
            HerdenSSHTransport.mapConnectForTesting(SSHError.connectionInvalidated)
                == .sshUnreachable(detail: String(describing: SSHError.connectionInvalidated)))
        #expect(
            HerdenSSHTransport.mapOperationForTesting(SSHError.connectionInvalidated)
                == .sshUnreachable(detail: "The SSH connection is no longer reusable."))

        // Generic channel failure is the same classification on both paths.
        #expect(
            HerdenSSHTransport.mapConnectForTesting(SSHError.channelFailed)
                == .channelFailed(detail: String(describing: SSHError.channelFailed)))
        #expect(
            HerdenSSHTransport.mapOperationForTesting(SSHError.channelFailed)
                == .channelFailed(detail: String(describing: SSHError.channelFailed)))
    }
}

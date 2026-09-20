import Foundation
import Darwin
@preconcurrency import Combine

// MARK: - Network Process Watcher

/// Monitors Siri-related system processes for active TCP connections
/// using `proc_pidinfo` with `PROC_PIDLISTFDS` (socket file descriptors).
///
/// Replaces the v0.1 approach of counting Mach IPC messages (`pti_messages_sent`),
/// which was a false proxy for network activity.
final class NetworkProcessWatcher: @unchecked Sendable {

    // MARK: Public

    let networkStatus = CurrentValueSubject<NetworkDestination, Never>(.none)

    // MARK: Private

    private var isMonitoring = false
    private let queue = DispatchQueue(label: "com.siritrace.networkwatcher", qos: .utility)

    /// Process names associated with Siri and Apple Intelligence.
    private let targetProcessNames: Set<String> = [
        "assistantd",
        "siriknowledged",
        "siriactionsd",
        "sirittsd",
        "generativeexperienced",
        "intelligenceplatformd",
        "siri_suggestionsd",
        "apple_intelligenced",
        "siriinferenced"
    ]

    /// Polling interval in seconds.
    private let pollInterval: TimeInterval = 1.5

    /// Apple's IPv4 range: 17.0.0.0/8
    private let appleFirstOctet: UInt8 = 17

    // Flavor constants from <sys/proc_info.h> / <libproc.h>
    private let flavorListFDs: Int32 = 1          // PROC_PIDLISTFDS
    private let fdTypeSocket: UInt32 = 2          // PROX_FDTYPE_SOCKET
    private let flavorSocketInfo: Int32 = 3       // PROC_PIDFDSOCKETINFO
    private let sockinfoTCP: Int32 = 2            // SOCKINFO_TCP

    // MARK: Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        queue.async { [weak self] in
            self?.pollLoop()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
    }

    // MARK: Polling

    private func pollLoop() {
        while isMonitoring {
            autoreleasepool {
                pollOnce()
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private func pollOnce() {
        let pids = findTargetPIDs()
        var bestResult: NetworkDestination = .none

        for pid in pids {
            let dest = inspectSockets(for: pid)
            switch dest {
            case .thirdParty:
                // Third-party is the strongest signal, immediately report
                networkStatus.send(.thirdParty)
                return
            case .appleCloud:
                bestResult = .appleCloud
            case .unknown where bestResult == .none:
                bestResult = .unknown
            default:
                break
            }
        }

        networkStatus.send(bestResult)
    }

    // MARK: PID Discovery

    private func findTargetPIDs() -> [pid_t] {
        let bufferSize = 4096
        var pids = [pid_t](repeating: 0, count: bufferSize)
        let bytesReturned = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * bufferSize))

        guard bytesReturned > 0 else { return [] }
        let pidCount = Int(bytesReturned) / MemoryLayout<pid_t>.size

        var matching: [pid_t] = []
        matching.reserveCapacity(targetProcessNames.count)

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            pathBuffer.withUnsafeMutableBufferPointer { buf in
                let len = proc_pidpath(pid, buf.baseAddress, UInt32(MAXPATHLEN))
                if len > 0 {
                    let path = String(cString: buf.baseAddress!)
                    let name = (path as NSString).lastPathComponent
                    if targetProcessNames.contains(name) {
                        matching.append(pid)
                    }
                }
            }
        }

        return matching
    }

    // MARK: Socket Inspection

    /// Inspects file descriptors of a process to find active TCP connections
    /// and classify their destinations as Apple or third-party.
    private func inspectSockets(for pid: pid_t) -> NetworkDestination {
        // Step 1: Get buffer size for FD list
        let bufSize = proc_pidinfo(pid, flavorListFDs, 0, nil, 0)
        guard bufSize > 0 else { return .none }

        let fdCount = Int(bufSize) / MemoryLayout<proc_fdinfo>.size
        guard fdCount > 0 else { return .none }

        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let actualBufSize = proc_pidinfo(pid, flavorListFDs, 0, &fds, bufSize)
        guard actualBufSize > 0 else { return .none }

        let actualFDCount = Int(actualBufSize) / MemoryLayout<proc_fdinfo>.size

        // Step 2: Check each socket FD
        var hasApple = false
        var hasThirdParty = false
        var hasUnknownSocket = false

        for i in 0..<actualFDCount {
            let fd = fds[i]
            guard fd.proc_fdtype == fdTypeSocket else { continue }

            // Try to get detailed socket info
            let dest = classifySocket(pid: pid, fd: fd.proc_fd)
            switch dest {
            case .appleCloud:   hasApple = true
            case .thirdParty:   hasThirdParty = true
            case .unknown:      hasUnknownSocket = true
            case .none:         break
            }
        }

        if hasThirdParty { return .thirdParty }
        if hasApple { return .appleCloud }
        if hasUnknownSocket { return .unknown }
        return .none
    }

    /// Classifies a single socket FD by inspecting its remote address.
    private func classifySocket(pid: pid_t, fd: Int32) -> NetworkDestination {
        var info = socket_fdinfo()
        let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
        let result = proc_pidfdinfo(pid, fd, flavorSocketInfo, &info, infoSize)

        // If we can't read socket info (SIP, permissions), skip
        guard result == infoSize else { return .none }

        let family = info.psi.soi_family
        // Only interested in IPv4/IPv6 internet sockets
        guard family == AF_INET || family == AF_INET6 else { return .none }

        // Check if it's a TCP socket
        guard info.psi.soi_kind == sockinfoTCP else { return .none }

        // Get the remote IPv4 address
        let tcpInfo = info.psi.soi_proto.pri_tcp
        let remoteAddr = tcpInfo.tcpsi_ini.insi_faddr.ina_46.i46a_addr4.s_addr

        // Skip unconnected sockets (remote addr 0.0.0.0)
        guard remoteAddr != 0 else { return .none }

        // Skip loopback (127.x.x.x)
        let firstOctet = UInt8(remoteAddr & 0xFF) // network byte order on little-endian
        if firstOctet == 127 { return .none }

        // Classify by destination
        if firstOctet == appleFirstOctet {
            return .appleCloud
        } else {
            return .thirdParty
        }
    }
}

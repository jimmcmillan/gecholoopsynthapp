import Foundation

@Observable
@MainActor
final class SerialManager {
    var availablePorts: [String] = []
    var selectedPort: String?
    var isConnected = false
    var receivedText = ""
    var log = ""

    private var fileDescriptor: Int32 = -1
    private var readTask: Task<Void, Never>?
    private var responseBuffer = ""
    private var collectingResponse = false

    init() {
        refreshPorts()
    }

    func refreshPorts() {
        let fm = FileManager.default
        let devPath = "/dev"
        guard let items = try? fm.contentsOfDirectory(atPath: devPath) else {
            availablePorts = []
            return
        }
        availablePorts = items
            .filter { $0.hasPrefix("cu.usbserial") || $0.hasPrefix("cu.usbmodem") }
            .map { "\(devPath)/\($0)" }
            .sorted()
        if let selected = selectedPort, !availablePorts.contains(selected) {
            selectedPort = nil
        }
        if selectedPort == nil {
            selectedPort = availablePorts.first
        }
    }

    func connect() {
        guard let portPath = selectedPort else {
            appendLog("[Error] No port selected")
            return
        }
        guard !isConnected else { return }

        let fd = Darwin.open(portPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            appendLog("[Error] Could not open \(portPath): \(String(cString: strerror(errno)))")
            return
        }

        // Clear non-blocking after open
        var flags = fcntl(fd, F_GETFL, 0)
        flags &= ~O_NONBLOCK
        fcntl(fd, F_SETFL, flags)

        // Configure termios: 115200 baud, 8N1, no flow control
        var options = termios()
        tcgetattr(fd, &options)

        cfsetispeed(&options, speed_t(B115200))
        cfsetospeed(&options, speed_t(B115200))

        // Enable receiver, local mode
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)

        // 8 data bits
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)

        // No parity
        options.c_cflag &= ~tcflag_t(PARENB)

        // 1 stop bit
        options.c_cflag &= ~tcflag_t(CSTOPB)

        // No hardware flow control
        options.c_cflag &= ~tcflag_t(CRTSCTS)

        // Raw input
        options.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ISIG)

        // No software flow control
        options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)

        // Raw output
        options.c_oflag &= ~tcflag_t(OPOST)

        // Read with timeout: VMIN=0, VTIME=5 (0.5 sec)
        options.c_cc.16 = 0   // VMIN
        options.c_cc.17 = 5   // VTIME (tenths of second)

        tcsetattr(fd, TCSANOW, &options)

        // Flush any stale data
        tcflush(fd, TCIOFLUSH)

        fileDescriptor = fd
        isConnected = true
        receivedText = ""
        appendLog("[Connected] \(portPath)")

        startReading()
    }

    func disconnect() {
        readTask?.cancel()
        readTask = nil
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
        isConnected = false
        appendLog("[Disconnected]")
    }

    func send(_ command: String) {
        guard isConnected, fileDescriptor >= 0 else {
            appendLog("[Error] Not connected")
            return
        }
        let message = command.hasSuffix("\n") ? command : command + "\n"
        let data = Array(message.utf8)
        let written = data.withUnsafeBufferPointer { buffer in
            Darwin.write(fileDescriptor, buffer.baseAddress!, buffer.count)
        }
        if written < 0 {
            appendLog("[Error] Write failed: \(String(cString: strerror(errno)))")
        } else {
            appendLog("[TX] \(command)")
        }
    }

    private func startReading() {
        let fd = fileDescriptor
        readTask = Task.detached { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            while !Task.isCancelled {
                let bytesRead = Darwin.read(fd, &buffer, buffer.count)
                if bytesRead > 0 {
                    if let text = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                        await self?.handleReceived(text)
                    }
                } else if bytesRead == 0 {
                    // No data, VTIME timeout elapsed — just loop
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                } else {
                    // Error or port disconnected
                    let err = errno
                    if err != EAGAIN && err != EINTR {
                        await self?.handleError(String(cString: strerror(err)))
                        break
                    }
                }
            }
        }
    }

    /// Sends a command and waits to collect the response.
    /// Waits up to `timeout` seconds, collecting data until no new data arrives
    /// for 300ms (indicating the Gecho is done replying).
    func sendAndCollectResponse(_ command: String, timeout: Double = 2.0) async -> String {
        guard isConnected else { return "" }
        responseBuffer = ""
        collectingResponse = true
        send(command)

        let deadline = Date().addingTimeInterval(timeout)
        var lastLength = 0
        var stableCount = 0

        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            let currentLength = responseBuffer.count
            if currentLength > 0 && currentLength == lastLength {
                stableCount += 1
                if stableCount >= 3 { break } // 300ms of no new data
            } else {
                stableCount = 0
            }
            lastLength = currentLength
        }

        collectingResponse = false
        return responseBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleReceived(_ text: String) {
        receivedText += text
        if collectingResponse {
            responseBuffer += text
        }
        appendLog("[RX] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private func handleError(_ message: String) {
        appendLog("[Error] Read failed: \(message)")
        disconnect()
    }

    func appendLog(_ entry: String) {
        log += entry + "\n"
    }
}

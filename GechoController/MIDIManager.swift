import Foundation
import CoreMIDI

@Observable
@MainActor
final class MIDIManager {
    var availableSources: [String] = []
    var selectedSourceIndex: Int?
    var lastNoteName = ""
    var chordNotes: [UInt8] = []
    private(set) var lastMIDINote: UInt8?
    var log = ""

    /// When set, called on every note-on with the MIDI note number
    var onNoteOn: ((UInt8) -> Void)?

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var connectedSourceRef: MIDIEndpointRef?

    private static let noteNames = ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"]

    init() {
        setupMIDI()
    }

    private func setupMIDI() {
        let status = MIDIClientCreateWithBlock("GechoController" as CFString, &midiClient) { [weak self] notification in
            // MIDI setup changed (device added/removed)
            Task { @MainActor in
                self?.refreshSources()
            }
        }
        guard status == noErr else {
            print("Failed to create MIDI client: \(status)")
            return
        }

        let portStatus = MIDIInputPortCreateWithBlock(midiClient, "GechoInput" as CFString, &inputPort) { [weak self] packetList, _ in
            let packets = packetList.pointee
            var packet = packets.packet
            for _ in 0..<packets.numPackets {
                let data = Mirror(reflecting: packet.data).children.map { $0.value as! UInt8 }
                let length = Int(packet.length)
                if length >= 3 {
                    let statusByte = data[0]
                    let msgType = statusByte & 0xF0
                    let channel = (statusByte & 0x0F) + 1
                    let note = data[1]
                    let velocity = data[2]
                    if msgType == 0x90 && velocity > 0 {
                        Task { @MainActor in
                            self?.processNoteOn(note: note, channel: channel)
                        }
                    } else if msgType == 0x80 || (msgType == 0x90 && velocity == 0) {
                        Task { @MainActor in
                            self?.processNoteOff(note: note, channel: channel)
                        }
                    }
                }
                let packetPtr = MIDIPacketNext(&packet)
                packet = packetPtr.pointee
            }
        }
        guard portStatus == noErr else {
            print("Failed to create MIDI input port: \(portStatus)")
            return
        }

        refreshSources()
    }

    func refreshSources() {
        let count = MIDIGetNumberOfSources()
        var names: [String] = []
        for i in 0..<count {
            let src = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            let result = MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name)
            if result == noErr, let cfName = name?.takeRetainedValue() {
                names.append(cfName as String)
            } else {
                names.append("Source \(i)")
            }
        }
        availableSources = names
        if let idx = selectedSourceIndex, idx >= names.count {
            selectedSourceIndex = nil
        }
    }

    func connectToSource(index: Int) {
        // Disconnect previous
        if let prev = connectedSourceRef {
            MIDIPortDisconnectSource(inputPort, prev)
            connectedSourceRef = nil
        }

        guard index >= 0 && index < MIDIGetNumberOfSources() else { return }
        let src = MIDIGetSource(index)
        let status = MIDIPortConnectSource(inputPort, src, nil)
        if status == noErr {
            connectedSourceRef = src
            selectedSourceIndex = index
        } else {
            print("Failed to connect to MIDI source: \(status)")
        }
    }

    func disconnectSource() {
        if let prev = connectedSourceRef {
            MIDIPortDisconnectSource(inputPort, prev)
            connectedSourceRef = nil
        }
        selectedSourceIndex = nil
    }

    func addNoteToChord(_ note: UInt8) {
        if !chordNotes.contains(note) {
            chordNotes.append(note)
        }
    }

    func addLastNoteToChord() {
        guard let note = lastMIDINote else { return }
        addNoteToChord(note)
    }

    func clearChord() {
        chordNotes.removeAll()
    }

    func removeNoteFromChord(_ note: UInt8) {
        chordNotes.removeAll { $0 == note }
    }

    /// Converts collected chord notes to Gecho notation (e.g. "a3c4e4")
    func chordAsGechoString() -> String {
        let sorted = chordNotes.sorted()
        return sorted.map { Self.midiNoteToGechoName($0) }.joined()
    }

    /// Converts a MIDI note number to Gecho notation (e.g. 69 → "a4")
    static func midiNoteToGechoName(_ midiNote: UInt8) -> String {
        let note = Int(midiNote)
        let nameIndex = note % 12
        let octave = note / 12 - 1
        return "\(noteNames[nameIndex])\(octave)"
    }

    /// Converts a Gecho note name back to display format (e.g. "a4" → "A4")
    static func displayName(for midiNote: UInt8) -> String {
        let note = Int(midiNote)
        let nameIndex = note % 12
        let octave = note / 12 - 1
        return "\(noteNames[nameIndex].uppercased())\(octave)"
    }

    func processNoteOn(note: UInt8, channel: UInt8) {
        lastNoteName = Self.midiNoteToGechoName(note)
        lastMIDINote = note
        log += "[MIDI] Note On: \(Self.displayName(for: note)) (MIDI \(note), ch\(channel))\n"
        onNoteOn?(note)
    }

    func processNoteOff(note: UInt8, channel: UInt8) {
        log += "[MIDI] Note Off: \(Self.displayName(for: note)) (MIDI \(note), ch\(channel))\n"
    }

    /// Converts a MIDI note number to frequency in Hz
    static func midiNoteToFrequency(_ note: UInt8) -> Float {
        440.0 * pow(2.0, Float(Int(note) - 69) / 12.0)
    }
}

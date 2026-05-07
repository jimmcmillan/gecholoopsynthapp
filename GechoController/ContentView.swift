import SwiftUI
import CoreMIDI

struct ContentView: View {
    @State private var serial = SerialManager()
    @State private var midi = MIDIManager()

    @State private var channelText = ""
    @State private var songText = ""
    @State private var melodyText = ""
    @State private var slotName = ""
    @State private var livePlayEnabled = false
    @State private var midiToTextEnabled = false
    @State private var consoleInput = ""
    @State private var showClearSongAlert = false
    @State private var showClearMelodyAlert = false

    enum FocusedField {
        case song, melody
    }
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The Awesome Gecho Loopsynth App")
                    .font(.title)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .center)

                serialConnectionSection
                consoleSection
                buttonsSection
                channelSection
                songSection
                melodySection
                // saveLoadSection
                midiSection
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 600)
        .onChange(of: focusedField) { _, _ in
            updateMIDIHandler()
        }
    }

    // MARK: - Serial Connection

    private var serialConnectionSection: some View {
        GroupBox("Serial Connection") {
            HStack {
                Picker("Port", selection: $serial.selectedPort) {
                    Text("None").tag(String?.none)
                    ForEach(serial.availablePorts, id: \.self) { port in
                        Text(port.replacingOccurrences(of: "/dev/", with: ""))
                            .tag(Optional(port))
                    }
                }
                .frame(maxWidth: 250)

                Button {
                    serial.refreshPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh port list")

                Spacer()

                Circle()
                    .fill(serial.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Button(serial.isConnected ? "Disconnect" : "Connect") {
                    if serial.isConnected {
                        serial.disconnect()
                    } else {
                        serial.connect()
                        Task {
                            await performHandshake()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        GroupBox("Buttons") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { num in
                        Button("\(num)") {
                            serial.send("BTN=\(num)")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                HStack(spacing: 8) {
                    Button("SET") {
                        serial.send("BTN=SET")
                    }
                    .frame(maxWidth: .infinity)

                    Button("RST") {
                        serial.send("BTN=RST")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(!serial.isConnected)
        }
    }

    // MARK: - Channel

    private var channelSection: some View {
        GroupBox("Channel") {
            HStack {
                TextField("Channel number", text: $channelText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)

                Button("Send") {
                    serial.send("CHAN=\(channelText)")
                }
                .disabled(!serial.isConnected || channelText.isEmpty)

                Spacer()
            }
        }
    }

    // MARK: - Song

    private var songSection: some View {
        GroupBox("Song") {
            VStack(alignment: .leading) {
                Text("Chord progression (e.g. a3c4e4,d4f#4a4,e4g#4b4)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $songText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 60)
                    .border(Color.secondary.opacity(0.3))
                    .focused($focusedField, equals: .song)

                HStack {
                    Button("Send Song") {
                        Task {
                            serial.send("BTN=RST")
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            serial.send("SONG=\(songText)")
                        }
                    }
                    .disabled(!serial.isConnected || songText.isEmpty)

                    Button("Query Song") {
                        Task {
                            serial.send("BTN=RST")
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            let reply = await serial.sendAndCollectResponse("SONG?=")
                            if !reply.isEmpty {
                                songText = reply
                            }
                        }
                    }
                    .disabled(!serial.isConnected)

                    Button("Clear Song") {
                        showClearSongAlert = true
                    }
                    .disabled(!serial.isConnected)
                    .alert("Clear Song", isPresented: $showClearSongAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Clear", role: .destructive) {
                            Task {
                                serial.send("BTN=RST")
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                serial.send("SONG=CLEAR")
                                songText = ""
                                serial.send("MELODY=CLEAR")
                                melodyText = ""
                            }
                        }
                    } message: {
                        Text("Are you sure you want to erase the Song and Melody?")
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Melody

    private var melodySection: some View {
        GroupBox("Melody") {
            VStack(alignment: .leading) {
                Text("Melody string (e.g. a4. c5. e5.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $melodyText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 60)
                    .border(Color.secondary.opacity(0.3))
                    .focused($focusedField, equals: .melody)

                HStack {
                    Button("Send Melody") {
                        Task {
                            serial.send("BTN=RST")
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            serial.send("MELODY=\(melodyText)")
                        }
                    }
                    .disabled(!serial.isConnected || melodyText.isEmpty)

                    Button("Query Melody") {
                        Task {
                            serial.send("BTN=RST")
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            let reply = await serial.sendAndCollectResponse("MELODY?=")
                            if !reply.isEmpty {
                                melodyText = reply
                            }
                        }
                    }
                    .disabled(!serial.isConnected)

                    Button("Clear Melody") {
                        showClearMelodyAlert = true
                    }
                    .disabled(!serial.isConnected)
                    .alert("Clear Melody", isPresented: $showClearMelodyAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Clear", role: .destructive) {
                            Task {
                                serial.send("BTN=RST")
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                serial.send("MELODY=CLEAR")
                                melodyText = ""
                            }
                        }
                    } message: {
                        Text("Are you sure you want to erase the Melody?")
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Save / Load

    private var saveLoadSection: some View {
        GroupBox("Save / Load (Channel 111)") {
            HStack {
                // TextField("Slot name", text: $slotName)
                //     .textFieldStyle(.roundedBorder)
                //     .frame(maxWidth: 150)

                Button("Save") {
                    var command = "SAVE=111"
                    if !songText.isEmpty {
                        command += "&SONG=\(songText)"
                    }
                    if !melodyText.isEmpty {
                        command += "&MELODY=\(melodyText)"
                    }
                    serial.send(command)
                }
                .disabled(!serial.isConnected || (songText.isEmpty && melodyText.isEmpty))

                Button("Load") {
                    Task {
                        let reply = await serial.sendAndCollectResponse("LOAD=111")
                        parseLoadResponse(reply)
                    }
                }
                .disabled(!serial.isConnected)

                Button("Erase All") {
                    serial.send("ERASE=ALL")
                }
                .disabled(!serial.isConnected)

                Spacer()
            }
        }
    }

    private func updateMIDIHandler() {
        midi.onNoteOn = { [self] note in
            // Append to focused text field if enabled
            if midiToTextEnabled {
                let noteName = MIDIManager.midiNoteToGechoName(note)
                switch focusedField {
                case .song:
                    if songText.isEmpty {
                        songText = noteName
                    } else {
                        songText += noteName
                    }
                case .melody:
                    if melodyText.isEmpty {
                        melodyText = noteName
                    } else {
                        melodyText += noteName
                    }
                case nil:
                    break
                }
            }

            // Live play: send FREQ command
            if livePlayEnabled {
                let freq = MIDIManager.midiNoteToFrequency(note)
                serial.send(String(format: "FREQ=%.2f", freq))
            }
        }
    }

    private func performHandshake() async {
        guard serial.isConnected else { return }
        // Small delay to let the port settle after opening
        try? await Task.sleep(nanoseconds: 300_000_000)
        let reply = await serial.sendAndCollectResponse("Hi Gecho!")
        if reply.contains("Hi there") {
            // Handshake confirmed, query firmware version
            let version = await serial.sendAndCollectResponse("FN=VER")
            if !version.isEmpty {
                serial.appendLog("[Firmware] \(version)")
            }
        } else {
            serial.appendLog("[Error] Handshake Failed. Check connection!")
            serial.disconnect()
        }
    }

    private func parseLoadResponse(_ response: String) {
        // Expected format: SONG=a3c4e4,d4f#4a4&MELODY=a4,c5,b4
        // or individual fields separated by &
        let parts = response.components(separatedBy: "&")
        for part in parts {
            if part.hasPrefix("SONG=") {
                songText = String(part.dropFirst("SONG=".count))
            } else if part.hasPrefix("MELODY=") {
                melodyText = String(part.dropFirst("MELODY=".count))
            }
        }
    }

    // MARK: - MIDI

    private var midiSection: some View {
        GroupBox("MIDI Input") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Source", selection: Binding(
                        get: { midi.selectedSourceIndex ?? -1 },
                        set: { newValue in
                            if newValue < 0 {
                                midi.disconnectSource()
                            } else {
                                midi.connectToSource(index: newValue)
                            }
                        }
                    )) {
                        Text("None").tag(-1)
                        ForEach(Array(midi.availableSources.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    .frame(maxWidth: 250)

                    Button {
                        midi.refreshSources()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh MIDI sources")

                    Spacer()
                }

                HStack {
                    Toggle("Live Play (Ch 113)", isOn: $livePlayEnabled)
                        .onChange(of: livePlayEnabled) { _, enabled in
                            if enabled {
                                serial.send("CHAN=113")
                            }
                            updateMIDIHandler()
                        }
                        .disabled(!serial.isConnected || midi.selectedSourceIndex == nil)

                    Spacer()
                }

                HStack {
                    Toggle("MIDI to Text Fields", isOn: $midiToTextEnabled)
                        .onChange(of: midiToTextEnabled) { _, _ in
                            updateMIDIHandler()
                        }
                        .disabled(midi.selectedSourceIndex == nil)

                    Spacer()
                }

                HStack {
                    Text("Last note:")
                        .foregroundStyle(.secondary)
                    Text(midi.lastNoteName.isEmpty ? "—" : midi.lastNoteName)
                        .font(.system(.body, design: .monospaced))
                        .bold()

                    Button("Add to Chord") {
                        midi.addLastNoteToChord()
                    }
                    .disabled(midi.lastMIDINote == nil)
                }

                if !midi.chordNotes.isEmpty {
                    HStack {
                        Text("Chord:")
                            .foregroundStyle(.secondary)

                        ForEach(midi.chordNotes, id: \.self) { note in
                            HStack(spacing: 2) {
                                Text(MIDIManager.displayName(for: note))
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(4)

                                Button {
                                    midi.removeNoteFromChord(note)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack {
                        Text("Gecho: \(midi.chordAsGechoString())")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Send Chord to Song") {
                        let chord = midi.chordAsGechoString()
                        if songText.isEmpty {
                            songText = chord
                        } else {
                            songText += ",\(chord)"
                        }
                    }
                    .disabled(midi.chordNotes.isEmpty)

                    Button("Clear Chord") {
                        midi.clearChord()
                    }
                    .disabled(midi.chordNotes.isEmpty)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(midi.log.isEmpty ? "No MIDI activity yet." : midi.log)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Color.clear.frame(height: 0).id("midiLogBottom")
                    }
                    .onChange(of: midi.log) {
                        proxy.scrollTo("midiLogBottom", anchor: .bottom)
                    }
                }
                .frame(height: 80)
                .border(Color.secondary.opacity(0.2))
            }
        }
    }

    // MARK: - Console

    private var consoleSection: some View {
        GroupBox("Console") {
            VStack(spacing: 4) {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(serial.log.isEmpty ? "No activity yet." : serial.log)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Color.clear.frame(height: 0).id("serialLogBottom")
                    }
                    .onChange(of: serial.log) {
                        proxy.scrollTo("serialLogBottom", anchor: .bottom)
                    }
                }
                .frame(height: 120)

                TextField("Enter command...", text: $consoleInput)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard !consoleInput.isEmpty else { return }
                        serial.send(consoleInput)
                        consoleInput = ""
                    }
                    .disabled(!serial.isConnected)
            }
        }
    }
}

#Preview {
    ContentView()
}

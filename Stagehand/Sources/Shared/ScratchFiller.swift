import Foundation

/// Fills the scratch tones for a Rocksmith song (ScratchTones.swift) and plays them.
///
/// The speaker edits only the tone a channel plays, and saving into another tone copies the
/// playing tone there with its edits and name (protocol-notes.md, Tone actions). So for each
/// song tone the channel plays its template slot, gets the song's pedal changes, and is saved
/// into the scratch tone, which is then renamed back; the template's edits are dropped. About
/// half a second a tone, while the song loads; the channel jumps between the slots meanwhile.
///
/// The five scratch tones ("RS 1" … "RS 5", category Others) are made on first use with save as
/// and kept in `BandBoxClient.scratchTones`; one deleted in the JBL app is made again.
@MainActor
final class ScratchFiller: ObservableObject {
    enum State: Equatable {
        case idle
        case filling(done: Int, of: Int)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var request: SongTonesRequest?
    /// The song tones filled for `request`, by index.
    @Published private(set) var ready: Set<Int> = []
    /// The guitar channel the song tones play on.
    @Published private(set) var channel = 3

    // Set by start (MIDIInput), so the app can own the filler and the screens can watch it.
    private var client: BandBoxClient!
    private var assignments: ToneAssignments!
    private var generation = 0
    private var wanted: Int?                // the scratch tone a Program Change asked for while filling

    func start(client: BandBoxClient, assignments: ToneAssignments) {
        self.client = client
        self.assignments = assignments
    }

    /// The song tone `channel` plays, if it plays one that is filled.
    func playing(channel: Int) -> Int? {
        guard request != nil, channel == self.channel, let tone = client?.presets[channel],
              let i = client.scratchTones.firstIndex(of: tone), ready.contains(i) else { return nil }
        return i
    }

    /// The tone slot a song tone is built on.
    func slot(_ index: Int) -> ToneSlot? {
        request.flatMap { $0.tones.indices.contains(index) ? ToneSlot.all[$0.tones[index].slot] : nil }
    }

    /// A new song: fills its tones, replacing any fill still running.
    func load(_ request: SongTonesRequest) {
        guard let client else { return }
        makeMissingBanks(request)
        // The tone buttons show the bank the song's tones are built from.
        if let bank = assignments.bank(named: request.bank), bank != assignments.current {
            assignments.selectBank(bank)
            client.record("bank \(assignments.bankName) for \(request.song.isEmpty ? "this song" : request.song)")
        }
        channel = client.primaryGuitarChannel
        generation += 1
        self.request = request
        ready = []
        wanted = nil
        guard client.link == .connected, !request.tones.isEmpty else {
            fail(request.tones.isEmpty ? "no tones" : "not connected to the speaker")
            return
        }
        let generation = generation
        // Filling from now, so a Program Change that comes before the task starts waits for it.
        state = .filling(done: 0, of: request.tones.count)
        Task { await fill(request, generation) }
    }

    /// Makes the banks the companion may name and Stagehand doesn't have yet, as copies of Main
    /// (or of the current bank if there's no Main), for the player to set up. Until they do, the
    /// songs that use them sound as with Main.
    private func makeMissingBanks(_ request: SongTonesRequest) {
        let source = assignments.bank(named: "Main") ?? assignments.current
        for name in request.banks + [request.bank] where !name.isEmpty && assignments.bank(named: name) == nil {
            assignments.addBank(named: name, copying: source)
            client.record("made bank \(name), a copy of \(assignments.banks[source].name): set its slots for these songs")
        }
    }

    /// Program Change 8 + `index`: plays that scratch tone, or its template slot until it's
    /// filled. While filling, the last one asked for plays when the fill is done, on the channel
    /// the fill is on.
    func play(_ index: Int) {
        guard let request, let client, request.tones.indices.contains(index), client.link == .connected else { return }
        if case .filling = state {
            wanted = index
            return
        }
        channel = client.primaryGuitarChannel
        if ready.contains(index), client.scratchTones.indices.contains(index) {
            client.setPreset(client.scratchTones[index], channel: channel)
        } else {
            client.setPreset(template(request.tones[index], channel), channel: channel)
        }
    }

    /// The tone a song tone starts from: its slot in the bank the song names, or in the current
    /// bank if there is none by that name.
    private func template(_ tone: SongTonesRequest.Tone, _ channel: Int) -> Int {
        assignments.tone(ToneSlot.all[tone.slot], channel: channel, bank: bank)
    }

    private var bank: Int { request.flatMap { assignments.bank(named: $0.bank) } ?? assignments.current }

    private func current(_ generation: Int) -> Bool { generation == self.generation }

    private func fill(_ request: SongTonesRequest, _ generation: Int) async {
        let start = Date()
        state = .filling(done: 0, of: request.tones.count)
        client.record("song tones from bank \(assignments.banks[bank].name)")
        guard let scratch = await scratchTones(request.tones.count), current(generation) else {
            if current(generation) { fail("couldn't make the scratch tones") }
            return
        }
        var writes = 0
        for (i, tone) in request.tones.enumerated() {
            let template = template(tone, channel), target = scratch[i]
            // Select the template (dropping edits if it is playing already), read its saved blocks.
            if client.presets[channel] == template {
                _ = await action(.discard, tone: template)
            } else {
                _ = await exchange(BandBoxProtocol.set(Property.preset, [UInt8(channel), UInt8(template)]),
                                   Property.preset, timeout: 1.5) { $0 == [UInt8(self.channel), UInt8(template)] }
            }
            guard current(generation) else { return }
            guard let value = await exchange(BandBoxProtocol.set(Property.toneDetailsQuery, [UInt8(template)]),
                                             Property.toneDetails, { $0.first == UInt8(template) }),
                  let details = BandBoxProtocol.toneDetails(value), current(generation) else {
                if current(generation) { fail("no details for tone \(template)") }
                return
            }
            var warnings: [String] = []
            let edits = ScratchPlan.edits(from: details.blocks.map(KnownBlock.init),
                                          to: ScratchPlan.target(template: details, tone: tone, warnings: &warnings))
            warnings.forEach { client.record("! song tones: \($0)") }
            for edit in edits {
                client.sendRaw(BandBoxProtocol.set(Property.effectBlock, edit.value(channel: channel, tone: template)))
            }
            writes += edits.count
            // The writes are queued in order, so the save follows them.
            guard await action(.save, tone: target) != nil, current(generation) else {
                if current(generation) { fail("tone \(i + 1) wasn't saved") }
                return
            }
            _ = await action(.rename, tone: target, name: Self.name(i))
            _ = await action(.discard, tone: template)
            guard current(generation) else { return }
            ready.insert(i)
            state = .filling(done: i + 1, of: request.tones.count)
            client.record("song tone \(i + 1) \(tone.key): \(ToneSlot.all[tone.slot].name) + \(edits.count) writes → \(Self.name(i))")
        }
        state = .ready
        client.record(String(format: "song tones ready: %d tones, %d writes, %.1f s", request.tones.count, writes,
                             Date().timeIntervalSince(start)))
        let play = wanted ?? 0
        wanted = nil
        self.play(play)
    }

    private func fail(_ reason: String) {
        state = .failed(reason)
        client.record("! song tones: \(reason); Program Change 8–12 play the template slots")
        if let wanted { self.wanted = nil; play(wanted) }
    }

    private nonisolated static func name(_ index: Int) -> String { "RS \(index + 1)" }
    nonisolated static func isScratchName(_ name: String) -> Bool { (0 ..< SongTonesRequest.maxTones).map(Self.name).contains(name) }

    /// The first `count` scratch tones, made with save as from the playing tone where missing.
    private func scratchTones(_ count: Int) async -> [Int]? {
        var ids = client.scratchTones
        if !client.tones.isEmpty {
            ids = ids.filter { id in client.tones.contains { $0.id == id && $0.isUser } }
        }
        while ids.count < count {
            guard let playing = client.presets[channel],
                  let echo = await exchange(BandBoxProtocol.toneAction(.saveAs, channel: channel, tone: playing,
                                                                       category: 7, name: Self.name(ids.count)),
                                            Property.toneAction, { $0.count > 3 && $0[1] == ToneAction.saveAs.rawValue }),
                  echo[3] != 0xFF else { return nil }
            ids.append(Int(echo[3]))
            client.scratchTones = ids
            client.record("made scratch tone \(Self.name(ids.count - 1)) (\(echo[3]))")
        }
        client.scratchTones = ids
        return Array(ids.prefix(count))
    }

    /// A tone action on the speaker; the echo, or nil if none came.
    private func action(_ op: ToneAction, tone: Int, name: String = "") async -> [UInt8]? {
        let message = BandBoxProtocol.toneAction(op, channel: channel, tone: tone,
                                                 target: op == .rename ? UInt8(tone) : 0xFF, name: name)
        return await exchange(message, Property.toneAction) { $0.count > 2 && $0[1] == op.rawValue && $0[2] == UInt8(tone) }
    }

    /// Sends `message` and waits for the first record `id` that `match` accepts.
    private func exchange(_ message: Data, _ id: UInt16, timeout: TimeInterval = 2.5,
                          _ match: @escaping ([UInt8]) -> Bool) async -> [UInt8]? {
        await withCheckedContinuation { (continuation: CheckedContinuation<[UInt8]?, Never>) in
            let key = UUID()
            var done = false
            let finish: ([UInt8]?) -> Void = { [weak client] value in
                guard !done else { return }
                done = true
                client?.recordObservers[key] = nil
                continuation.resume(returning: value)
            }
            client.recordObservers[key] = { record in
                if record.id == id, match(record.value) { finish(record.value) }
            }
            client.sendRaw(message)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}

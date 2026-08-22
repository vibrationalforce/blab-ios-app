#if canImport(SwiftUI)
import SwiftUI

// PatchbayView.swift
// Echoel — the universal routing patchbay made visible. Each SOURCE lists the
// DESTINATIONS it can reach (same type directly, or via a converter like
// pitch→colour); tap to connect/disconnect. "Smart patch" applies every sensible
// connection at once. Honest: each endpoint shows its transport status (live vs
// soon), and the note explains which edges move bytes today. Binds to SignalRouter
// (persisted). See docs/dev/DMMW_ARCHITECTURE.md + Core/SignalRouting.swift.

@MainActor
struct PatchbayView: View {

    @Environment(SignalRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    #if canImport(Network)
    @Environment(OSCSender.self) private var osc
    @Environment(ADMOSCSender.self) private var admOSC
    @Environment(ArtNetSender.self) private var artNet
    @Environment(SACNSender.self) private var sacn
    #endif

    #if os(iOS) && canImport(CoreMIDI)
    /// #187 — the inbound RTP-MIDI switch. Declared via `StudioDefaultKeys` so the
    /// key string and the default-OFF literal live in one place (H15-KEYSTORE); the
    /// engine reads the SAME key in `MIDIInput.applyNetworkSessionPreference()`.
    @AppStorage(StudioDefaultKeys.networkMIDI.key)
    private var networkMIDI = StudioDefaultKeys.networkMIDI.value

    /// #713 — the two MIDI-OUT quality switches. Same shape as `networkMIDI` above: the key
    /// string and the default-OFF literal live once in `StudioDefaultKeys`, and the engine
    /// reads the SAME keys in `MIDIOutput.applyOutputPreferences()`.
    @AppStorage(StudioDefaultKeys.midiOutMPE.key)
    private var midiOutMPE = StudioDefaultKeys.midiOutMPE.value

    @AppStorage(StudioDefaultKeys.midiOutExpression.key)
    private var midiOutExpression = StudioDefaultKeys.midiOutExpression.value

    /// The live MIDI-out engine, injected at the app root (`EchoelmusicApp`, `.environment`).
    /// Read only to APPLY the two switches above; the flags themselves are never assigned
    /// from here, so this surface never becomes a second lifecycle owner (the BLE-3 lesson).
    ///
    /// Declared INSIDE this guard, next to its only users, rather than beside `router`: an
    /// `@Environment(Type.self)` with no injected value traps when it is READ, so keeping the
    /// declaration and the reads under one condition means there is no platform on which this
    /// view can compile with a lookup it cannot satisfy.
    @Environment(MIDIOutput.self) private var midiOut
    #endif

    /// `true` when hosted as a workspace surface rather than a sheet.
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Routing")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBar
                #if canImport(Network)
                networkOutSection
                lichtSection
                #endif
                #if os(iOS) && canImport(CoreAudioKit)
                // The NavigationLink push needs the enclosing NavigationStack, which only
                // exists on the sheet (non-embedded) path — so gate it to !embedded (no
                // dead control in the dormant workspace path).
                if !embedded { bluetoothMIDISection }
                #endif
                #if os(iOS) && canImport(CoreMIDI)
                // Mounted unconditionally: it is a Toggle, not a NavigationLink push, so
                // unlike `bluetoothMIDISection` it needs no enclosing NavigationStack and
                // is correct on the embedded path too. Defensive rather than a live fix —
                // `PatchbayView(embedded:)` has no caller today — but a control that only
                // works on one of two hosts is exactly how a door goes missing again.
                networkMIDISection
                midiOutSection
                #endif
                ForEach(router.graph.sources) { src in
                    sourceCard(src)
                }
                Text("Tap a destination to route a source to it. Compatible types connect directly or via a converter (e.g. pitch→colour, bio→MIDI CC). Light and spatial follow the music live today; other edges are authored here as their adapters come online.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
    }

    #if os(iOS) && canImport(CoreAudioKit)
    // MARK: - Bluetooth MIDI (B6: pair a wireless controller — plays the synth directly)
    /// A titled card (same grammar as `lichtSection`) with a single push to Apple's
    /// built-in BLE-MIDI central. A NavigationLink PUSH — not a `.sheet`/`.fullScreenCover`
    /// — so `EchoelStudioView`'s modal metadata chain does not grow. A paired controller
    /// becomes a CoreMIDI source that `MIDIInput` auto-connects → real synth notes.
    private var bluetoothMIDISection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bluetooth MIDI").font(EchoelTheme.font(11, .bold)).foregroundStyle(EchoelTheme.dim)
            NavigationLink {
                BluetoothMIDIPairingView()
                    .navigationTitle("Bluetooth MIDI")
                    .navigationBarTitleDisplayMode(.inline)
                    .ignoresSafeArea()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pianokeys").font(.system(size: 13)).foregroundStyle(EchoelTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pair a controller")
                            .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                        Text("Pair a wireless MIDI keyboard or controller — it plays the synth directly.")
                            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pair a Bluetooth MIDI controller")
            .accessibilityHint("Opens Apple's Bluetooth MIDI pairing. A paired controller plays the synth directly.")
        }
    }
    #endif

    #if os(iOS) && canImport(CoreMIDI)
    // MARK: - Network MIDI (#187: the inbound listener gets a switch, default OFF)
    /// The one control for Apple's RTP-MIDI session. It sits in Routing rather than
    /// anywhere in the instrument because it is a ROUTE, not a sound — and because
    /// this surface is reachable (master panel → "Routing"), which is the whole point:
    /// until this shipped, the session was armed at launch on every install with no
    /// control anywhere. A capability with no switch is not a feature, and an inbound
    /// network listener with no switch is not a default anyone chose.
    ///
    /// `Toggle`, not `EchoelValueField`: the app-wide field law covers adjustable
    /// NUMERIC parameters. This is a binary route on/off, same grammar as the other
    /// route switches on this surface.
    private var networkMIDISection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network MIDI").font(EchoelTheme.font(11, .bold)).foregroundStyle(EchoelTheme.dim)
            VStack(alignment: .leading, spacing: 6) {
                // COPY IS DELIBERATELY TWO-DIRECTIONAL (corrected 2026-07-28). The label
                // read "Receive wireless MIDI" and the off-state promised only that no
                // INCOMING session is accepted. That understates the switch: disabling
                // `MIDINetworkSession` withdraws the network endpoint as a CoreMIDI
                // DESTINATION too, and `MIDIOutput.send` fans out to every destination —
                // so wireless MIDI OUT to a Mac stops as well. A control that names half
                // of what it does is the repo's own "lying control" class; the rationale
                // in MIDIInput being framed as inbound-only is what led the copy astray.
                Toggle(isOn: $networkMIDI) {
                    Text("Wireless MIDI session")
                        .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                }
                .tint(EchoelTheme.accent)
                .accessibilityHint(networkMIDI
                    ? "On. Any device on your local network can open a MIDI session with this iPhone, and this iPhone can send MIDI out over the network."
                    : "Off. No wireless MIDI session in either direction.")
                Text(networkMIDI
                     ? "This iPhone accepts a MIDI session from any device on your local network — a Mac's Network MIDI, rtpMIDI, or a compatible app — and appears to them as a wireless MIDI destination. Turn it off when you are on a network you do not control."
                     : "Off. This iPhone does not announce itself for wireless MIDI: no incoming session is accepted, and it no longer appears as a wireless MIDI destination, so MIDI out over the network stops too. Turn it on to play the instrument from a Mac, or to play a Mac from here, over the network.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            // Apply on change, from the SAME entry point launch uses, so the switch
            // and the live session can never disagree. @AppStorage has already written
            // the key by the time this fires.
            .onChange(of: networkMIDI) { _, _ in MIDIInput.applyNetworkSessionPreference() }
        }
    }

    // MARK: - MIDI out quality (#713: the two switches the Tools-grid removal took)

    /// The MPE layout and per-note expression switches for the OUTBOUND stream.
    ///
    /// WHY IT IS HERE. `MIDIOutput.mpeEnabled` and `.expressionEnabled` gate live code — the
    /// zone RPN when the port opens, and the Glide/Slide/Press bytes that ride with each
    /// note-on — and both lost their only control when the Tools grid was removed. Until this
    /// section a player routing to a hardware rig got plain channel-1 notes with no way to ask
    /// for anything else. (⛔ #713 dated that removal as a fact; the clone is shallow and cannot
    /// show it — the measured part is that no control existed anywhere. #714 finding F.) `networkMIDISection` above states the rule
    /// this follows: a capability with no switch is not a feature. Routing is the right home
    /// because these describe the OUTBOUND stream, not a sound.
    ///
    /// `Toggle`, not `EchoelValueField`: the app-wide field law covers adjustable NUMERIC
    /// parameters, and these are binary, exactly like the switch above.
    ///
    /// ⚠️ THE SECOND SWITCH IS DISABLED WHILE THE FIRST IS OFF, and that is the honesty half
    /// of this slice rather than polish. `MIDIOutput`'s send path reads
    /// `if mpeEnabled, expressionEnabled` — per-note bend and pressure need a member channel
    /// per note — so an expression switch that could be turned on alone would move, persist
    /// and change nothing. Disabled and visible beats hidden: the dependency is the thing a
    /// player needs to understand, and hiding the row would make it a mystery instead.
    private var midiOutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MIDI out").font(EchoelTheme.font(11, .bold)).foregroundStyle(EchoelTheme.dim)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $midiOutMPE) {
                    Text("MPE note layout")
                        .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                }
                .tint(EchoelTheme.accent)
                .accessibilityHint(midiOutMPE
                    ? "On. Notes are spread across the MPE member channels, so a rig can bend and press each note on its own."
                    : "Off. Every note is sent on channel 1.")

                Toggle(isOn: $midiOutExpression) {
                    Text("Per-note expression")
                        .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                }
                .tint(EchoelTheme.accent)
                .disabled(!midiOutMPE)
                .accessibilityHint(midiOutMPE
                    ? (midiOutExpression
                       ? "On. Each note carries the body's live Glide, Slide and Press."
                       : "Off. Notes are sent without per-note expression.")
                    : "Unavailable while MPE note layout is off, because per-note expression needs one channel per note.")

                Text(midiOutMPE
                     ? (midiOutExpression
                        ? "Notes go out across the MPE member channels, each carrying the body's live Glide, Slide and Press. Point it at an MPE synth or a DAW track."
                        : "Notes go out across the MPE member channels. Turn on per-note expression to send the body's Glide, Slide and Press with each note.")
                     : "Every note goes out on channel 1 — what any MIDI device understands. Turn on the MPE note layout to give each note its own channel; per-note expression needs that and stays unavailable until then.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                // ⛔ #713 SHIPPED THE THREE SENTENCES ABOVE WITHOUT THIS ONE, and they say
                // "notes go out" unconditionally. Nothing goes out unless the `midi.out` sink
                // is routed below — `MIDIOutput.noteOn` guards on `enabled`, which only
                // `applyRouting()` sets. With the route off, both switches move, persist,
                // change the engine flags and change NO byte: the same lying-control class the
                // `.disabled(!midiOutMPE)` above exists to prevent, one level out (#714).
                //
                // A sentence rather than `.disabled(!midiOut.enabled)`: the disabled form would
                // read an engine property in `body`, and this surface deliberately touches
                // `midiOut` only inside `.onChange` so it registers no observation at all.
                Text("Both need the MIDI out route switched on below — without it nothing is sent, whatever these say.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            // Apply from the SAME entry point launch uses, so the switch and the live engine
            // can never disagree — the `networkMIDISection` pattern. @AppStorage has already
            // written the key by the time this fires.
            .onChange(of: midiOutMPE) { _, _ in midiOut.applyOutputPreferences() }
            .onChange(of: midiOutExpression) { _, _ in midiOut.applyOutputPreferences() }
        }
    }

    #endif


    #if canImport(Network)
    // MARK: - Netzwerk-Ausgabe (rank #1: OSC / ADM-OSC / sACN / Art-Net target config)

    /// Host + port (+ universe) per network output, so the founder can point OSC/ADM at
    /// Resolume/TouchDesigner/MadMapper and sACN/Art-Net at the right light node instead
    /// of only localhost/broadcast. Values persist (UserDefaults in each sender) and a
    /// live edit reconnects immediately. Flat rows (no card-in-card, Uncodixfy). The dot
    /// = whether that output is currently sending (low-frequency isActive — freeze-safe).
    private var networkOutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network output").font(EchoelTheme.font(11, .bold)).foregroundStyle(EchoelTheme.dim)
            outputRow("OSC", active: osc.isActive, host: oscHost, port: oscPort)
            outputRow("ADM-OSC", active: admOSC.isActive, host: admHost, port: admPort)
            outputRow("sACN · Light", active: sacn.isActive, host: sacnHost, port: sacnPort,
                      universe: sacnUniverse, universeRange: 1...63_999)
            outputRow("Art-Net · Light", active: artNet.isActive, host: artNetHost, port: artNetPort,
                      universe: artNetUniverse, universeRange: 0...32_767)
            Text("Target IP + port per output — changes take effect immediately while the output is running. OSC/ADM default to 'localhost' (this device); for Resolume · TouchDesigner · MadMapper enter the target computer's IP. Art-Net sends by broadcast (255.255.255.255) to all LAN nodes by default.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private func outputRow(_ name: String, active: Bool, host: Binding<String>, port: Binding<Float>,
                           universe: Binding<Float>? = nil,
                           universeRange: ClosedRange<Float> = 1...63_999) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                // ⛔ THIS DOT WAS COLOUR-ONLY until 2026-07-29: `fill(active ? accent : border)`
                // on an identical 7 pt circle, no text, no label. Whether an Art-Net / sACN /
                // OSC output is actually live was green-versus-grey and nothing else — so for
                // a red-green colour-blind operator (~8% of men) it was unreadable, on the one
                // surface where reading it wrong means a silent show. `differentiateWithoutColor`
                // is used ZERO times in this codebase, so there was no fallback anywhere.
                //
                // Fixed by SHAPE, not by a setting: filled when live, hollow ring when not.
                // That is the idiom `BioStripView` already uses for its driving/live/idle dot,
                // and it is unconditional — it helps everyone, including someone glancing at a
                // dim laptop screen in a venue, rather than only users who found a toggle.
                Group {
                    if active {
                        Circle().fill(EchoelTheme.accent)
                    } else {
                        Circle().strokeBorder(EchoelTheme.border, lineWidth: 1.5)
                    }
                }
                .frame(width: 7, height: 7)
                // No-op today: the `.ignore` below already discards this subtree. Kept so a
                // later switch to `.combine` stays correct rather than silently reading a
                // glyph name.
                .accessibilityHidden(true)
                Text(name).font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
            }
            // …and VoiceOver could not read the state at all, because a bare `Circle` carries
            // no label. The name and the state are announced as one element.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(active ? "sending" : "not sending")
            TextField("IP / host", text: host)
                .textFieldStyle(.plain)
                .font(EchoelTheme.font(13).monospacedDigit())
                .padding(.horizontal, 10).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.bg))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            HStack(spacing: 8) {
                EchoelValueField(label: "Port", value: port, range: 1...65_535, unit: "", decimals: 0)
                if let universe {
                    EchoelValueField(label: "Universe", value: universe, range: universeRange, unit: "", decimals: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) — network target")
    }

    // Manual bindings (the senders are @Environment @Observable references, not @Bindable).
    private var oscHost: Binding<String> { Binding(get: { osc.host }, set: { osc.host = $0 }) }
    private var oscPort: Binding<Float> { Binding(get: { Float(osc.port) }, set: { osc.port = Self.clampPort($0) }) }
    private var admHost: Binding<String> { Binding(get: { admOSC.host }, set: { admOSC.host = $0 }) }
    private var admPort: Binding<Float> { Binding(get: { Float(admOSC.port) }, set: { admOSC.port = Self.clampPort($0) }) }
    private var sacnHost: Binding<String> { Binding(get: { sacn.host }, set: { sacn.host = $0 }) }
    private var sacnPort: Binding<Float> { Binding(get: { Float(sacn.port) }, set: { sacn.port = Self.clampPort($0) }) }
    private var sacnUniverse: Binding<Float> {
        Binding(get: { Float(sacn.universe) }, set: { sacn.universe = min(max(Int($0.rounded()), 1), 63_999) })
    }
    private var artNetHost: Binding<String> { Binding(get: { artNet.host }, set: { artNet.host = $0 }) }
    private var artNetPort: Binding<Float> { Binding(get: { Float(artNet.port) }, set: { artNet.port = Self.clampPort($0) }) }
    private var artNetUniverse: Binding<Float> {
        Binding(get: { Float(artNet.universe) }, set: { artNet.universe = min(max(Int($0.rounded()), 0), 32_767) })
    }
    private static func clampPort(_ v: Float) -> UInt16 { UInt16(min(max(Int(v.rounded()), 1), 65_535)) }

    // MARK: - Licht (L1: Grand Master + Blackout, drives Art-Net AND sACN)

    private var lichtSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Light").font(EchoelTheme.font(11, .bold)).foregroundStyle(EchoelTheme.dim)
            HStack(spacing: 10) {
                EchoelValueField(label: "Master", value: grandMasterBinding,
                                 range: 0...1, unit: "", decimals: 2)
                Button {
                    let newState = !artNet.blackout
                    artNet.blackout = newState
                    sacn.blackout = newState
                } label: {
                    Text(artNet.blackout ? "Blackout ON" : "Blackout")
                        .font(EchoelTheme.font(13, .semibold))
                        .foregroundStyle(artNet.blackout ? EchoelTheme.onPrimary : EchoelTheme.text)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(artNet.blackout ? EchoelTheme.danger : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(artNet.blackout ? EchoelTheme.danger : EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(artNet.blackout ? "Blackout active — turn the light back on" : "Blackout — black out the light immediately")
            }
            Text("Master scales the brightness of all outgoing light data (Art-Net + sACN). Blackout goes dark instantly; the return fades back in flicker-free.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    /// One fader, both protocols — the patchbay is the "kleines Lichtpult".
    private var grandMasterBinding: Binding<Float> {
        Binding(
            get: { artNet.grandMaster },
            set: { v in
                artNet.grandMaster = v
                sacn.grandMaster = v
            }
        )
    }
    #endif

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("\(router.graph.routes.count) connections")
                .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
            Spacer(minLength: 0)
            Button { router.applyAllSuggestions() } label: {
                Label("Smart patch", systemImage: "wand.and.stars")
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
            }
            .buttonStyle(.plain)
            // Disabled-with-no-reason, the same one-channel defect as the status dot above.
            .accessibilityLabel(router.suggestions().isEmpty
                                ? "Smart patch — no suggestions available"
                                : "Smart patch")
            .disabled(router.suggestions().isEmpty)
            Button { router.clearAll() } label: {
                Text("Clear").font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 12).frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(router.graph.routes.isEmpty
                                ? "Clear — no routes to clear"
                                : "Clear all routes")
            .disabled(router.graph.routes.isEmpty)
        }
    }

    // MARK: - Source card

    private func sourceCard(_ src: SignalPort) -> some View {
        let sinks = router.graph.sinks.filter { $0.id != src.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: kindIcon(src.kind)).font(.system(size: 13)).foregroundStyle(EchoelTheme.accent)
                Text(src.name).font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                statusTag(src)
                Spacer(minLength: 0)
            }
            ForEach(sinks) { dst in
                destinationRow(src, dst)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private func destinationRow(_ src: SignalPort, _ dst: SignalPort) -> some View {
        let check = router.graph.check(sourceID: src.id, sinkID: dst.id)
        let compatible: Bool = { if case .ok = check { return true } else { return false } }()
        let connected = router.isConnected(src.id, dst.id)
        let conv = converterName(check)
        return Button {
            if compatible { router.toggle(src.id, dst.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: connected ? "checkmark.circle.fill" : (compatible ? "circle" : "minus.circle"))
                    .font(.system(size: 14))
                    .foregroundStyle(connected ? EchoelTheme.accent : (compatible ? EchoelTheme.dim : EchoelTheme.border))
                Image(systemName: kindIcon(dst.kind)).font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
                Text(dst.name).font(EchoelTheme.font(13)).foregroundStyle(compatible ? EchoelTheme.text : EchoelTheme.dim)
                if let conv { Text(conv).font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim) }
                Spacer(minLength: 0)
                statusTag(dst)
            }
            .frame(height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!compatible)
        .accessibilityLabel("\(src.name) to \(dst.name)")
        .accessibilityValue(connected ? "connected" : (compatible ? "not connected" : "incompatible"))
    }

    // MARK: - Helpers

    private func converterName(_ check: SignalGraph.ConnectionCheck) -> String? {
        if case let .ok(cid) = check, let cid {
            return router.graph.catalog.converters.first { $0.id == cid }?.name
        }
        return nil
    }

    /// "soon" tag for roadmap transports — keeps the patchbay honest (no dead points).
    @ViewBuilder
    private func statusTag(_ port: SignalPort) -> some View {
        if port.transport.status == .roadmap {
            Text("soon")
                .font(EchoelTheme.font(9, .semibold)).foregroundStyle(EchoelTheme.dim)
                .padding(.horizontal, 5).frame(height: 16)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
    }

    private func kindIcon(_ kind: SignalKind) -> String {
        switch kind {
        case .controlBio:     return "waveform.path.ecg"
        case .controlMusical: return "music.note"
        case .controlMacro:   return "dial.medium"
        case .note:           return "pianokeys"
        case .controlChange:  return "slider.horizontal.3"
        case .audio:          return "speaker.wave.2"
        case .light:          return "lightbulb"
        case .spatial:        return "move.3d"
        case .clock:          return "metronome"
        case .video:          return "film"
        case .visual:         return "sparkles"
        }
    }
}
#endif

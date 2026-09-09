// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import SwiftUI

/// One voice: name, versions, attribution, and the Play / Install controls.
struct VoiceRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: SamplePlayer

    let voice: VoicePackage
    let language: LanguagePackage

    private var installed: InstalledVoice? { model.installedVoice(for: voice) }
    private var state: VoiceState { model.state(of: voice) }
    private var attribution: VoiceAttribution {
        VoiceMetadataStore.attribution(voiceId: voice.id, installedDirectory: installed?.directory)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(voice.name)
                        .font(.title3.weight(.semibold))
                    if let accent = voice.accent {
                        Text(accent)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let installed {
                        Text(model.isRegistered(voice) ? "Available to VoiceOver" : "Registering with the system…")
                            .font(.caption)
                            .foregroundStyle(model.isRegistered(voice) ? .green : .secondary)
                            .accessibilityLabel(model.isRegistered(voice) ? "Available to VoiceOver" : "Registering with the system")
                        let _ = installed
                    }
                }
                details
                attributionView
                controls
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowLabel)
    }

    private var rowLabel: String {
        var parts = [voice.name]
        if let accent = voice.accent { parts.append(accent) }
        parts.append(statusDescription)
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let installed {
                Text("Installed version \(installed.fullVersionString) · Available \(voice.version.description)")
                if installed.gender != .unknown {
                    Text(installed.gender == .female ? "Female voice" : "Male voice")
                }
            } else {
                Text("Version \(voice.version.description)")
            }
            if let region = voice.ctry2code, let country = Locale.current.localizedString(forRegionCode: region) {
                Text("Region: \(country)")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var attributionView: some View {
        let attribution = self.attribution
        VStack(alignment: .leading, spacing: 2) {
            if !attribution.creators.isEmpty {
                Text("Creators: \(attribution.creators.joined(separator: ", "))")
            }
            if let copyright = attribution.copyright {
                Text(copyright)
            }
            if let name = attribution.licenseName {
                if let url = attribution.licenseURL {
                    Link("License: \(name)", destination: url)
                } else {
                    Text("License: \(name)")
                }
            } else if let url = attribution.licenseURL {
                Link("License", destination: url)
            } else if attribution.attributionText == nil {
                Text("License: see the voice's package for details")
                    .foregroundStyle(.secondary)
            }
            if let homepage = attribution.homepage {
                Link("Website", destination: homepage)
            }
            if let text = attribution.attributionText {
                Text(text)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                model.toggleSample(for: voice, in: language)
            } label: {
                if player.playingVoiceId == voice.id {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .disabled(!model.canPlaySample(voice) || state.isBusy)
            .help(installed == nil ? "Play the demo clip" : "Speak a sample with this voice")

            switch state {
            case .notInstalled:
                Button("Install") { model.install(voice, in: language) }
                    .keyboardShortcut(.defaultAction)
            case .installed:
                Button("Uninstall") { model.requestRemoval(of: voice, in: language) }
            case .updateAvailable:
                Button("Update") { model.install(voice, in: language) }
                Button("Uninstall") { model.requestRemoval(of: voice, in: language) }
            case .downloading(let packName, let fraction):
                ProgressView(value: fraction ?? 0, total: 1) {
                    Text("Downloading \(packName)…")
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 260)
                .accessibilityLabel("Downloading \(packName)")
                .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "in progress")
                Button("Cancel") { model.cancel(voice) }
            case .installing(let packName):
                ProgressView()
                    .controlSize(.small)
                Text("Installing \(packName)…")
                Button("Cancel") { model.cancel(voice) }
            case .removing:
                ProgressView()
                    .controlSize(.small)
                Text("Removing…")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button("Retry") { model.clearFailure(voice); model.install(voice, in: language) }
                Button("Dismiss") { model.clearFailure(voice) }
            }
            Spacer()
        }
    }

    private var statusDescription: String {
        switch state {
        case .notInstalled: return "not installed"
        case .installed: return "installed"
        case .updateAvailable: return "installed, update available"
        case .downloading(let name, let fraction):
            return "downloading \(name)" + (fraction.map { ", \(Int($0 * 100)) percent" } ?? "")
        case .installing(let name): return "installing \(name)"
        case .removing: return "removing"
        case .failed(let message): return "failed: \(message)"
        }
    }
}

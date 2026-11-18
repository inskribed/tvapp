import UIKit
import SwiftUI
import OrkaCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                playlistsSection
                librarySection
                sportsSection
                appearanceSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(OrkaBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    ScrollView {
                        AddPlaylistForm { showAdd = false }
                            .padding(16)
                    }
                    .background(OrkaBackground())
                    .navigationTitle("Add a playlist")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAdd = false }
                        }
                    }
                }
            }
            .task { await model.refreshAccount() }
        }
    }

    private var playlistsSection: some View {
        Section("Playlists") {
            ForEach(model.playlists) { p in
                Button {
                    if p.id != model.active?.id { model.setActive(p.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            Text(p.server).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if p.id == model.active?.id {
                            Text("In use").font(.caption).foregroundStyle(model.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Remove", role: .destructive) { model.removePlaylist(p.id) }
                }
            }
            Button("Add playlist") { showAdd = true }
            if let a = model.account {
                Text(accountLine(a)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func accountLine(_ a: AccountInfo) -> String {
        var parts: [String] = []
        if let s = a.status { parts.append(s) }
        if let e = a.expiresAt { parts.append("expires " + e.formatted(date: .abbreviated, time: .omitted)) }
        if let c = a.maxConnections { parts.append("\(c) connection\(c == 1 ? "" : "s") allowed") }
        return "Account: " + parts.joined(separator: "  ·  ")
    }

    /// Live TV loads by itself. Movies and Series wait until you ask for them.
    private var librarySection: some View {
        Section {
            LabeledContent("Live TV") {
                switch model.syncStates[.live] ?? .idle {
                case .syncing: Text("Syncing…").foregroundStyle(.secondary)
                case .failed(let message): Text(message).foregroundStyle(.red).lineLimit(1)
                case .idle:
                    if let at = model.liveSyncedAt {
                        Text(at.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
                    } else {
                        Text("Not synced").foregroundStyle(.secondary)
                    }
                }
            }
            Button("Sync Live TV now") { Task { await model.refreshLive() } }
                .disabled(model.syncStates[.live] == .syncing)
            NavigationLink {
                ChannelGroupsView()
            } label: {
                LabeledContent("Channel groups") {
                    let total = model.groupsWithChannels.count
                    let shown = model.groupsWithChannels.filter { model.isGroupVisible($0.id) }.count
                    Text(shown == total ? "All shown" : "\(shown) of \(total) shown")
                }
            }
            .disabled(model.allChannelCount == 0)
            LabeledContent("Movies") { Text("Coming soon").foregroundStyle(.secondary) }
            LabeledContent("Series") { Text("Coming soon").foregroundStyle(.secondary) }
        } header: {
            Text("Library")
        } footer: {
            Text("Orka only loads Live TV when it opens, so you get to your games fast. Movies and Series will sync only when you choose to.")
        }
    }

    private var sportsSection: some View {
        Section("Sports") {
            Toggle("Show scores", isOn: Binding(get: { model.showScores }, set: { model.setShowScores($0) }))
            NavigationLink {
                TeamPickerView()
            } label: {
                HStack {
                    Text("My teams")
                    Spacer()
                    Text(model.favoriteTeams.isEmpty ? "None yet" : "\(model.favoriteTeams.count) selected")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Accent color")
                    Spacer()
                    Text(model.preset.name).foregroundStyle(model.accent)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(Brand.presets) { p in
                        Button {
                            model.setAccent(p)
                        } label: {
                            Circle()
                                .fill(p.color)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if p.name == model.accentName {
                                        Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(.black.opacity(0.75))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p.name)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// The brand lives here (not on Home): logo, name and version on a glass card.
    private var aboutSection: some View {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return Section("About") {
            VStack(spacing: 10) {
                ZStack {
                    // Soft teal-and-lime glow behind the mark.
                    Circle()
                        .fill(RadialGradient(colors: [model.accent.opacity(0.45), .clear], center: .center, startRadius: 4, endRadius: 70))
                        .frame(width: 140, height: 140)
                    Circle()
                        .fill(RadialGradient(colors: [model.highlight.opacity(0.18), .clear], center: .bottomLeading, startRadius: 2, endRadius: 60))
                        .frame(width: 140, height: 140)
                    Image("orka_mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 81)
                        .shadow(color: model.accent.opacity(0.5), radius: 12)
                }
                .frame(height: 112)
                Text("Orka")
                    .font(.largeTitle.bold())
                Text("Live TV, your guide and every game, in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Version \(v) (\(b))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .accessibilityElement(children: .combine)
        }
    }
}

struct TeamPickerView: View {
    @Environment(AppModel.self) private var model
    @State private var league: League = .nfl
    @State private var search = ""

    private var shown: [Team] {
        let all = model.teams[league] ?? []
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return all }
        return all.filter { $0.displayName.lowercased().contains(q) || $0.abbr.lowercased() == q }
    }

    var body: some View {
        List {
            Section {
                Picker("League", selection: $league) {
                    ForEach(League.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                if let error = model.teamsError, model.teams[league] == nil {
                    Text(error).foregroundStyle(.secondary)
                } else if model.teams[league] == nil {
                    HStack(spacing: 10) { ProgressView(); Text("Loading teams…").foregroundStyle(.secondary) }
                } else if shown.isEmpty {
                    Text("No teams match \"\(search)\".").foregroundStyle(.secondary)
                } else {
                    ForEach(shown) { team in
                        Button {
                            model.toggleTeam(team)
                        } label: {
                            HStack(spacing: 12) {
                                TeamLogo(team: team, size: 30)
                                Text(team.displayName)
                                Spacer()
                                Image(systemName: model.isFavoriteTeam(team) ? "star.fill" : "star")
                                    .foregroundStyle(model.isFavoriteTeam(team) ? Brand.star : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(OrkaBackground())
        .navigationTitle("My teams")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a team")
        .task(id: league) { await model.loadTeams(league) }
    }
}

/// Xtream Codes login. Used on first launch and from Settings.
struct AddPlaylistForm: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void = {}

    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            field("Name (optional)", text: $name)
            field("Server URL", text: $server, placeholder: "http://example.com:8080", keyboard: .URL)
            field("Username", text: $username)
            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.footnote).foregroundStyle(.secondary)
                SecureField("Password", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button {
                submit()
            } label: {
                Text(busy ? "Connecting…" : "Save and connect").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(busy)
            if let error {
                Text(error).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            TextField(placeholder.isEmpty ? title : placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func submit() {
        if busy { return }
        busy = true
        error = nil
        Task {
            let result = await model.addPlaylist(name: name, server: server, username: username, password: password)
            busy = false
            if let result { error = result } else { onDone() }
        }
    }
}

/// First launch, before there's a playlist.
struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("orka_mark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 95)
                    .padding(.top, 48)
                Text("Welcome to Orka").font(.largeTitle.bold())
                Text("Add your Xtream Codes login to start watching. Your channels load once, then Orka opens straight to your games.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                AddPlaylistForm()
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OrkaBackground())
    }
}

/// Show or hide whole channel groups. Hidden groups disappear from the Guide, Search and the
/// channels suggested for games. Favorites and recently watched aren't affected.
struct ChannelGroupsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        let groups = model.groupsWithChannels
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = q.isEmpty ? groups : groups.filter {
            ChannelSearch.matches(nameWords: ChannelSearch.words($0.name), queryWords: ChannelSearch.words(q))
        }
        List {
            if q.isEmpty {
                let prefixes = model.groupPrefixes()
                if !prefixes.isEmpty {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                            ForEach(prefixes, id: \.tag) { p in
                                prefixChip(p.tag, ids: p.ids)
                            }
                        }
                        .padding(.vertical, 6)
                    } header: {
                        Text("By country")
                    } footer: {
                        Text("Tap a tag to show or hide all of its groups. To keep only one country, choose Hide all from the menu, then tap its tag.")
                    }
                }
            }
            Section(q.isEmpty ? "Groups" : "Matching groups") {
                ForEach(shown) { c in
                    Toggle(isOn: Binding(
                        get: { model.isGroupVisible(c.id) },
                        set: { model.setGroups([c.id], visible: $0) }
                    )) {
                        HStack {
                            Text(c.name).lineLimit(1)
                            Spacer()
                            Text("\(model.library.counts[c.id] ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(OrkaBackground())
        .navigationTitle("Channel groups")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a group")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Show all") { model.setGroups(groups.map(\.id), visible: true) }
                    Button("Hide all", role: .destructive) { model.setGroups(groups.map(\.id), visible: false) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    /// Filled = all shown, outlined = some shown, dim = all hidden.
    private func prefixChip(_ tag: String, ids: [String]) -> some View {
        let visibleCount = ids.filter { model.isGroupVisible($0) }.count
        let all = visibleCount == ids.count
        let none = visibleCount == 0
        return Button {
            model.setGroups(ids, visible: none)
        } label: {
            VStack(spacing: 2) {
                Text(tag).font(.headline)
                Text("\(ids.count) group\(ids.count == 1 ? "" : "s")").font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(all ? Color.black : (none ? Color.secondary : Color.primary))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(all ? model.accent : Color.white.opacity(none ? 0.04 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(none ? Color.clear : model.accent.opacity(all ? 0 : 0.8), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tag), \(none ? "hidden" : (all ? "shown" : "partly shown"))")
    }
}

import SwiftUI
import AppKit
import CryptoKit

@main
struct DuplicateFinderApp: App {
    var body: some Scene {
        WindowGroup("Duplicate Finder") {
            ContentView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Folder…") {
                    NotificationCenter.default.post(name: .duplicateFinderChooseFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let duplicateFinderChooseFolder = Notification.Name("DuplicateFinderChooseFolder")
}

struct DuplicateItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let size: Int64
}

struct DuplicateGroup: Identifiable {
    let id: String
    let hash: String
    let size: Int64
    let items: [DuplicateItem]

    var wastedBytes: Int64 {
        max(0, Int64(items.count - 1)) * size
    }
}

@MainActor
final class DuplicateFinderModel: ObservableObject {
    @Published var selectedFolder: URL?
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var progress = 0.0
    @Published var status = "Choose a folder to begin."
    @Published var selectedURLs: Set<URL> = []
    @Published var errorMessage: String?

    private let fileManager = FileManager.default

    var totalDuplicateFiles: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    var duplicateBytes: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to scan"
        panel.prompt = "Scan"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url
            groups = []
            selectedURLs = []
            status = "Ready to scan \(url.lastPathComponent)."
            errorMessage = nil
        }
    }

    func scan() {
        guard let folder = selectedFolder, !isScanning else { return }
        groups = []
        selectedURLs = []
        errorMessage = nil
        isScanning = true
        progress = 0
        status = "Collecting files…"

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let files = try Self.collectRegularFiles(in: folder)
                await MainActor.run {
                    self?.status = "Analyzing \(files.count.formatted()) files…"
                    self?.progress = 0.05
                }

                let duplicateGroups = try Self.findDuplicates(files) { done, total in
                    let p = total == 0 ? 1.0 : 0.05 + (Double(done) / Double(total)) * 0.95
                    Task { @MainActor [weak self] in
                        self?.progress = p
                        self?.status = "Analyzing file \(done.formatted()) of \(total.formatted())…"
                    }
                }

                await MainActor.run {
                    self?.groups = duplicateGroups
                    self?.isScanning = false
                    self?.progress = 1
                    self?.status = duplicateGroups.isEmpty
                        ? "No exact duplicates found."
                        : "Found \(duplicateGroups.count) duplicate groups."
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.isScanning = false
                    self?.status = "Scan cancelled."
                }
            } catch {
                await MainActor.run {
                    self?.isScanning = false
                    self?.status = "Scan failed."
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func toggleSelection(_ url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    func selectAllButFirst(in group: DuplicateGroup) {
        for item in group.items.dropFirst() {
            selectedURLs.insert(item.url)
        }
    }

    func clearSelection() {
        selectedURLs.removeAll()
    }

    func moveSelectedToTrash() {
        let targets = selectedURLs.filter { url in
            groups.contains(where: { $0.items.contains(where: { $0.url == url }) })
        }
        guard !targets.isEmpty else { return }

        var failed: [String] = []
        for url in targets {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }

        selectedURLs.removeAll()
        groups = groups.compactMap { group in
            let remaining = group.items.filter { !targets.contains($0.url) }
            guard remaining.count > 1 else { return nil }
            return DuplicateGroup(id: group.id, hash: group.hash, size: group.size, items: remaining)
        }

        if failed.isEmpty {
            status = "Moved \(targets.count) file(s) to the Trash."
        } else {
            errorMessage = "Could not move: \(failed.joined(separator: ", "))"
        }
    }

    private static func collectRegularFiles(in folder: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: options) else {
            throw NSError(domain: "DuplicateFinder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read the selected folder."])
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { continue }
                if values.isRegularFile == true { urls.append(url) }
            } catch {
                continue
            }
        }
        return urls
    }

    private static func findDuplicates(_ files: [URL], progress: @escaping @Sendable (Int, Int) -> Void) throws -> [DuplicateGroup] {
        var bySize: [Int64: [URL]] = [:]
        for url in files {
            do {
                let size = try fileSize(url)
                bySize[size, default: []].append(url)
            } catch {
                continue
            }
        }

        let candidates = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        var buckets: [String: [DuplicateItem]] = [:]
        var done = 0
        let total = candidates.count
        for url in candidates {
            if Task.isCancelled { throw CancellationError() }
            do {
                let size = try fileSize(url)
                let hash = try sha256(of: url)
                buckets[hash, default: []].append(DuplicateItem(id: url, url: url, size: size))
            } catch {
                // Ignore unreadable files.
            }
            done += 1
            progress(done, total)
        }

        return buckets.compactMap { hash, items in
            guard items.count > 1 else { return nil }
            let sorted = items.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            return DuplicateGroup(id: hash, hash: hash, size: sorted[0].size, items: sorted)
        }
        .sorted {
            if $0.wastedBytes != $1.wastedBytes { return $0.wastedBytes > $1.wastedBytes }
            return $0.items[0].url.path < $1.items[0].url.path
        }
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

}

struct ContentView: View {
    @StateObject private var model = DuplicateFinderModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .duplicateFinderChooseFolder)) { _ in
            model.chooseFolder()
        }
        .alert("Scan Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 50, height: 50)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("Duplicate Finder")
                    .font(.system(size: 24, weight: .bold))
                Text(model.selectedFolder?.path ?? "No folder selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            Button("Choose Folder…") { model.chooseFolder() }
                .keyboardShortcut("o", modifiers: [.command])

            Button {
                model.scan()
            } label: {
                Label(model.isScanning ? "Scanning…" : "Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedFolder == nil || model.isScanning)
        }
        .padding(18)
    }

    private var content: some View {
        Group {
            if model.groups.isEmpty && !model.isScanning {
                emptyState
            } else {
                resultsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(model.selectedFolder == nil ? "Find duplicate files" : "Ready to scan")
                .font(.title2.weight(.semibold))
            Text(model.selectedFolder == nil
                 ? "Choose a folder. Duplicate Finder compares exact file contents locally on your Mac."
                 : "Start a scan to find exact duplicates in this folder.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            if model.selectedFolder == nil {
                Button("Choose Folder…") { model.chooseFolder() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(40)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            if model.isScanning {
                ProgressView(value: model.progress)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
            }
            List {
                ForEach(model.groups) { group in
                    DuplicateGroupRow(group: group, model: model)
                }
            }
            .listStyle(.inset)
            .padding(.top, 6)
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if model.groups.isEmpty {
                    Text(model.status)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(model.groups.count) groups • \(model.totalDuplicateFiles) files • \(ByteCountFormatter.string(fromByteCount: model.duplicateBytes, countStyle: .file)) recoverable")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !model.selectedURLs.isEmpty {
                Button("Clear Selection") { model.clearSelection() }
                Button {
                    model.moveSelectedToTrash()
                } label: {
                    Label("Move to Trash (\(model.selectedURLs.count))", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @ObservedObject var model: DuplicateFinderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.items.count) identical files")
                        .font(.headline)
                    Text("Each file: \(ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file)) • Wasted: \(ByteCountFormatter.string(fromByteCount: group.wastedBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Keep First") { model.selectAllButFirst(in: group) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { model.selectedURLs.contains(item.url) },
                        set: { _ in model.toggleSelection(item.url) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                    FileIcon(url: item.url)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.url.lastPathComponent)
                            .fontWeight(index == 0 ? .semibold : .regular)
                            .lineLimit(1)
                        Text(item.url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if index == 0 {
                        Text("Keep")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.vertical, 6)
    }
}

struct FileIcon: View {
    let url: URL

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 28, height: 28)
    }

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

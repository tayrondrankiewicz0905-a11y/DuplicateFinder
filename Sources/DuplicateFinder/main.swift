import SwiftUI
import AppKit
import Foundation
import CryptoKit
import UniformTypeIdentifiers

struct DuplicateFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let hash: String

    var name: String {
        url.lastPathComponent
    }

    var path: String {
        url.path
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let hash: String
    let files: [DuplicateFile]

    var wastedBytes: Int64 {
        guard files.count > 1 else { return 0 }
        return files.dropFirst().reduce(0) { $0 + $1.size }
    }

    var wastedSize: String {
        ByteCountFormatter.string(fromByteCount: wastedBytes, countStyle: .file)
    }
}

@MainActor
final class DuplicateFinderModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var status = "Choose a folder to scan."
    @Published var errorMessage: String?
    @Published var selectedPaths: Set<String> = []

    var duplicateCount: Int {
        groups.reduce(0) { $0 + $1.files.count }
    }

    var groupCount: Int {
        groups.count
    }

    var reclaimableBytes: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }

    var reclaimableSize: String {
        ByteCountFormatter.string(fromByteCount: reclaimableBytes, countStyle: .file)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to scan"
        panel.message = "Duplicate Finder searches this folder and its subfolders."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let folder = panel.url {
            scan(folder)
        }
    }

    func scan(_ folder: URL) {
        guard !isScanning else { return }

        isScanning = true
        progress = 0
        groups = []
        selectedPaths.removeAll()
        errorMessage = nil
        status = "Collecting files…"

        // Everything is intentionally kept on the MainActor.
        // This avoids Swift 6 concurrency/capture errors and keeps the project
        // simple and reliable for the first version.
        Task { @MainActor in
            do {
                let files = try Self.collectRegularFiles(in: folder)

                if files.isEmpty {
                    status = "No files found."
                    progress = 1
                    isScanning = false
                    return
                }

                status = "Checking \(files.count.formatted()) files…"
                progress = 0.1

                var bySize: [Int64: [URL]] = [:]

                for (index, url) in files.enumerated() {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    let size = Int64(values.fileSize ?? 0)
                    bySize[size, default: []].append(url)

                    if index % 100 == 0 {
                        progress = 0.1 + (Double(index) / Double(files.count)) * 0.2
                        status = "Checking file \(index.formatted()) of \(files.count.formatted())…"
                        await Task.yield()
                    }
                }

                let candidates = bySize.values.filter { $0.count > 1 }
                let candidateCount = candidates.reduce(0) { $0 + $1.count }

                if candidateCount == 0 {
                    status = "No exact duplicates found."
                    progress = 1
                    isScanning = false
                    return
                }

                status = "Comparing \(candidateCount.formatted()) matching-size files…"

                var hashGroups: [String: [DuplicateFile]] = [:]
                var processed = 0

                for urls in candidates {
                    for url in urls {
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        let size = Int64(values.fileSize ?? 0)

                        let hash = try Self.sha256(for: url)
                        let file = DuplicateFile(
                            url: url,
                            size: size,
                            hash: hash
                        )

                        hashGroups[hash, default: []].append(file)

                        processed += 1
                        progress = 0.3 + (Double(processed) / Double(candidateCount)) * 0.7
                        status = "Analyzing \(processed.formatted()) of \(candidateCount.formatted())…"

                        if processed % 10 == 0 {
                            await Task.yield()
                        }
                    }
                }

                groups = hashGroups.values
                    .filter { $0.count > 1 }
                    .map {
                        DuplicateGroup(
                            hash: $0.first?.hash ?? "",
                            files: $0.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                        )
                    }
                    .sorted {
                        if $0.wastedBytes != $1.wastedBytes {
                            return $0.wastedBytes > $1.wastedBytes
                        }
                        return $0.files.count > $1.files.count
                    }

                progress = 1
                isScanning = false

                if groups.isEmpty {
                    status = "No exact duplicates found."
                } else {
                    status = "Found \(groups.count) duplicate groups."
                    selectKeepFirst()
                }
            } catch {
                isScanning = false
                progress = 0
                status = "Scan failed."
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectKeepFirst() {
        selectedPaths.removeAll()

        for group in groups {
            for file in group.files.dropFirst() {
                selectedPaths.insert(file.path)
            }
        }
    }

    func clearSelection() {
        selectedPaths.removeAll()
    }

    func toggle(_ file: DuplicateFile) {
        if selectedPaths.contains(file.path) {
            selectedPaths.remove(file.path)
        } else {
            selectedPaths.insert(file.path)
        }
    }

    func deleteSelected() {
        let urls = groups
            .flatMap(\.files)
            .filter { selectedPaths.contains($0.path) }
            .map(\.url)

        guard !urls.isEmpty else { return }

        var failed = 0

        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed += 1
            }
        }

        selectedPaths.removeAll()

        if failed > 0 {
            errorMessage = "\(failed) file(s) could not be moved to the Trash."
        }

        status = "\(urls.count - failed) file(s) moved to Trash."
    }

    private static func collectRegularFiles(in folder: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in
                true
            }
        ) else {
            return []
        }

        var result: [URL] = []

        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: Set(keys))

                if values.isSymbolicLink == true {
                    continue
                }

                if values.isRegularFile == true {
                    result.append(url)
                }
            } catch {
                continue
            }
        }

        return result
    }

    private static func sha256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()

        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()

            if data.isEmpty {
                break
            }

            hasher.update(data: data)
        }

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@main
struct DuplicateFinderApp: App {
    var body: some Scene {
        WindowGroup("Duplicate Finder") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @StateObject private var model = DuplicateFinderModel()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if model.groups.isEmpty && !model.isScanning {
                emptyState
            } else {
                results
            }

            Divider()

            bottomBar
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text("Duplicate Finder")
                    .font(.system(size: 25, weight: .bold))

                Text(model.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if model.isScanning {
                ProgressView(value: model.progress)
                    .frame(width: 180)

                Text("\(Int(model.progress * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button("Choose Folder…") {
                model.chooseFolder()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isScanning)
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            Text("Find duplicate files")
                .font(.system(size: 28, weight: .bold))

            Text("Select a folder and Duplicate Finder will compare files\nby size and SHA-256 content hash.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Choose Folder") {
                model.chooseFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(model.groupCount) duplicate groups")
                    .font(.headline)

                Text("• \(model.duplicateCount) files")
                    .foregroundStyle(.secondary)

                Text("• \(model.reclaimableSize) recoverable")
                    .foregroundStyle(.secondary)

                Spacer()

                if model.isScanning {
                    ProgressView()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            List {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.files) { file in
                            FileRow(
                                file: file,
                                selected: model.selectedPaths.contains(file.path),
                                onToggle: {
                                    model.toggle(file)
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text("\(group.files.count) identical files")
                                .font(.headline)

                            Spacer()

                            Text("Wasted: \(group.wastedSize)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            if !model.groups.isEmpty {
                Button("Keep First") {
                    model.selectKeepFirst()
                }

                Button("Clear Selection") {
                    model.clearSelection()
                }
            }

            Spacer()

            Text("\(model.selectedPaths.count) selected")
                .foregroundStyle(.secondary)

            Button("Move Selected to Trash") {
                model.deleteSelected()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.selectedPaths.isEmpty || model.isScanning)
        }
        .padding(16)
    }
}

struct FileRow: View {
    let file: DuplicateFile
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { selected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(file.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

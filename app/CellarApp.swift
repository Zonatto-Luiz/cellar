// Cellar.app — a small window to start and stop Windows Steam in Cellar's bottles.
// All Wine work is done by the bundled `cellar` CLI (Contents/Resources/cellar).
import AppKit
import SwiftUI

extension Color {
    // Same burgundy gradient as the app icon (MakeIcon.swift).
    static let wine = Color(red: 0.55, green: 0.10, blue: 0.20)
    static let wineDark = Color(red: 0.30, green: 0.04, blue: 0.12)
    // Deeper than the window's traffic-light green and red so the buttons don't read as window controls.
    static let start = Color(red: 0.13, green: 0.52, blue: 0.30)
    static let stop = Color(red: 0.72, green: 0.20, blue: 0.18)
}

extension ShapeStyle where Self == LinearGradient {
    static var wineGradient: LinearGradient {
        LinearGradient(colors: [.wine, .wineDark], startPoint: .top, endPoint: .bottom)
    }
}

struct Bottle: Identifiable, Equatable {
    let id: String
    let runtime: String
    var running: Bool
    let hasSteam: Bool

    var runtimeLabel: String {
        switch runtime {
        case "cx": return "Wine · CodeWeavers source"
        case "staging": return "Wine Staging"
        case "devel": return "Wine Devel"
        case "gptk": return "Game Porting Toolkit"
        default: return runtime
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var busy: Set<String> = []
    @Published var error: String?
    @Published var loaded = false

    private let cli = Bundle.main.url(forResource: "cellar", withExtension: nil)
    private var timer: Timer?

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            let result = await run(["status"])
            guard result.status == 0 else { return }
            bottles = result.output.split(separator: "\n").compactMap { line in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count == 4 else { return nil }
                return Bottle(id: f[0], runtime: f[1], running: f[2] == "running", hasSteam: f[3] == "steam")
            }
            loaded = true
        }
    }

    func start(_ bottle: Bottle) { perform(bottle, ["steam", "run", bottle.id], failure: "Steam couldn't start") }
    func stop(_ bottle: Bottle) { perform(bottle, ["kill", bottle.id], failure: "Couldn't stop \(bottle.id)") }
    func openDrive(_ bottle: Bottle) { perform(bottle, ["open", bottle.id], failure: "Couldn't open drive C:") }

    private func perform(_ bottle: Bottle, _ args: [String], failure: String) {
        busy.insert(bottle.id)
        Task {
            let result = await run(args)
            if result.status != 0 { error = "\(failure)\n\n\(result.output)" }
            refresh()
            // Wine takes a moment to come up or wind down; keep the spinner until status catches up.
            try? await Task.sleep(for: .seconds(3))
            busy.remove(bottle.id)
            refresh()
        }
    }

    private func run(_ args: [String]) async -> (status: Int32, output: String) {
        guard let cli else { return (-1, "The cellar command is missing from the app bundle.") }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [cli.path] + args
            // Pass only what Wine and cellar need, so unrelated variables from whatever
            // launched the app (tokens, shell config) never reach Windows programs.
            let keep: Set<String> = ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "__CF_USER_TEXT_ENCODING"]
            let prefixes = ["LC_", "CELLAR_", "WINE", "MTL_", "ROSETTA_"]
            var env = ProcessInfo.processInfo.environment.filter { key, _ in
                keep.contains(key) || prefixes.contains { key.hasPrefix($0) }
            }
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (p.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do { try process.run() } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }
}

// Wine bottle silhouette: lip, long neck, sloped shoulders, straight body.
struct WineBottle: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        let lip = w * 0.22, neck = w * 0.17, body = w * 0.5, mid = x + w / 2
        let lipBottom = y + h * 0.06, shoulderTop = y + h * 0.3, shoulderBottom = y + h * 0.5, corner = w * 0.14
        var p = Path()
        p.move(to: CGPoint(x: mid - lip, y: y))
        p.addLine(to: CGPoint(x: mid + lip, y: y))
        p.addLine(to: CGPoint(x: mid + lip, y: lipBottom))
        p.addLine(to: CGPoint(x: mid + neck, y: lipBottom))
        p.addLine(to: CGPoint(x: mid + neck, y: shoulderTop))
        p.addCurve(to: CGPoint(x: mid + body, y: shoulderBottom),
                   control1: CGPoint(x: mid + neck, y: shoulderTop + h * 0.1),
                   control2: CGPoint(x: mid + body, y: shoulderTop + h * 0.06))
        p.addLine(to: CGPoint(x: mid + body, y: y + h - corner))
        p.addQuadCurve(to: CGPoint(x: mid + body - corner, y: y + h), control: CGPoint(x: mid + body, y: y + h))
        p.addLine(to: CGPoint(x: mid - body + corner, y: y + h))
        p.addQuadCurve(to: CGPoint(x: mid - body, y: y + h - corner), control: CGPoint(x: mid - body, y: y + h))
        p.addLine(to: CGPoint(x: mid - body, y: shoulderBottom))
        p.addCurve(to: CGPoint(x: mid - neck, y: shoulderTop),
                   control1: CGPoint(x: mid - body, y: shoulderTop + h * 0.06),
                   control2: CGPoint(x: mid - neck, y: shoulderTop + h * 0.1))
        p.addLine(to: CGPoint(x: mid - neck, y: lipBottom))
        p.addLine(to: CGPoint(x: mid - lip, y: lipBottom))
        p.closeSubpath()
        return p
    }
}

struct BottleRow: View {
    @EnvironmentObject var store: Store
    let bottle: Bottle

    var body: some View {
        HStack(spacing: 12) {
            WineBottle()
                .fill(.white)
                .frame(width: 10, height: 24)
                .frame(width: 32, height: 32)
                .background(.wineGradient, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.id.capitalized).font(.headline)
                Text(bottle.runtimeLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(bottle.running ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(bottle.running ? "Running" : "Stopped")
                    .font(.callout)
                    .foregroundStyle(bottle.running ? .primary : .secondary)
            }
            .frame(width: 80, alignment: .leading)
            Group {
                if store.busy.contains(bottle.id) {
                    ProgressView().controlSize(.small)
                } else if bottle.running {
                    Button("Stop") { store.stop(bottle) }
                        .buttonStyle(.borderedProminent)
                        .tint(.stop)
                } else {
                    Button("Start") { store.start(bottle) }
                        .buttonStyle(.borderedProminent)
                        .tint(.start)
                        .disabled(!bottle.hasSteam)
                        .help(bottle.hasSteam ? "Start Steam" : "Steam is not installed in this bottle")
                }
            }
            .frame(width: 64)
            Menu {
                Button("Open Drive C: in Finder") { store.openDrive(bottle) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 6)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            header
            bottleList
        }
        .frame(minWidth: 460, minHeight: 200)
        .ignoresSafeArea(edges: .top)
        .task { store.startPolling() }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
        ) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }

    // Burgundy band behind the traffic lights, matching the app icon.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "wineglass.fill")
            Text("Cellar").font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(.wineGradient)
    }

    private var bottleList: some View {
        Group {
            if store.loaded && store.bottles.isEmpty {
                ContentUnavailableView(
                    "No bottles yet",
                    systemImage: "wineglass",
                    description: Text("Create one in Terminal with: cellar bottle create steam")
                )
            } else {
                List(store.bottles) { BottleRow(bottle: $0) }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CellarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Cellar", id: "main") {
            ContentView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 260)
    }
}

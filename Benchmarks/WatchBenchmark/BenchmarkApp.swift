import SwiftUI

@main
struct DictionaryBenchmarkApp: App {
    var body: some Scene {
        WindowGroup { BenchmarkView() }
    }
}

struct BenchmarkView: View {
    @State private var status = "Preparing benchmark…"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dictionary benchmark").font(.headline)
                Text(status).font(.footnote)
            }.padding()
        }
        .task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LookupBenchmark.run()
                }.value
                status = result
            } catch {
                status = "Failed: \(error.localizedDescription)"
                print("BENCHMARK_ERROR \(error)")
            }
        }
    }
}

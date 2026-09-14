import Foundation
import Darwin
import WatchKit

struct LookupBenchmark {
    struct Query: Decodable, Sendable { let query: String; let expectedWord: String? }
    struct FileInfo: Decodable, Sendable { let bytes: Int64; let sha256: String }
    struct Fixture: Decodable, Sendable {
        let entries: Int
        let sourceSHA256: String
        let largestBlockBytes: Int
        let workloads: [String: [Query]]
        let files: [String: FileInfo]
    }
    enum Failure: Error { case missingArgument, mismatch(String), invalidFixture }

    static func run() throws -> String {
        let args = ProcessInfo.processInfo.arguments
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appending(path: "Fixtures")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "queries.json")))
        let output = documents.appending(path: "Results")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if args.contains("--validate-only") {
            let baseline = DictionaryStore(databaseURL: root.appending(path: "per-entry.sqlite"))
            var checked = 0
            for queries in fixture.workloads.values {
                for item in queries {
                    let reference = try baseline.lookup(item.query)
                    guard reference.entry?.word == item.expectedWord else { throw Failure.mismatch(item.query) }
                    for format in BenchmarkStore.Format.allCases {
                        let result = try BenchmarkStore(databaseURL: root.appending(path: "\(format.rawValue).sqlite"), format: format).lookup(item.query)
                        guard result.query == reference.query, result.entry == reference.entry,
                              result.suggestions == reference.suggestions else { throw Failure.mismatch(item.query) }
                        checked += 1
                    }
                }
            }
            try save(["validatedLookups": checked, "entries": fixture.entries, "sourceSHA256": fixture.sourceSHA256],
                     to: output.appending(path: "validation.json"))
            print("BENCHMARK_COMPLETE validation \(checked)")
            return "Validated \(checked) lookups across all three formats."
        }
        guard let i = args.firstIndex(of: "--format"), args.indices.contains(i + 1),
              let format = BenchmarkStore.Format(rawValue: args[i + 1]) else { throw Failure.missingArgument }
        let runID: String
        if let j = args.firstIndex(of: "--run-id"), args.indices.contains(j + 1) { runID = args[j + 1] }
        else { runID = UUID().uuidString }
        guard runID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { throw Failure.invalidFixture }
        let url = root.appending(path: "\(format.rawValue).sqlite")
        let store = BenchmarkStore(databaseURL: url, format: format)
        let production = DictionaryStore(databaseURL: url)
        let startMemory = footprint()
        var largestMemory = startMemory
        let startThermal = ProcessInfo.processInfo.thermalState.rawValue
        var checksum = 0
        var reports: [[String: Any]] = []
        for workload in ["random", "repeated", "aliases", "misses", "typos"] {
            guard let queries = fixture.workloads[workload] else { throw Failure.invalidFixture }
            for pass in 0..<3 {
                var durations: [Double] = []
                for item in queries {
                    // Match production: fresh SQLite connection and no application
                    // block cache for every lookup. OS file caching is not purged.
                    let measurement = try autoreleasepool { () throws -> (Double, Int) in
                        let before = DispatchTime.now().uptimeNanoseconds
                        let result = try format == .perEntry ? production.lookup(item.query) : store.lookup(item.query)
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - before) / 1_000_000
                        guard result.entry?.word == item.expectedWord else { throw Failure.mismatch(item.query) }
                        return (elapsed, (result.entry?.word.utf8.count ?? 0) + result.suggestions.count)
                    }
                    durations.append(measurement.0)
                    checksum += measurement.1
                    // Sample outside the timed region. This is observed process
                    // footprint, not a guaranteed allocation high-water mark.
                    largestMemory = max(largestMemory, footprint())
                }
                let sorted = durations.sorted()
                func percentile(_ fraction: Double) -> Double {
                    sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * fraction)) - 1))]
                }
                reports.append(["workload": workload, "pass": pass + 1, "count": durations.count,
                                "medianMS": percentile(0.5), "p95MS": percentile(0.95), "p99MS": percentile(0.99),
                                "meanMS": durations.reduce(0, +) / Double(durations.count), "maxMS": sorted.last!,
                                "samplesMS": durations])
            }
        }
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        #if targetEnvironment(simulator)
        let environment = "watchOS simulator — executes on Mac hardware"
        #else
        let environment = "physical Apple Watch"
        #endif
        let report: [String: Any] = [
            "format": format.rawValue, "runID": runID, "environment": environment, "machine": machine,
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "build": "Release -O wholemodule",
            "entries": fixture.entries, "fileBytes": fixture.files[format.rawValue]!.bytes,
            "sourceSHA256": fixture.sourceSHA256, "largestBlockBytes": fixture.largestBlockBytes,
            "thermalStart": startThermal, "thermalEnd": ProcessInfo.processInfo.thermalState.rawValue,
            "footprintStartBytes": startMemory, "footprintObservedMaxBytes": largestMemory,
            "footprintEndBytes": footprint(), "checksum": checksum,
            "timingScope": "normalization + open + SQL + inflate if applicable + JSON decode + presentation cleanup + close; excludes UI; no app cache; OS cache uncontrolled",
            "results": reports
        ]
        try save(report, to: output.appending(path: "\(runID)-\(format.rawValue).json"))
        print("BENCHMARK_COMPLETE \(runID) \(format.rawValue)")
        return "Finished \(format.rawValue).\nResults saved."
    }

    private static func save(_ report: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

import AppKit

@main
struct FinderTest {
    static func main() {
        let snapshot = WindowEnumerator.snapshot()
        let finderWins = snapshot.windows.filter { $0.pid == 776 }
        print("Finder windows in snapshot: \(finderWins.count)")
        for w in finderWins {
            print("  [\(w.id)] \"\(w.title)\" bounds: \(w.bounds)")
        }
    }
}

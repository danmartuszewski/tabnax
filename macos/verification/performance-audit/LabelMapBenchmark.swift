import Foundation
@main struct MapBenchmark {
    static func main() throws {
        var rows: [[String: Any]] = []
        for (alphabet,appCount,windowCount,tabCount) in [("abcdefghijklmnopqrstuvwxyz",10,20,0),("abcdefghijklmnopqrstuvwxyz",25,75,0),("abcdefghijklmnopqrstuvwxyz",50,150,0),("jkluionmhp",10,20,50),("jkluionmhp",25,75,300),("jkluionmhp",50,150,1000)] {
            let ids = (0..<appCount).map { _ in UUID() }
            let apps = ids.enumerated().map { i,id in Target(id:TargetID(process:id),app:"Application \(i)",title:"Application \(i)",bundleID:"test.app.\(i)") }
            let windows = (0..<windowCount).map { i in Target(id:TargetID(process:ids[i % appCount],window:UUID()),app:"Application \(i % appCount)",title:"Project \(i) editor document with a moderately long title") }
            let browser = UUID()
            let tabs = (0..<tabCount).map { i in Target(id:TargetID(process:browser,window:UUID()),app:"Browser",title:"Article \(i) with a realistic browser tab title and some additional text",owner:ids[0]) }
            let source = CatalogueSnapshot(windows:windows,apps:apps,tabs:tabs)
            var prefs = SelectionPreferences(); prefs.alphabet = alphabet
            var session = LabelSession(selection:prefs)
            _ = session.map(source)
            var samples: [Double] = []
            var checksum = 0
            for _ in 0..<100 {
                let start = ContinuousClock.now
                let mapped = session.map(source)
                let elapsed = start.duration(to:.now).components
                samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                checksum += mapped.apps.reduce(0) { $0 + $1.address.count } + mapped.tabs.reduce(0) { $0 + $1.foldAddress.count } + mapped.windows.reduce(0) { $0 + $1.foldAddress.count }
            }
            samples.sort()
            rows.append(["alphabet":alphabet,"apps":appCount,"windows":windowCount,"tabs":tabCount,"samples":samples.count,"median_ms":samples[50],"p95_ms":samples[95],"checksum":checksum])
        }
        let json = try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:json,as:UTF8.self))
    }
}

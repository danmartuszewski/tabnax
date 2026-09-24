import SafariServices
import Foundation
import TabnaxCore

private final class SafariTransport: @unchecked Sendable {
    static let shared = SafariTransport()
    private let lock = NSLock()
    private var peer: BrowserPeer?
    private var commands: [[String:Any]] = []
    func exchange(_ message: BrowserMessage) -> [String:Any] {
        lock.lock(); defer { lock.unlock() }
        if peer == nil {
            guard let socket = BrowserWire.connectSocket() else { return ["error":"Open Tabnax to connect"] }
            let next = BrowserPeer(socket); peer = next
            Thread.detachNewThread { [self,next] in
                while let data = next.read() {
                    guard let command = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { break }
                    lock.lock(); if commands.count < 32 { commands.append(command) }; lock.unlock()
                }
                lock.lock(); next.close(); if peer === next { peer = nil; commands.removeAll() }; lock.unlock()
            }
        }
        guard let data = try? JSONEncoder().encode(message) else { return ["error":"Invalid message"] }
        peer?.send(data)
        let outgoing = commands.filter { $0["connection"] as? String == message.connection }
        commands.removeAll { $0["connection"] as? String == message.connection }
        return ["commands":outgoing]
    }
}
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context:NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let result: [String:Any]
        if let object = request?.userInfo?[SFExtensionMessageKey],
           let data = try? JSONSerialization.data(withJSONObject:object),
           var message = try? JSONDecoder().decode(BrowserMessage.self,from:data) {
            message.browser = .safari
            if let checked = try? message.validated() { result = SafariTransport.shared.exchange(checked) }
            else { result = ["error":"Private or invalid browser data rejected"] }
        } else { result = ["error":"Invalid companion message"] }
        let response = NSExtensionItem(); response.userInfo = [SFExtensionMessageKey:result]
        context.completeRequest(returningItems:[response])
    }
}

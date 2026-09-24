import Foundation
import AppKit
import Darwin
import TabnaxCore

final class BrowserBridge: @unchecked Sendable {
    private let peers = Locked<[UUID:BrowserPeer]>([:])
    private let onMessage: @MainActor @Sendable (BrowserMessage,BrowserPeer) -> Void
    private let onDisconnect: @MainActor @Sendable (UUID) -> Void
    private var listener: Int32 = -1
    init(onMessage:@escaping @MainActor @Sendable (BrowserMessage,BrowserPeer)->Void,onDisconnect:@escaping @MainActor @Sendable (UUID)->Void) { self.onMessage=onMessage;self.onDisconnect=onDisconnect }
    func start() throws {
        let root = "/private/tmp/pl.tabnax"
        if mkdir(root,0o1777) == 0 { chmod(root,0o1777) }
        var rootInfo = stat()
        guard lstat(root,&rootInfo) == 0,rootInfo.st_mode & S_IFMT == S_IFDIR else { throw SettingsError.invalid("Invalid browser bridge directory.") }
        let userDirectory = root + "/\(getuid())"
        _ = mkdir(userDirectory,0o700)
        var userInfo = stat()
        guard lstat(userDirectory,&userInfo) == 0,userInfo.st_uid == getuid(),userInfo.st_mode & S_IFMT == S_IFDIR,userInfo.st_mode & 0o077 == 0 else { throw SettingsError.invalid("Browser bridge directory ownership is invalid.") }
        // Never remove another live instance's listener.
        if let existing = BrowserWire.connectSocket() { Darwin.close(existing); throw SettingsError.invalid("Another Tabnax instance owns the browser connection.") }
        var info = stat()
        if lstat(BrowserWire.socketPath,&info) == 0 {
            guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { throw SettingsError.invalid("Browser connection path is not a Tabnax socket.") }
            unlink(BrowserWire.socketPath)
        }
        listener = socket(AF_UNIX,SOCK_STREAM,0)
        guard listener >= 0 else { throw SettingsError.invalid("Could not create the local browser connection.") }
        var address = BrowserWire.address()
        let result = withUnsafePointer(to:&address) { p in p.withMemoryRebound(to:sockaddr.self,capacity:1) { bind(listener,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0,chmod(BrowserWire.socketPath,0o600) == 0,listen(listener,8) == 0 else { Darwin.close(listener); throw SettingsError.invalid("Could not open the local browser connection.") }
        signal(SIGPIPE,SIG_IGN)
        let executable = Bundle.main.executableURL?.path ?? ""
        let safari = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/TabnaxSafari.appex/Contents/MacOS/TabnaxSafari").path
        Thread.detachNewThread { [self] in
            while true {
                let fd = accept(listener,nil,nil); guard fd >= 0 else { break }
                var uid:uid_t = 0, gid:gid_t = 0
                guard getpeereid(fd,&uid,&gid) == 0,uid == getuid(),peers.withValue({ $0.count < 8 }) else { Darwin.close(fd); continue }
                var pid:pid_t = 0, length = socklen_t(MemoryLayout<pid_t>.size)
                guard getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&length) == 0 else { Darwin.close(fd); continue }
                let path = BrowserWire.processPath(pid)
                guard path == executable || path == safari else { Darwin.close(fd); continue }
                let peer = BrowserPeer(fd); peers.withValue { $0[peer.id] = peer }
                Thread.detachNewThread { [self] in
                    while let data = peer.read() {
                        guard let message = try? JSONDecoder().decode(BrowserMessage.self,from:data), let checked = try? message.validated() else { break }
                        Task { @MainActor [self] in onMessage(checked,peer) }
                    }
                    peer.close(); _ = peers.withValue { $0.removeValue(forKey:peer.id) }
                    Task { @MainActor [self] in onDisconnect(peer.id) }
                }
            }
        }
    }
    @MainActor static func installHost(for browser:BrowserID) throws {
        guard browser != .safari else { return }
        guard let executable = Bundle.main.executableURL else { throw SettingsError.invalid("Tabnax executable is unavailable.") }
        let manifest: [String:Any] = ["name":"pl.tabnax.bridge","description":"Tabnax browser tab switching","path":executable.path,"type":"stdio","allowed_extensions":["tabnax@tabnax.local"]]
        let data = try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys])
        for directory in hostDirectories(for:browser) {
            let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(directory,isDirectory:true)
            try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
            try data.write(to:base.appendingPathComponent("pl.tabnax.bridge.json"),options:.atomic)
        }
    }
    static func hostDirectories(for browser:BrowserID) -> [String] {
        // Zen builds have used both Gecko's Mozilla directory and their branded
        // directory. Register only this app's manifest in both known locations.
        let mozilla = "Library/Application Support/Mozilla/NativeMessagingHosts"
        return browser == .zen ? [mozilla,"Library/Application Support/zen/NativeMessagingHosts"] : [mozilla]
    }
    static func runNativeHost() {
        // Firefox/Zen launch hosts with the manifest path and the allowed extension ID.
        guard CommandLine.arguments.last == "tabnax@tabnax.local" else { return }
        let parentPath = BrowserWire.processPath(getppid())
        guard let end = parentPath.range(of:".app/"),let bundle = Bundle(path:String(parentPath[..<end.lowerBound])+".app")?.bundleIdentifier,
              let browser = BrowserID.allCases.first(where:{ $0.bundleID == bundle }),[BrowserID.zen,.firefox].contains(browser),
              let socket = BrowserWire.connectSocket() else { return }
        signal(SIGPIPE,SIG_IGN)
        let peer = BrowserPeer(socket)
        let replies = Thread {
            while let data = peer.read() { if !BrowserWire.write(data,to:STDOUT_FILENO) { break } }
            Darwin.exit(0)
        }
        replies.start()
        while let data = BrowserWire.read(from:STDIN_FILENO) {
            guard var message = try? JSONDecoder().decode(BrowserMessage.self,from:data) else { break }
            message.browser = browser
            guard let checked = try? message.validated(),let clean = try? JSONEncoder().encode(checked),BrowserWire.write(clean,to:socket) else { break }
        }
        peer.close()
    }
}

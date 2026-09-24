import Foundation

public struct BrowserTabRecord: Codable, Equatable, Sendable {
    public var id: String
    public var window: String
    public var title: String
    public var active: Bool
    public var focusedWindow: Bool
    public var incognito: Bool
    public var group: String?
    public var pinned: Bool?
    public init(id:String,window:String,title:String,active:Bool=false,focusedWindow:Bool=false,incognito:Bool=false,group:String?=nil,pinned:Bool?=nil) {
        self.id=id;self.window=window;self.title=title;self.active=active;self.focusedWindow=focusedWindow;self.incognito=incognito;self.group=group;self.pinned=pinned
    }
}
public struct BrowserMessage: Codable, Sendable {
    public var version: Int
    public var kind: String
    public var connection: String
    public var tabs: [BrowserTabRecord]?
    public var request: String?
    public var selected: Bool?
    public var error: String?
    public var browser: BrowserID?
    public init(version:Int=1,kind:String,connection:String,tabs:[BrowserTabRecord]?=nil,request:String?=nil,selected:Bool?=nil,error:String?=nil,browser:BrowserID?=nil) {
        self.version=version;self.kind=kind;self.connection=connection;self.tabs=tabs;self.request=request;self.selected=selected;self.error=error;self.browser=browser
    }
    public func validated() throws -> Self {
        guard version == 1, ["snapshot","result","hello"].contains(kind), UUID(uuidString:connection) != nil,
              (tabs?.count ?? 0) <= 4000 else { throw SettingsError.invalid("Invalid browser connection message.") }
        if let tabs {
            guard tabs.allSatisfy({ !$0.incognito && !$0.id.isEmpty && $0.id.count <= 256 && !$0.window.isEmpty && $0.window.count <= 256 && $0.title.count <= 4096 }), Set(tabs.map(\.id)).count == tabs.count else { throw SettingsError.invalid("Browser data was rejected: private, duplicate or invalid tab identity.") }
        }
        return self
    }
}

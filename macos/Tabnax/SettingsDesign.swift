import AppKit
import SwiftUI
import TabnaxCore

struct DesktopSpotlightPreview: NSViewRepresentable {
    var preferences: DesktopSpotlightPreferences
    var accent: NSColor
    var replayToken = 0
    func makeNSView(context: Context) -> DesktopSpotlightSampleView { DesktopSpotlightSampleView() }
    func updateNSView(_ view: DesktopSpotlightSampleView, context: Context) {
        view.configure(preferences: preferences, accent: accent, replayToken: replayToken)
    }
}

struct AnchorPicker: View {
    let selected: TabnaxCore.Anchor
    let onSelect: (TabnaxCore.Anchor) -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    private let symbols = ["arrow.up.left","arrow.up","arrow.up.right","arrow.left","scope","arrow.right","arrow.down.left","arrow.down","arrow.down.right"]
    var body: some View {
        VStack(spacing:8) {
            ForEach(0..<3,id:\.self) { row in
                HStack(spacing:8) {
                    ForEach(0..<3,id:\.self) { col in
                        let index = row*3+col, anchor = TabnaxCore.Anchor.allCases[index]
                        Button { onSelect(anchor) } label: {
                            Image(systemName:symbols[index]).font(.system(size:17,weight:.medium))
                                .foregroundStyle(selected == anchor ? Color.white : Color.secondary)
                                .frame(width:48,height:38)
                                .background(selected == anchor ? Color.accentColor : Color.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:6))
                                .overlay(RoundedRectangle(cornerRadius:6).stroke(selected == anchor ? Color.primary.opacity(0.35) : Color.primary.opacity(contrast == .increased ? 0.45 : 0.12),lineWidth:contrast == .increased ? 1.5 : 0.5))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help(anchor.title).accessibilityLabel(anchor.title)
                            .accessibilityValue(selected == anchor ? "Selected" : "")
                            .accessibilityAddTraits(selected == anchor ? .isSelected : [])
                            .accessibilityHint("Places the switcher at this position on the selected display.")
                            .accessibilityIdentifier("anchor-\(anchor.rawValue)")
                    }
                }
            }
        }.padding(17).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(Color.primary.opacity(0.13),lineWidth:0.5))
            .accessibilityElement(children:.contain).accessibilityLabel("Position on screen")
    }
}

struct PreviewWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors:scheme == .dark ? [Color(red:0.25,green:0.36,blue:0.39),Color(red:0.16,green:0.23,blue:0.28)] : [Color(red:0.85,green:0.90,blue:0.90),Color(red:0.67,green:0.75,blue:0.79)],startPoint:.topLeading,endPoint:.bottomTrailing)
    }
}

struct ThemeTile: View {
    let preset: ThemePreset
    let appearance: AppearancePreferences
    let dark: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var tokens: ThemeTokens { var value = appearance; value.preset = preset; return ThemeTokens.resolve(value,dark:dark) }
    private var selected: Bool { appearance.preset == preset }
    private var showsGlass: Bool { preset.surfaceStyle != .solid && !reduceTransparency && contrast != .increased }
    var body: some View {
        Button(action:action) {
            VStack(spacing:8) {
                thumbnail.accessibilityHidden(true)
                Text(preset.title).font(.system(size:12,weight:selected ? .semibold : .regular)).lineLimit(2)
                    .multilineTextAlignment(.center).frame(height:30)
            }.frame(maxWidth:.infinity).padding(10)
                .background(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).stroke(selected ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.45 : 0.10),lineWidth:selected || contrast == .increased ? 1.5 : 0.5))
                .overlay(alignment:.topTrailing) {
                    if selected {
                        Image(systemName:"checkmark.circle.fill").font(.system(size:12,weight:.semibold))
                            .foregroundStyle(Color.accentColor).background(Color(nsColor:.windowBackgroundColor),in:Circle()).padding(5).accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(preset.detail)
            .accessibilityLabel("\(preset.title) theme").accessibilityValue(selected ? String(localized:"Selected") : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(preset.detail).accessibilityIdentifier("theme-\(preset.rawValue)")
    }
    private var thumbnail: some View {
        ZStack {
            if showsGlass {
                LinearGradient(colors:[Color(red:0.33,green:0.62,blue:0.70),Color(red:0.62,green:0.56,blue:0.77),Color(red:0.79,green:0.70,blue:0.58)],startPoint:.topLeading,endPoint:.bottomTrailing)
                RoundedRectangle(cornerRadius:6)
                    .fill(Color(nsColor:NSColor(tokens.surface)).opacity(dark ? 0.78 : 0.72))
                    .overlay(RoundedRectangle(cornerRadius:6).stroke(.white.opacity(dark ? 0.30 : 0.65),lineWidth:1))
                    .padding(5)
            } else {
                Color(nsColor:NSColor(tokens.surface))
            }
            HStack(spacing:5) {
                VStack(alignment:.leading,spacing:4) {
                    Capsule().fill(Color(nsColor:NSColor(tokens.text)).opacity(0.60)).frame(width:18,height:3)
                    Capsule().fill(Color(nsColor:NSColor(tokens.secondary)).opacity(0.45)).frame(width:12,height:3)
                }
                Text("J").font(.system(size:12,weight:.semibold,design:.monospaced))
                    .foregroundStyle(Color(nsColor:NSColor(tokens.keyText)))
                    .padding(.horizontal,6).padding(.vertical,3)
                    .background(Color(nsColor:NSColor(tokens.key)),in:RoundedRectangle(cornerRadius:4))
                    .overlay(RoundedRectangle(cornerRadius:4).stroke(Color(nsColor:NSColor(tokens.secondary)).opacity(0.4),lineWidth:0.5))
            }
        }.frame(height:44).frame(maxWidth:.infinity).clipShape(RoundedRectangle(cornerRadius:7))
            .overlay(RoundedRectangle(cornerRadius:7).stroke(Color.primary.opacity(0.14),lineWidth:0.5))
    }
}

struct BrowserSettingsIcon: View {
    let browser: BrowserID
    // Cached per bundle identifier: urlForApplication(withBundleIdentifier:) is a synchronous
    // Launch Services lookup, otherwise repeated on every body evaluation (6 rows in Connections).
    private static var cache: [String: NSImage] = [:]
    private var icon: NSImage {
        if let cached = Self.cache[browser.bundleID] { return cached }
        let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier:browser.bundleID).map { IconCache.icon(forFile:$0.path) } ?? NSImage(systemSymbolName:"globe",accessibilityDescription:nil)!
        Self.cache[browser.bundleID] = resolved
        return resolved
    }
    var body: some View { Image(nsImage:icon).resizable().interpolation(.high).frame(width:28,height:28).accessibilityHidden(true) }
}

struct PositionPreview: View {
    let placement: Placement
    let mode: DisplayMode
    let appearance: AppearancePreferences
    let targets: [Target]
    var compact = false
    @Environment(\.colorScheme) private var scheme
    private var external: Bool { placement.display == .focused }
    private var displayName: String { external ? String(localized:"External display") : String(localized:"Main display") }
    private var caption: String { String(localized:"\(placement.anchor.title) · \(displayName) · \(Int(placement.inset)) pt edge spacing") }
    private var displayExplanation: String {
        switch placement.display {
        case .focused: String(localized:"The active window is on External in this example, so the switcher opens there.")
        case .pointer: String(localized:"The pointer is on Main in this example, so the switcher opens there.")
        case .main: String(localized:"The switcher opens on Main, wherever your active window or pointer is.")
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.bottom,spacing:14) {
                monitor(String(localized:"Main"),role:String(localized:"Pointer"),symbol:"cursorarrow",selected:!external,width:91,height:57)
                monitor(String(localized:"External"),role:String(localized:"Active window"),symbol:"macwindow",selected:external,width:115,height:70)
            }.frame(maxWidth:.infinity).padding(.top,4).padding(.bottom,10)
            GeometryReader { proxy in desktop(size:proxy.size) }
                .frame(height:compact ? 160 : 224).clipShape(RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.16),lineWidth:0.5))
                .accessibilityElement(children:.ignore).accessibilityLabel("Position preview")
                .accessibilityValue("\(mode.title) · \(caption)")
                .accessibilityIdentifier("position-desktop")
            Text(caption).font(.system(size:11,weight:.medium)).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("position-preview-caption")
            Text(displayExplanation).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text("Example displays · simplified layout").font(.system(size:11)).foregroundStyle(.secondary)
                .fixedSize(horizontal:false,vertical:true)
        }
    }
    private func monitor(_ name:String,role:String,symbol:String,selected:Bool,width:CGFloat,height:CGFloat) -> some View {
        VStack(spacing:4) {
            VStack(spacing:5) {
                HStack(spacing:3) {
                    Text(name).font(.system(size:11,weight:.medium))
                    if selected { Image(systemName:"checkmark.circle.fill").font(.system(size:10)) }
                }
                Label(role,systemImage:symbol).font(.system(size:9))
            }.frame(width:width,height:height)
                .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:5))
                .overlay(RoundedRectangle(cornerRadius:5).stroke(selected ? Color.accentColor : Color.primary.opacity(0.15),lineWidth:2))
            Rectangle().fill(selected ? Color.accentColor : Color.primary.opacity(0.18)).frame(width:30,height:3)
        }.foregroundStyle(selected ? Color.accentColor : .secondary)
            .accessibilityElement(children:.ignore).accessibilityLabel("\(name) display, \(role)")
            .accessibilityValue(selected ? "Selected" : "")
    }
    private func desktop(size:CGSize) -> some View {
        let screen = CGRect(x:0,y:0,width:1440,height:1440*size.height/max(1,size.width))
        let visible = CGRect(x:0,y:76,width:1440,height:screen.height-104)
        let frame = SwitcherGeometry.previewFrame(placement:placement,mode:mode,count:min(4,targets.count),screen:screen,visible:visible,canvas:size)
        let dark = appearance.source == .dark || (appearance.source == .system && scheme == .dark)
        let tokens = ThemeTokens.resolve(appearance,dark:dark)
        return ZStack(alignment:.topLeading) {
            PreviewWallpaper()
            HStack { Text("Tabnax"); Spacer(); Image(systemName:"clock") }.font(.system(size:8,weight:.medium)).padding(.horizontal,10).frame(height:18).background(.black.opacity(0.10))
            RoundedRectangle(cornerRadius:4).fill(.white.opacity(0.12)).overlay(alignment:.top) { Rectangle().fill(.white.opacity(0.25)).frame(height:1).padding(.top,12) }
                .overlay(RoundedRectangle(cornerRadius:4).stroke(.white.opacity(0.35),lineWidth:0.5))
                .frame(width:size.width*0.42,height:size.height*0.42).offset(x:size.width*0.23,y:size.height*0.28)
            HStack(spacing:8) { ForEach(["finder","folder.fill","safari","note.text"],id:\.self) { symbol in Image(systemName:symbol == "finder" ? "face.smiling" : symbol).font(.system(size:8)) } }
                .padding(.horizontal,9).padding(.vertical,4).background(.white.opacity(0.3),in:RoundedRectangle(cornerRadius:4))
                .position(x:size.width/2,y:size.height-12)
            if mode == .beacons {
                ForEach(0..<2,id:\.self) { index in
                    HStack { Text(targets.indices.contains(index) ? targets[index].app : String(localized:"Window")); Spacer(); Text(targets.indices.contains(index) ? targets[index].address.uppercased() : "").fontWeight(.bold) }
                        .font(.system(size:7)).padding(4).frame(width:85)
                        .background(Color(nsColor:NSColor(tokens.surface)),in:RoundedRectangle(cornerRadius:3))
                        .foregroundStyle(Color(nsColor:NSColor(tokens.text)))
                        .offset(x:15+CGFloat(index)*64,y:37+CGFloat(index)*45)
                }
            }
            MiniatureSwitcher(mode:mode,tokens:tokens,targets:Array((mode == .beacons ? Array(targets.dropFirst(2)) : targets).prefix(4)))
                .frame(width:frame.width,height:frame.height)
                .background(Color(nsColor:NSColor(tokens.surface)),in:RoundedRectangle(cornerRadius:5))
                .overlay(RoundedRectangle(cornerRadius:5).stroke(Color(nsColor:NSColor(tokens.secondary)).opacity(0.65),lineWidth:0.7))
                .shadow(color:.black.opacity(0.18),radius:5,y:3).clipped()
                .offset(x:frame.minX,y:frame.minY)
        }.frame(width:size.width,height:size.height)
    }
}

private struct MiniatureSwitcher: View {
    let mode: DisplayMode
    let tokens: ThemeTokens
    let targets: [Target]
    private var grid: Bool { mode == .lattice || mode == .canopy }
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text(mode == .beacons ? "Window bank" : "Windows, tabs & apps").font(.system(size:8,weight:.semibold))
            if targets.isEmpty { Text("No targets available").font(.system(size:7)) }
            else if grid {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:5) {
                    ForEach(targets.indices,id:\.self) { i in row(i).padding(3).background(Color(nsColor:NSColor(tokens.key)).opacity(0.12),in:RoundedRectangle(cornerRadius:3)) }
                }
            } else if mode == .fold {
                HStack(alignment:.top,spacing:5) {
                    VStack(alignment:.leading,spacing:8) { ForEach(targets.prefix(3),id:\.id) { target in Text(target.app + " " + target.foldAddress.prefix(1).uppercased()).lineLimit(1) } }.font(.system(size:7)).frame(width:38)
                    Divider()
                    VStack(spacing:5) { ForEach(targets.indices.filter { targets[$0].groupOwner == targets.first?.groupOwner }.prefix(2),id:\.self) { row($0) } }
                }
            } else {
                if mode == .relay { Text("↵ Return to previous").font(.system(size:7)).foregroundStyle(Color(nsColor:NSColor(tokens.selection))) }
                ForEach(0..<min(targets.count,mode == .beacons ? 2 : 4),id:\.self) { row($0) }
            }
            Spacer(minLength:0)
        }.padding(6).foregroundStyle(Color(nsColor:NSColor(tokens.text))).allowsHitTesting(false).accessibilityHidden(true)
    }
    private func row(_ index:Int) -> some View {
        HStack(spacing:4) {
            Image(systemName:"macwindow").font(.system(size:7))
            Text(targets[index].app).font(.system(size:7)).lineLimit(1)
            Spacer(minLength:0)
            Text((mode == .fold || mode == .canopy ? targets[index].foldAddress : targets[index].address).uppercased())
                .font(.system(size:7,weight:.semibold,design:.monospaced)).padding(2)
                .background(Color(nsColor:NSColor(tokens.key)),in:RoundedRectangle(cornerRadius:2)).foregroundStyle(Color(nsColor:NSColor(tokens.keyText)))
        }
    }
}

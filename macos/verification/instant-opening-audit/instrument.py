"""Add stage counters to a temporary presenter copy; never edit application source."""
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text()
replacements = {
    '        cancelPreparation()\n        Trace.log.info("perf: present entry': '        let auditStart = CACurrentMediaTime()\n        func auditMark(_ name: String) { OpeningAudit.stages[name] = (CACurrentMediaTime()-auditStart)*1000 }\n        OpeningAudit.stages = [:]\n        OpeningAudit.frameSizes = []\n        cancelPreparation()\n        Trace.log.info("perf: present entry',
    '        startMouseMonitor()\n        let cursorMoved': '        auditMark("placement")\n        startMouseMonitor()\n        let cursorMoved',
    '        var safe = display?.visibleFrame': '        auditMark("theme")\n        var safe = display?.visibleFrame',
    '        content.frame = CGRect(origin: .zero, size: frame.size)\n': '        content.frame = CGRect(origin: .zero, size: frame.size)\n        auditMark("geometry")\n',
    '        desiredBodyViews.removeAll(keepingCapacity: true)\n        body.rules': '        auditMark("chrome")\n        desiredBodyViews.removeAll(keepingCapacity: true)\n        body.rules',
    '        for (id, plaque) in plaques where !wantedPlaques': '        auditMark("body")\n        for (id, plaque) in plaques where !wantedPlaques',
    '        reconcileBodyViews()\n': '        reconcileBodyViews()\n        auditMark("reconcile")\n',
    '        if opening && !previewOnly { panel.makeKeyAndOrderFront': '        auditMark("finalGeometry")\n        if opening && !previewOnly { panel.makeKeyAndOrderFront',
    '        needsFullPresent = false\n        if opening {': '        needsFullPresent = false\n        auditMark("return")\n        if opening {',
    '        super.init(frame: frame); title = ""; isBordered = false; wantsLayer = true; layer?.cornerRadius = 7;': '        OpeningAudit.rowConstructions += 1\n        super.init(frame: frame); title = ""; isBordered = false; wantsLayer = true; layer?.cornerRadius = 7;',
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f'Instrumentation anchor not unique: {old!r}')
    text = text.replace(old, new)
# Optional isolated experiment for the unfiltered Canopy fixture. This is not a
# production layout implementation; compare final frame sizes in the output.
anchor = '        let defaultHeight = geometry.height'
experiment = """        if CommandLine.arguments.contains("--single-size"), mode == .canopy, !embedded, state.query == nil {
            let auditGutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            let auditBodyWidth = max(100, desiredWidth-36-auditGutter)
            let auditOrder = canopyOrder(state.displayTargets)
            let auditGroups = Dictionary(grouping: state.displayTargets, by: canopyGroupKey)
            let auditColumns = max(1, min(auditOrder.count, Int(auditBodyWidth/260)))
            let auditHeader = max(36+(settings.appearance.scale.factor-1)*12+8, sectionHeight+8)
            var auditHeight: CGFloat = 0
            for start in stride(from: 0, to: auditOrder.count, by: auditColumns) {
                let chunk = auditOrder[start..<min(start+auditColumns, auditOrder.count)]
                let largest = chunk.map { auditGroups[canopyGroupKey($0)]?.count ?? 0 }.max() ?? 0
                auditHeight += auditHeader+CGFloat(largest)*rowStride+16
            }
            geometry.height = max(geometry.height, auditHeight+77+82)
        }
"""
assert text.count(anchor) == 1
text = text.replace(anchor, experiment+anchor)
text = text.replace('if !embedded { panel.setFrame(frame, display: false) }', 'if !embedded { OpeningAudit.frameSizes.append([Double(frame.width), Double(frame.height)]); panel.setFrame(frame, display: false) }')
text = text.replace('            panel.setFrame(grownFrame, display: false)', '            OpeningAudit.frameSizes.append([Double(grownFrame.width), Double(grownFrame.height)])\n            panel.setFrame(grownFrame, display: false)')
pathlib.Path(sys.argv[2]).write_text(text)

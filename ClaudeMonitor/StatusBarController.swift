import AppKit

private let kWidth:    CGFloat = 88
private let kHeight:   CGFloat = 22
private let kFontSize: CGFloat = 9.5
private let kDotSize:  CGFloat = 6
private let kDotX:     CGFloat = 3
private let kTextX:    CGFloat = kDotX + kDotSize + 4  // 13

private func dotColor(_ pct: Double) -> NSColor {
    if pct >= 90 { return .systemRed }
    if pct >= 60 { return .systemOrange }
    return .systemGreen
}

final class StatusBarController: NSObject {

    private let statusItem = NSStatusBar.system.statusItem(withLength: kWidth)

    private let item5hHeader = NSMenuItem(title: "5-часовое окно",      action: nil, keyEquivalent: "")
    private let item5hDetail = NSMenuItem(title: "",                     action: nil, keyEquivalent: "")
    private let item7dHeader = NSMenuItem(title: "Недельный лимит (7д)", action: nil, keyEquivalent: "")
    private let item7dDetail = NSMenuItem(title: "",                     action: nil, keyEquivalent: "")

    override init() {
        super.init()
        buildMenu()
        render(line1: "Loading...", line2: "", pct5: nil, pct7: nil)
        refresh()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        for it in [item5hHeader, item5hDetail, item7dHeader, item7dDetail] {
            it.isEnabled = false
        }
        menu.addItem(item5hHeader)
        menu.addItem(item5hDetail)
        menu.addItem(.separator())
        menu.addItem(item7dHeader)
        menu.addItem(item7dDetail)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Обновить", action: #selector(forceRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func forceRefresh() {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        try? FileManager.default.removeItem(at: base.appendingPathComponent("claude-api-response.json"))
        try? FileManager.default.removeItem(at: base.appendingPathComponent("claude-usage-backoff"))
        try? FileManager.default.removeItem(at: base.appendingPathComponent("claude-usage.lock"))
        refresh()
    }

    // MARK: - Data

    private func refresh() {
        fetchUsage { [weak self] json in
            DispatchQueue.main.async { self?.apply(json) }
        }
    }

    private func apply(_ json: [String: Any]?) {
        guard let json else {
            render(line1: "Not work", line2: "claude", pct5: nil, pct7: nil)
            return
        }
        let u  = parseUsage(json)
        let p5 = u.fiveHourPct
        let p7 = u.sevenDayPct
        let t5 = u.fiveHourResetsAt.map(timeLeft) ?? "--:--"
        let t7 = u.sevenDayResetsAt.map(timeLeft) ?? "--:--"

        render(
            line1: p5.map { "5h \(Int($0))%  \(t5)" } ?? "5h  —",
            line2: p7.map { "7d \(Int($0))%  \(t7)" } ?? "7d  —",
            pct5: p5,
            pct7: p7
        )
        item5hDetail.title = p5.map { "  \(Int($0))% · сброс через \(t5)" } ?? "  нет данных"
        item7dDetail.title = p7.map { "  \(Int($0))% · сброс через \(t7)" } ?? "  нет данных"
    }

    // MARK: - Drawing

    private func render(line1: String, line2: String, pct5: Double?, pct7: Double?) {
        let img = NSImage(size: NSSize(width: kWidth, height: kHeight), flipped: false) { _ in
            let font = NSFont.monospacedDigitSystemFont(ofSize: kFontSize, weight: .regular)
            let ps   = NSMutableParagraphStyle()
            ps.alignment = .left
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font:            font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle:  ps,
            ]

            // ── top line ──────────────────────────────────────────────────────
            let topLineCenter: CGFloat = 11 + 5.5  // mid of upper half
            let topDotY = topLineCenter - kDotSize / 2
            if let pct = pct5 {
                dotColor(pct).setFill()
                NSBezierPath(ovalIn: NSRect(x: kDotX, y: topDotY, width: kDotSize, height: kDotSize)).fill()
            }
            (line1 as NSString).draw(
                in: NSRect(x: kTextX, y: 11, width: kWidth - kTextX, height: 11),
                withAttributes: textAttrs
            )

            // ── bottom line ───────────────────────────────────────────────────
            let botLineCenter: CGFloat = 1 + 5.5
            let botDotY = botLineCenter - kDotSize / 2
            if let pct = pct7 {
                dotColor(pct).setFill()
                NSBezierPath(ovalIn: NSRect(x: kDotX, y: botDotY, width: kDotSize, height: kDotSize)).fill()
            }
            (line2 as NSString).draw(
                in: NSRect(x: kTextX, y: 1, width: kWidth - kTextX, height: 11),
                withAttributes: textAttrs
            )

            return true
        }
        // Без isTemplate — рисуем цвета сами, labelColor адаптируется к теме
        statusItem.button?.image         = img
        statusItem.button?.imagePosition = .imageOnly
    }
}

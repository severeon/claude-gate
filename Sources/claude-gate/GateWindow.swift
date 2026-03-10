import AppKit

class GateWindow: NSObject, NSWindowDelegate {
    var onAuthenticate: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTimeout: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?
    var onAlwaysDeny: (() -> Void)?
    var onRequestJustification: (() -> Void)?

    private let window: NSWindow
    private let errorLabel: NSTextField
    private let auditHeader: NSTextField
    private let auditLabel: NSTextField
    private let auditDisclaimer: NSTextField
    private let justificationResponseLabel: NSTextField
    private let whyButton: NSButton
    private var resolved = false

    // Countdown
    private let countdownLabel: NSTextField
    private var remainingSeconds: Int
    private var countdownTimer: Timer?
    private let timeoutActionWord: String

    // Line number support
    private let lineNumberView: NSTextField
    private let commandTextView: NSTextView

    init(ruleName: String, riskLevel: String, reason: String, commandText: String, workingDirectory: String, justification: String? = nil, timeout: Int = 60, timeoutAction: String = "deny") {

        // --- Compute window size based on content ---
        let commandLines = commandText.components(separatedBy: "\n")
        let lineCount = commandLines.count
        let maxLineLength = commandLines.map({ $0.count }).max() ?? 0
        let isLongCommand = lineCount > 3 || maxLineLength > 60

        let minWidth: CGFloat = 520
        let maxWidth: CGFloat = 1100
        let minHeight: CGFloat = 420
        let maxHeight: CGFloat = 800

        // Side-by-side when command is long enough to warrant it
        let useSideBySide = isLongCommand

        let windowWidth: CGFloat
        let windowHeight: CGFloat
        if useSideBySide {
            // Wider window for side-by-side
            let charWidth: CGFloat = 7.2 // approximate monospace char width at 12pt
            let codeWidth = min(CGFloat(maxLineLength) * charWidth + 80, 600) // +80 for line numbers + padding
            windowWidth = min(max(340 + codeWidth, minWidth), maxWidth)
            let codeHeight = min(CGFloat(lineCount) * 16 + 40, 400) // 16pt per line
            windowHeight = min(max(codeHeight + 200, minHeight), maxHeight)
        } else {
            windowWidth = minWidth
            windowHeight = minHeight
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "claude-gate: Authorization Required"
        window.level = .floating
        window.minSize = NSSize(width: minWidth, height: minHeight)
        window.maxSize = NSSize(width: maxWidth, height: maxHeight)
        window.center()
        self.window = window

        // ===== LEFT PANEL: Rule info, risk, reason, justification, audit =====

        let leftStack = NSStackView()
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 8
        leftStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        // Rule name
        let ruleLabel = NSTextField(labelWithString: ruleName)
        ruleLabel.font = NSFont.boldSystemFont(ofSize: 16)

        // Risk level
        let riskColor: NSColor = {
            switch riskLevel.lowercased() {
            case "critical": return .systemRed
            case "high": return .systemOrange
            case "medium": return .systemYellow
            case "low": return .systemGreen
            default: return .labelColor
            }
        }()
        let riskLabel = NSTextField(labelWithString: "Risk: \(riskLevel.uppercased())")
        riskLabel.font = NSFont.boldSystemFont(ofSize: 13)
        riskLabel.textColor = riskColor

        // Countdown timer
        let actionWord = timeoutAction == "passthrough" ? "Auto-allow" : "Auto-deny"
        let countdownLabel = NSTextField(labelWithString: "\(actionWord) in \(timeout)s")
        countdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        countdownLabel.textColor = .secondaryLabelColor
        self.countdownLabel = countdownLabel
        self.remainingSeconds = timeout
        self.timeoutActionWord = actionWord

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // WHY section
        let whyHeader = NSTextField(labelWithString: "WHY:")
        whyHeader.font = NSFont.boldSystemFont(ofSize: 13)

        let reasonLabel = NSTextField(wrappingLabelWithString: reason)
        reasonLabel.font = NSFont.systemFont(ofSize: 13)

        // AGENT JUSTIFICATION section (if provided)
        var justificationViews: [NSView] = []
        if let justification = justification, !justification.isEmpty {
            let justHeader = NSTextField(labelWithString: "AGENT JUSTIFICATION:")
            justHeader.font = NSFont.boldSystemFont(ofSize: 13)

            let justLabel = NSTextField(wrappingLabelWithString: justification)
            justLabel.font = NSFont.systemFont(ofSize: 13)
            justLabel.textColor = .secondaryLabelColor

            justificationViews = [justHeader, justLabel]
        }

        // WORKING DIRECTORY section
        let cwdHeader = NSTextField(labelWithString: "WORKING DIRECTORY:")
        cwdHeader.font = NSFont.boldSystemFont(ofSize: 13)

        let cwdLabel = NSTextField(labelWithString: workingDirectory)
        cwdLabel.font = NSFont.systemFont(ofSize: 13)
        cwdLabel.lineBreakMode = .byTruncatingMiddle

        // SECURITY AUDIT section
        let auditSeparator = NSBox()
        auditSeparator.boxType = .separator
        auditSeparator.translatesAutoresizingMaskIntoConstraints = false

        let auditHeader = NSTextField(labelWithString: "SECURITY AUDIT: analyzing...")
        auditHeader.font = NSFont.boldSystemFont(ofSize: 13)
        auditHeader.textColor = .secondaryLabelColor
        self.auditHeader = auditHeader

        let auditLabel = NSTextField(wrappingLabelWithString: "")
        auditLabel.font = NSFont.systemFont(ofSize: 12)
        auditLabel.textColor = .secondaryLabelColor
        auditLabel.isHidden = true
        self.auditLabel = auditLabel

        let auditDisclaimer = NSTextField(labelWithString: "AI audit is advisory only — verify commands yourself")
        auditDisclaimer.font = NSFont.systemFont(ofSize: 10)
        auditDisclaimer.textColor = .tertiaryLabelColor
        auditDisclaimer.isHidden = true
        self.auditDisclaimer = auditDisclaimer

        // "Why?" button and justification response
        let whyButton = NSButton(title: "Why?", target: nil, action: nil)
        whyButton.bezelStyle = .rounded
        whyButton.contentTintColor = .systemBlue
        self.whyButton = whyButton

        let justificationResponseLabel = NSTextField(wrappingLabelWithString: "")
        justificationResponseLabel.font = NSFont.systemFont(ofSize: 12)
        justificationResponseLabel.textColor = .secondaryLabelColor
        justificationResponseLabel.isHidden = true
        self.justificationResponseLabel = justificationResponseLabel

        // Error label (hidden initially)
        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
        self.errorLabel = errorLabel

        // Spacer
        let leftSpacer = NSView()
        leftSpacer.translatesAutoresizingMaskIntoConstraints = false
        leftSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Button bar
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        let authButton = NSButton(title: "Authenticate", target: nil, action: nil)
        authButton.bezelStyle = .rounded
        authButton.keyEquivalent = "\r"
        cancelButton.bezelStyle = .rounded

        let buttonBar = NSStackView(views: [cancelButton, authButton])
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 12
        buttonBar.translatesAutoresizingMaskIntoConstraints = false

        // Persistent rule buttons
        let alwaysAllowButton = NSButton(title: "Always Allow", target: nil, action: nil)
        alwaysAllowButton.bezelStyle = .rounded
        alwaysAllowButton.contentTintColor = .systemGreen
        let alwaysDenyButton = NSButton(title: "Always Deny", target: nil, action: nil)
        alwaysDenyButton.bezelStyle = .rounded
        alwaysDenyButton.contentTintColor = .systemRed

        let persistBar = NSStackView(views: [alwaysDenyButton, alwaysAllowButton])
        persistBar.orientation = .horizontal
        persistBar.spacing = 12
        persistBar.translatesAutoresizingMaskIntoConstraints = false

        // Assemble left stack
        leftStack.addArrangedSubview(ruleLabel)
        leftStack.addArrangedSubview(riskLabel)
        leftStack.addArrangedSubview(countdownLabel)
        leftStack.addArrangedSubview(separator)
        leftStack.addArrangedSubview(whyHeader)
        leftStack.addArrangedSubview(reasonLabel)
        for view in justificationViews {
            leftStack.addArrangedSubview(view)
        }
        leftStack.addArrangedSubview(cwdHeader)
        leftStack.addArrangedSubview(cwdLabel)
        leftStack.addArrangedSubview(auditSeparator)
        leftStack.addArrangedSubview(auditHeader)
        leftStack.addArrangedSubview(auditLabel)
        leftStack.addArrangedSubview(auditDisclaimer)
        leftStack.addArrangedSubview(whyButton)
        leftStack.addArrangedSubview(justificationResponseLabel)
        leftStack.addArrangedSubview(leftSpacer)
        leftStack.addArrangedSubview(errorLabel)
        leftStack.addArrangedSubview(persistBar)
        leftStack.addArrangedSubview(buttonBar)

        // ===== RIGHT PANEL: Syntax-highlighted command with line numbers =====

        // Line number gutter
        let lineNumberView = NSTextField(labelWithString: "")
        lineNumberView.font = ShellSyntaxHighlighter.codeFont
        lineNumberView.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        lineNumberView.backgroundColor = NSColor(calibratedRed: 0x1a/255.0, green: 0x1a/255.0, blue: 0x1a/255.0, alpha: 1.0)
        lineNumberView.drawsBackground = true
        lineNumberView.alignment = .right
        lineNumberView.maximumNumberOfLines = 0
        lineNumberView.lineBreakMode = .byClipping
        self.lineNumberView = lineNumberView

        // Build line number text
        let lineNumbers = (1...max(lineCount, 1)).map { String($0) }.joined(separator: "\n")
        lineNumberView.stringValue = lineNumbers

        // Command text view with syntax highlighting
        let commandTextView = NSTextView()
        commandTextView.isEditable = false
        commandTextView.isSelectable = true
        commandTextView.backgroundColor = ShellSyntaxHighlighter.backgroundColor
        commandTextView.textContainerInset = NSSize(width: 8, height: 8)
        commandTextView.isAutomaticQuoteSubstitutionEnabled = false
        commandTextView.isAutomaticTextReplacementEnabled = false
        commandTextView.isAutomaticSpellingCorrectionEnabled = false
        commandTextView.isRichText = false

        // Apply syntax highlighting
        let highlighted = ShellSyntaxHighlighter.highlight(commandText)
        commandTextView.textStorage?.setAttributedString(highlighted)
        self.commandTextView = commandTextView

        let commandScrollView = NSScrollView()
        commandScrollView.documentView = commandTextView
        commandScrollView.hasVerticalScroller = true
        commandScrollView.hasHorizontalScroller = true
        commandScrollView.borderType = .noBorder
        commandScrollView.drawsBackground = true
        commandScrollView.backgroundColor = ShellSyntaxHighlighter.backgroundColor
        commandScrollView.translatesAutoresizingMaskIntoConstraints = false
        commandTextView.autoresizingMask = [.width]

        // Line number scroll view
        let lineNumberScrollView = NSScrollView()
        lineNumberScrollView.documentView = lineNumberView
        lineNumberScrollView.hasVerticalScroller = false
        lineNumberScrollView.drawsBackground = true
        lineNumberScrollView.backgroundColor = NSColor(calibratedRed: 0x1a/255.0, green: 0x1a/255.0, blue: 0x1a/255.0, alpha: 1.0)
        lineNumberScrollView.borderType = .noBorder
        lineNumberScrollView.translatesAutoresizingMaskIntoConstraints = false

        // Code panel header
        let codeHeader = NSTextField(labelWithString: "COMMAND:")
        codeHeader.font = NSFont.boldSystemFont(ofSize: 13)
        codeHeader.textColor = .white

        let codeHeaderBar = NSView()
        codeHeaderBar.translatesAutoresizingMaskIntoConstraints = false
        codeHeaderBar.wantsLayer = true
        codeHeaderBar.layer?.backgroundColor = NSColor(calibratedRed: 0x25/255.0, green: 0x25/255.0, blue: 0x25/255.0, alpha: 1.0).cgColor
        codeHeader.translatesAutoresizingMaskIntoConstraints = false
        codeHeaderBar.addSubview(codeHeader)

        // Code area: line numbers + code
        let codeArea = NSView()
        codeArea.translatesAutoresizingMaskIntoConstraints = false

        codeArea.addSubview(lineNumberScrollView)
        codeArea.addSubview(commandScrollView)

        // Right panel container
        let rightPanel = NSView()
        rightPanel.translatesAutoresizingMaskIntoConstraints = false
        rightPanel.wantsLayer = true
        rightPanel.layer?.backgroundColor = ShellSyntaxHighlighter.backgroundColor.cgColor
        rightPanel.addSubview(codeHeaderBar)
        rightPanel.addSubview(codeArea)

        // ===== LAYOUT =====

        if useSideBySide {
            // Side-by-side with NSSplitView
            let splitView = NSSplitView()
            splitView.isVertical = true
            splitView.dividerStyle = .thin
            splitView.translatesAutoresizingMaskIntoConstraints = false

            // Wrap left stack in a scroll view for when content overflows
            let leftScrollView = NSScrollView()
            let leftFlipped = FlippedClipView()
            leftScrollView.contentView = leftFlipped
            leftScrollView.documentView = leftStack
            leftScrollView.hasVerticalScroller = true
            leftScrollView.drawsBackground = false
            leftScrollView.translatesAutoresizingMaskIntoConstraints = false

            splitView.addArrangedSubview(leftScrollView)
            splitView.addArrangedSubview(rightPanel)

            window.contentView = splitView

            // Left panel min width
            splitView.setHoldingPriority(.defaultLow + 1, forSubviewAt: 0)
            splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

            NSLayoutConstraint.activate([
                splitView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
                splitView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
                splitView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
                splitView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),

                leftScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
                rightPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

                leftStack.widthAnchor.constraint(equalTo: leftScrollView.widthAnchor),
            ])

            // Width constraints for left panel content
            let leftContentWidth = leftScrollView.widthAnchor
            NSLayoutConstraint.activate([
                separator.widthAnchor.constraint(equalTo: leftContentWidth, constant: -32),
                auditSeparator.widthAnchor.constraint(equalTo: leftContentWidth, constant: -32),
                reasonLabel.widthAnchor.constraint(equalTo: leftContentWidth, constant: -32),
                cwdLabel.widthAnchor.constraint(equalTo: leftContentWidth, constant: -32),
                auditLabel.widthAnchor.constraint(equalTo: leftContentWidth, constant: -32),
                justificationResponseLabel.widthAnchor.constraint(equalTo: leftContentWidth, constant: -32),
            ])

            for view in justificationViews {
                if view is NSTextField, view != justificationViews.first {
                    NSLayoutConstraint.activate([
                        view.widthAnchor.constraint(equalTo: leftContentWidth, constant: -32),
                    ])
                }
            }
        } else {
            // Single-column layout for short commands — command shown inline
            let commandHeader = NSTextField(labelWithString: "COMMAND:")
            commandHeader.font = NSFont.boldSystemFont(ofSize: 13)

            // Insert command section into left stack before cwdHeader
            // Remove cwdHeader and cwdLabel, re-add after command
            // Actually, re-order: add command before working directory
            // We need to rebuild the stack for single-column with inline command
            let singleStack = NSStackView()
            singleStack.orientation = .vertical
            singleStack.alignment = .leading
            singleStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            singleStack.spacing = 8
            singleStack.translatesAutoresizingMaskIntoConstraints = false

            // Inline command scroll (smaller)
            let inlineCodeArea = NSView()
            inlineCodeArea.translatesAutoresizingMaskIntoConstraints = false
            inlineCodeArea.addSubview(lineNumberScrollView)
            inlineCodeArea.addSubview(commandScrollView)

            let inlineScrollContainer = NSView()
            inlineScrollContainer.translatesAutoresizingMaskIntoConstraints = false
            inlineScrollContainer.wantsLayer = true
            inlineScrollContainer.layer?.backgroundColor = ShellSyntaxHighlighter.backgroundColor.cgColor
            inlineScrollContainer.layer?.cornerRadius = 4
            inlineScrollContainer.addSubview(inlineCodeArea)

            singleStack.addArrangedSubview(ruleLabel)
            singleStack.addArrangedSubview(riskLabel)
            singleStack.addArrangedSubview(countdownLabel)
            singleStack.addArrangedSubview(separator)
            singleStack.addArrangedSubview(whyHeader)
            singleStack.addArrangedSubview(reasonLabel)
            for view in justificationViews {
                singleStack.addArrangedSubview(view)
            }
            singleStack.addArrangedSubview(commandHeader)
            singleStack.addArrangedSubview(inlineScrollContainer)
            singleStack.addArrangedSubview(cwdHeader)
            singleStack.addArrangedSubview(cwdLabel)
            singleStack.addArrangedSubview(auditSeparator)
            singleStack.addArrangedSubview(auditHeader)
            singleStack.addArrangedSubview(auditLabel)
            singleStack.addArrangedSubview(auditDisclaimer)
            singleStack.addArrangedSubview(whyButton)
            singleStack.addArrangedSubview(justificationResponseLabel)
            singleStack.addArrangedSubview(leftSpacer)
            singleStack.addArrangedSubview(errorLabel)
            singleStack.addArrangedSubview(persistBar)
            singleStack.addArrangedSubview(buttonBar)

            window.contentView = singleStack

            NSLayoutConstraint.activate([
                singleStack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
                singleStack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
                singleStack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
                singleStack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),

                separator.widthAnchor.constraint(equalTo: singleStack.widthAnchor, constant: -32),
                auditSeparator.widthAnchor.constraint(equalTo: singleStack.widthAnchor, constant: -32),
                reasonLabel.widthAnchor.constraint(equalTo: singleStack.widthAnchor, constant: -32),
                cwdLabel.widthAnchor.constraint(equalTo: singleStack.widthAnchor, constant: -32),
                auditLabel.widthAnchor.constraint(equalTo: singleStack.widthAnchor, constant: -32),
                justificationResponseLabel.widthAnchor.constraint(equalTo: singleStack.widthAnchor, constant: -32),

                inlineScrollContainer.widthAnchor.constraint(equalTo: singleStack.widthAnchor, constant: -32),
                inlineScrollContainer.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
                inlineScrollContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),

                inlineCodeArea.topAnchor.constraint(equalTo: inlineScrollContainer.topAnchor),
                inlineCodeArea.bottomAnchor.constraint(equalTo: inlineScrollContainer.bottomAnchor),
                inlineCodeArea.leadingAnchor.constraint(equalTo: inlineScrollContainer.leadingAnchor),
                inlineCodeArea.trailingAnchor.constraint(equalTo: inlineScrollContainer.trailingAnchor),
            ])

            // Inline code area internal layout
            NSLayoutConstraint.activate([
                lineNumberScrollView.topAnchor.constraint(equalTo: inlineCodeArea.topAnchor),
                lineNumberScrollView.bottomAnchor.constraint(equalTo: inlineCodeArea.bottomAnchor),
                lineNumberScrollView.leadingAnchor.constraint(equalTo: inlineCodeArea.leadingAnchor),
                lineNumberScrollView.widthAnchor.constraint(equalToConstant: lineNumberGutterWidth(lineCount: lineCount)),

                commandScrollView.topAnchor.constraint(equalTo: inlineCodeArea.topAnchor),
                commandScrollView.bottomAnchor.constraint(equalTo: inlineCodeArea.bottomAnchor),
                commandScrollView.leadingAnchor.constraint(equalTo: lineNumberScrollView.trailingAnchor),
                commandScrollView.trailingAnchor.constraint(equalTo: inlineCodeArea.trailingAnchor),
            ])

            for view in justificationViews {
                if view is NSTextField, view != justificationViews.first {
                    NSLayoutConstraint.activate([
                        view.widthAnchor.constraint(equalTo: singleStack.widthAnchor, constant: -32),
                    ])
                }
            }
        }

        // Right panel internal layout (for side-by-side mode)
        if useSideBySide {
            NSLayoutConstraint.activate([
                codeHeaderBar.topAnchor.constraint(equalTo: rightPanel.topAnchor),
                codeHeaderBar.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
                codeHeaderBar.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
                codeHeaderBar.heightAnchor.constraint(equalToConstant: 32),

                codeHeader.centerYAnchor.constraint(equalTo: codeHeaderBar.centerYAnchor),
                codeHeader.leadingAnchor.constraint(equalTo: codeHeaderBar.leadingAnchor, constant: 12),

                codeArea.topAnchor.constraint(equalTo: codeHeaderBar.bottomAnchor),
                codeArea.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
                codeArea.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
                codeArea.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor),

                lineNumberScrollView.topAnchor.constraint(equalTo: codeArea.topAnchor),
                lineNumberScrollView.bottomAnchor.constraint(equalTo: codeArea.bottomAnchor),
                lineNumberScrollView.leadingAnchor.constraint(equalTo: codeArea.leadingAnchor),
                lineNumberScrollView.widthAnchor.constraint(equalToConstant: lineNumberGutterWidth(lineCount: lineCount)),

                commandScrollView.topAnchor.constraint(equalTo: codeArea.topAnchor),
                commandScrollView.bottomAnchor.constraint(equalTo: codeArea.bottomAnchor),
                commandScrollView.leadingAnchor.constraint(equalTo: lineNumberScrollView.trailingAnchor),
                commandScrollView.trailingAnchor.constraint(equalTo: codeArea.trailingAnchor),
            ])
        }

        super.init()

        window.delegate = self

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        authButton.target = self
        authButton.action = #selector(authenticateClicked)
        alwaysAllowButton.target = self
        alwaysAllowButton.action = #selector(alwaysAllowClicked)
        alwaysDenyButton.target = self
        alwaysDenyButton.action = #selector(alwaysDenyClicked)
        whyButton.target = self
        whyButton.action = #selector(whyClicked)
    }

    /// Calculate gutter width based on number of lines
    private static func gutterWidth(for lineCount: Int) -> CGFloat {
        let digits = max(String(lineCount).count, 2)
        return CGFloat(digits) * 8.5 + 16 // character width + padding
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func startCountdown() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remainingSeconds -= 1
            if self.remainingSeconds <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                if !self.resolved {
                    self.resolved = true
                    self.onTimeout?()
                    self.window.close()
                }
            } else {
                self.countdownLabel.stringValue = "\(self.timeoutActionWord) in \(self.remainingSeconds)s"
                if self.remainingSeconds <= 10 {
                    self.countdownLabel.textColor = .systemOrange
                }
                if self.remainingSeconds <= 5 {
                    self.countdownLabel.textColor = .systemRed
                }
            }
        }
    }

    func close() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        window.close()
    }

    func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }

    /// Update the security audit section with results
    func showAuditResult(verdict: String, analysis: String) {
        let color: NSColor
        switch verdict.uppercased() {
        case "SAFE": color = .systemBlue
        case "SUSPICIOUS": color = .systemOrange
        case "DANGEROUS": color = .systemRed
        default: color = .secondaryLabelColor
        }

        auditHeader.stringValue = "SECURITY AUDIT: \(verdict.uppercased())"
        auditHeader.textColor = color
        auditLabel.stringValue = analysis
        auditLabel.isHidden = false
        auditDisclaimer.isHidden = false
    }

    /// Show the justification response from the API
    func showJustificationResponse(_ text: String) {
        whyButton.isHidden = true
        justificationResponseLabel.stringValue = text
        justificationResponseLabel.isHidden = false
    }

    /// Show that justification is unavailable
    func showJustificationUnavailable() {
        whyButton.isHidden = true
        justificationResponseLabel.stringValue = "Justification unavailable (no ANTHROPIC_API_KEY)"
        justificationResponseLabel.textColor = .tertiaryLabelColor
        justificationResponseLabel.isHidden = false
    }

    /// Show that the audit is unavailable (no API key)
    func showAuditUnavailable() {
        auditHeader.stringValue = "SECURITY AUDIT: unavailable (no ANTHROPIC_API_KEY)"
        auditHeader.textColor = .tertiaryLabelColor
    }

    // MARK: - Actions

    @objc private func authenticateClicked() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        onAuthenticate?()
    }

    @objc private func alwaysAllowClicked() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        onAlwaysAllow?()
        window.close()
    }

    @objc private func alwaysDenyClicked() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        onAlwaysDeny?()
        window.close()
    }

    @objc private func whyClicked() {
        whyButton.isEnabled = false
        whyButton.title = "Asking..."
        onRequestJustification?()
    }

    @objc private func cancelClicked() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        onCancel?()
        window.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        if !resolved {
            resolved = true
            onCancel?()
        }
    }
}

// MARK: - Helpers

/// Compute gutter width for line numbers
private func lineNumberGutterWidth(lineCount: Int) -> CGFloat {
    let digits = max(String(lineCount).count, 2)
    return CGFloat(digits) * 8.5 + 16
}

/// A flipped clip view so NSStackView content starts from top in scroll views.
class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

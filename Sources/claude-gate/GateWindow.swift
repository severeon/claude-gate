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
    private let stackView: NSStackView
    private var resolved = false

    // Countdown
    private let countdownLabel: NSTextField
    private var remainingSeconds: Int
    private var countdownTimer: Timer?
    private let timeoutActionWord: String

    // MARK: - Styled Button Factory

    private static func styledButton(
        title: String,
        backgroundColor: NSColor,
        textColor: NSColor = .white,
        fontSize: CGFloat = 13,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 6
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: textColor,
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            ]
        )
        button.contentTintColor = textColor

        // Minimum size via intrinsic content size padding
        let width = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ]).width + horizontalPadding * 2
        let height = fontSize + verticalPadding * 2
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: width),
            button.heightAnchor.constraint(equalToConstant: height),
        ])

        return button
    }

    // MARK: - Risk Badge Factory

    private static func riskBadge(riskLevel: String) -> NSView {
        let riskColor: NSColor = {
            switch riskLevel.lowercased() {
            case "critical": return .systemRed
            case "high": return .systemOrange
            case "medium": return .systemYellow
            case "low": return .systemGreen
            default: return .systemGray
            }
        }()

        let badgeText = riskLevel.uppercased()
        let label = NSTextField(labelWithString: badgeText)
        label.font = NSFont.boldSystemFont(ofSize: 11)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.backgroundColor = riskColor.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -3),
        ])

        // Wrapper so NSStackView gets the right alignment
        let wrapper = NSStackView(views: [badge])
        wrapper.alignment = .leading
        return wrapper
    }

    // MARK: - Section Container Factory

    private static func sectionContainer(views: [NSView], backgroundColor: NSColor? = nil) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        if let bg = backgroundColor {
            container.layer?.backgroundColor = bg.cgColor
        } else {
            container.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.1).cgColor
        }
        container.layer?.cornerRadius = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let innerStack = NSStackView()
        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 4
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        innerStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        for v in views {
            innerStack.addArrangedSubview(v)
        }

        container.addSubview(innerStack)
        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: container.topAnchor),
            innerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            innerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        return container
    }

    init(ruleName: String, riskLevel: String, reason: String, commandText: String, workingDirectory: String, justification: String? = nil, timeout: Int = 60, timeoutAction: String = "deny") {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "claude-gate: Authorization Required"
        window.level = .floating
        window.center()
        self.window = window

        // -- Build the content view --

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView = stackView

        // Rule name (title)
        let ruleLabel = NSTextField(labelWithString: ruleName)
        ruleLabel.font = NSFont.boldSystemFont(ofSize: 16)

        // Risk badge (colored pill)
        let riskBadgeView = GateWindow.riskBadge(riskLevel: riskLevel)

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

        // WHY section (in a shaded container)
        let whyHeader = NSTextField(labelWithString: "WHY:")
        whyHeader.font = NSFont.boldSystemFont(ofSize: 12)
        whyHeader.textColor = .secondaryLabelColor

        let reasonLabel = NSTextField(wrappingLabelWithString: reason)
        reasonLabel.font = NSFont.systemFont(ofSize: 13)

        let whyContainer = GateWindow.sectionContainer(views: [whyHeader, reasonLabel])

        // AGENT JUSTIFICATION section (if provided)
        var justificationContainer: NSView?
        if let justification = justification, !justification.isEmpty {
            let justHeader = NSTextField(labelWithString: "AGENT JUSTIFICATION:")
            justHeader.font = NSFont.boldSystemFont(ofSize: 12)
            justHeader.textColor = .secondaryLabelColor

            let justLabel = NSTextField(wrappingLabelWithString: justification)
            justLabel.font = NSFont.systemFont(ofSize: 13)
            justLabel.textColor = .secondaryLabelColor

            justificationContainer = GateWindow.sectionContainer(views: [justHeader, justLabel])
        }

        // COMMAND section (in a shaded container)
        let commandHeader = NSTextField(labelWithString: "COMMAND:")
        commandHeader.font = NSFont.boldSystemFont(ofSize: 12)
        commandHeader.textColor = .secondaryLabelColor

        let commandTextView = NSTextView()
        commandTextView.isEditable = false
        commandTextView.isSelectable = true
        commandTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        commandTextView.backgroundColor = NSColor(calibratedRed: 0x1e/255.0, green: 0x1e/255.0, blue: 0x1e/255.0, alpha: 1.0)
        commandTextView.textColor = .white
        commandTextView.string = commandText
        commandTextView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView()
        scrollView.documentView = commandTextView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 6

        let commandContainer = NSView()
        commandContainer.translatesAutoresizingMaskIntoConstraints = false
        commandContainer.wantsLayer = true
        commandContainer.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.1).cgColor
        commandContainer.layer?.cornerRadius = 8

        let commandInnerStack = NSStackView()
        commandInnerStack.orientation = .vertical
        commandInnerStack.alignment = .leading
        commandInnerStack.spacing = 6
        commandInnerStack.translatesAutoresizingMaskIntoConstraints = false
        commandInnerStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        commandInnerStack.addArrangedSubview(commandHeader)
        commandInnerStack.addArrangedSubview(scrollView)

        commandContainer.addSubview(commandInnerStack)
        NSLayoutConstraint.activate([
            commandInnerStack.topAnchor.constraint(equalTo: commandContainer.topAnchor),
            commandInnerStack.bottomAnchor.constraint(equalTo: commandContainer.bottomAnchor),
            commandInnerStack.leadingAnchor.constraint(equalTo: commandContainer.leadingAnchor),
            commandInnerStack.trailingAnchor.constraint(equalTo: commandContainer.trailingAnchor),
        ])

        // WORKING DIRECTORY section
        let cwdHeader = NSTextField(labelWithString: "WORKING DIRECTORY:")
        cwdHeader.font = NSFont.boldSystemFont(ofSize: 12)
        cwdHeader.textColor = .secondaryLabelColor

        let cwdLabel = NSTextField(labelWithString: workingDirectory)
        cwdLabel.font = NSFont.systemFont(ofSize: 12)
        cwdLabel.lineBreakMode = .byTruncatingMiddle
        cwdLabel.textColor = .secondaryLabelColor

        let cwdContainer = GateWindow.sectionContainer(views: [cwdHeader, cwdLabel])

        // SECURITY AUDIT section
        let auditHeader = NSTextField(labelWithString: "SECURITY AUDIT: analyzing...")
        auditHeader.font = NSFont.boldSystemFont(ofSize: 12)
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

        let auditContainer = GateWindow.sectionContainer(views: [auditHeader, auditLabel, auditDisclaimer])

        // "Why?" button — small, blue, inline style
        let whyButton = GateWindow.styledButton(
            title: "Why?",
            backgroundColor: .systemBlue,
            textColor: .white,
            fontSize: 11,
            horizontalPadding: 10,
            verticalPadding: 4
        )
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

        // Styled buttons
        let cancelButton = GateWindow.styledButton(
            title: "Cancel",
            backgroundColor: NSColor.systemGray.withAlphaComponent(0.3),
            textColor: .labelColor,
            fontSize: 13
        )

        let authButton = GateWindow.styledButton(
            title: "Authenticate",
            backgroundColor: .systemGreen,
            textColor: .white,
            fontSize: 14,
            horizontalPadding: 20,
            verticalPadding: 8
        )
        authButton.keyEquivalent = "\r"

        let buttonBar = NSStackView(views: [cancelButton, authButton])
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 12

        // Persistent rule buttons
        let alwaysAllowButton = GateWindow.styledButton(
            title: "Always Allow",
            backgroundColor: .systemGreen.withAlphaComponent(0.2),
            textColor: .systemGreen,
            fontSize: 12
        )
        let alwaysDenyButton = GateWindow.styledButton(
            title: "Always Deny",
            backgroundColor: .systemRed.withAlphaComponent(0.2),
            textColor: .systemRed,
            fontSize: 12
        )

        let persistBar = NSStackView(views: [alwaysDenyButton, alwaysAllowButton])
        persistBar.orientation = .horizontal
        persistBar.spacing = 12

        // Spacer view
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Add all views to stack with increased spacing between major sections
        stackView.addArrangedSubview(ruleLabel)
        stackView.setCustomSpacing(8, after: ruleLabel)

        stackView.addArrangedSubview(riskBadgeView)
        stackView.setCustomSpacing(4, after: riskBadgeView)

        stackView.addArrangedSubview(countdownLabel)
        stackView.setCustomSpacing(12, after: countdownLabel)

        stackView.addArrangedSubview(separator)
        stackView.setCustomSpacing(14, after: separator)

        stackView.addArrangedSubview(whyContainer)
        stackView.setCustomSpacing(10, after: whyContainer)

        if let jc = justificationContainer {
            stackView.addArrangedSubview(jc)
            stackView.setCustomSpacing(10, after: jc)
        }

        stackView.addArrangedSubview(commandContainer)
        stackView.setCustomSpacing(10, after: commandContainer)

        stackView.addArrangedSubview(cwdContainer)
        stackView.setCustomSpacing(14, after: cwdContainer)

        stackView.addArrangedSubview(auditContainer)
        stackView.setCustomSpacing(10, after: auditContainer)

        stackView.addArrangedSubview(whyButton)
        stackView.addArrangedSubview(justificationResponseLabel)
        stackView.setCustomSpacing(8, after: justificationResponseLabel)

        stackView.addArrangedSubview(spacer)
        stackView.setCustomSpacing(8, after: spacer)

        stackView.addArrangedSubview(errorLabel)
        stackView.setCustomSpacing(10, after: errorLabel)

        stackView.addArrangedSubview(persistBar)
        stackView.setCustomSpacing(8, after: persistBar)

        stackView.addArrangedSubview(buttonBar)

        // Layout hints
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        persistBar.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = stackView

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),

            separator.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),

            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 80),
            scrollView.widthAnchor.constraint(equalTo: commandInnerStack.widthAnchor, constant: -24),

            whyContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            commandContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            cwdContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            auditContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),

            reasonLabel.widthAnchor.constraint(equalTo: whyContainer.widthAnchor, constant: -24),
            auditLabel.widthAnchor.constraint(equalTo: auditContainer.widthAnchor, constant: -24),
            justificationResponseLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),

            buttonBar.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -20),

            persistBar.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 20),
        ])

        // Constrain justification container width if present
        if let jc = justificationContainer {
            NSLayoutConstraint.activate([
                jc.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
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
        whyButton.attributedTitle = NSAttributedString(
            string: "Asking...",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            ]
        )
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

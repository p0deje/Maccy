//
//  RecordView.swift
//
//  KeyHolder
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa
import Carbon
import Magnet
import Sauce

public protocol RecordViewDelegate: AnyObject {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool
    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool
    func recordViewDidClearShortcut(_ recordView: RecordView)
    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo)
    func recordViewDidEndRecording(_ recordView: RecordView)
}

@IBDesignable
open class RecordView: NSView {

    // MARK: - Properties
    @IBInspectable open var backgroundColor: NSColor = .controlColor {
        didSet { needsDisplay = true }
    }
    @IBInspectable open var tintColor: NSColor = .controlAccentPolyfill {
        didSet { needsDisplay = true }
    }
    @IBInspectable open var borderColor: NSColor = .controlColor {
        didSet { layer?.borderColor = borderColor.cgColor }
    }
    @IBInspectable open var borderWidth: CGFloat = 0 {
        didSet { layer?.borderWidth = borderWidth }
    }
    @IBInspectable open var cornerRadius: CGFloat = 0 {
        didSet {
            layer?.cornerRadius = cornerRadius
            needsDisplay = true
            noteFocusRingMaskChanged()
        }
    }
    open var clearButtonMode: RecordView.ClearButtonMode = .always {
        didSet { needsDisplay = true }
    }

    open weak var delegate: RecordViewDelegate?
    open var didChange: ((KeyCombo?) -> Void)?
    @objc dynamic open private(set) var isRecording = false
    open var keyCombo: KeyCombo? {
        didSet { needsDisplay = true }
    }
    open var isEnabled = true {
        didSet {
            needsDisplay = true
            if !isEnabled { endRecording() }
            noteFocusRingMaskChanged()
        }
    }

    private let clearButton = ClearButton()
    private let modifierEventHandler = ModifierEventHandler()
    private let validModifiers: [NSEvent.ModifierFlags] = [.shift, .control, .option, .command]
    private let validModifiersText: [NSString] = ["⇧", "⌃", "⌥", "⌘"]
    private var inputModifiers = NSEvent.ModifierFlags(rawValue: 0)
    private var doubleTapModifier = NSEvent.ModifierFlags(rawValue: 0)
    private var multiModifiers = false
    private var fontSize: CGFloat {
        return bounds.height / 1.7
    }
    private var clearSize: CGFloat {
        return fontSize / 1.3
    }
    private var marginY: CGFloat {
        return (bounds.height - fontSize) / 2.6
    }
    private var marginX: CGFloat {
        return marginY * 1.5
    }

    // MARK: - Override Properties
    open override var isOpaque: Bool {
        return false
    }
    open override var isFlipped: Bool {
        return true
    }
    open override var focusRingMaskBounds: NSRect {
        return (isEnabled && window?.firstResponder == self) ? bounds : NSRect.zero
    }

    // MARK: - Initialize
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        initView()
    }

    private func initView() {
        // Clear Button
        clearButton.target = self
        clearButton.action = #selector(RecordView.clearAndEndRecording)
        addSubview(clearButton)
        // Double Tap
        modifierEventHandler.doubleTapped = { [weak self] modifierFlags in
            guard let strongSelf = self else { return }
            guard let keyCombo = KeyCombo(doubledCocoaModifiers: modifierFlags) else { return }
            guard self?.delegate?.recordView(strongSelf, canRecordKeyCombo: keyCombo) ?? true else { return }
            self?.keyCombo = keyCombo
            self?.didChange?(keyCombo)
            self?.delegate?.recordView(strongSelf, didChangeKeyCombo: keyCombo)
            self?.endRecording()
        }
    }

    // MARK: - Draw
    open override func drawFocusRingMask() {
        if isEnabled && window?.firstResponder == self {
            NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
    }

    override open func draw(_ dirtyRect: NSRect) {
        drawBackground(dirtyRect)
        drawModifiers(dirtyRect)
        drawKeyCode(dirtyRect)
        drawClearButton(dirtyRect)
    }

    private func drawBackground(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()

        let rect = NSRect(x: borderWidth / 2, y: borderWidth / 2, width: bounds.width - borderWidth, height: bounds.height - borderWidth)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = borderWidth
        borderColor.set()
        path.stroke()
    }

    private func drawModifiers(_ dirtyRect: NSRect) {
        let fontSize = self.fontSize
        let modifiers: NSEvent.ModifierFlags
        if let keyCombo = self.keyCombo {
            modifiers = keyCombo.modifiers.convertSupportCocoaModifiers()
        } else {
            modifiers = inputModifiers
        }
        for (i, text) in validModifiersText.enumerated() {
            let rect = NSRect(x: marginX + (fontSize * CGFloat(i)), y: marginY, width: fontSize, height: bounds.height)
            text.draw(in: rect, withAttributes: modifierTextAttributes(modifiers, checkModifier: validModifiers[i]))
        }
    }

    private func drawKeyCode(_ dirtyRext: NSRect) {
        guard let keyCombo = self.keyCombo else { return }
        let fontSize = self.fontSize
        let minX = (fontSize * 4) + (marginX * 2)
        let width = bounds.width - minX - (marginX * 2) - clearSize
        if width <= 0 { return }
        let text = (keyCombo.doubledModifiers) ? "double tap" : keyCombo.keyEquivalent.uppercased()
        text.draw(in: NSRect(x: minX, y: marginY, width: width, height: bounds.height), withAttributes: keyCodeTextAttributes())
    }

    private func drawClearButton(_ dirtyRext: NSRect) {
        let clearSize = self.clearSize
        let x = bounds.width - clearSize - marginX
        let y = (bounds.height - clearSize) / 2
        clearButton.frame = NSRect(x: x, y: y, width: clearSize, height: clearSize)
        switch clearButtonMode {
        case .always:
            clearButton.isHidden = false
        case .never:
            clearButton.isHidden = true
        case .whenRecorded:
            clearButton.isHidden = (keyCombo == nil)
        }
    }

    // MARK: - NSResponder
    override open var acceptsFirstResponder: Bool {
        return isEnabled
    }

    override open var canBecomeKeyView: Bool {
        return super.canBecomeKeyView && NSApp.isFullKeyboardAccessEnabled
    }

    override open var needsPanelToBecomeKey: Bool {
        return true
    }

    override open func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    override open func acceptsFirstMouse(for theEvent: NSEvent?) -> Bool {
        return true
    }

    override open func mouseDown(with theEvent: NSEvent) {
        if !isEnabled {
            super.mouseDown(with: theEvent)
            return
        }

        let locationInView = convert(theEvent.locationInWindow, from: nil)
        if isMousePoint(locationInView, in: bounds) && !isRecording {
            _ = beginRecording()
        } else {
            super.mouseDown(with: theEvent)
        }
    }

    open override func cancelOperation(_ sender: Any?) {
        endRecording()
    }

    override open func keyDown(with theEvent: NSEvent) {
        if !performKeyEquivalent(with: theEvent) { super.keyDown(with: theEvent) }
    }

    override open func performKeyEquivalent(with theEvent: NSEvent) -> Bool {
        guard isEnabled else { return false }
        guard window?.firstResponder == self else { return false }
        guard let key = Sauce.shared.key(by: Int(theEvent.keyCode)) else { return false }
        if isRecording && validateModifiers(inputModifiers) {
            let modifiers = theEvent.modifierFlags.carbonModifiers()
            if let keyCombo = KeyCombo(key: key, carbonModifiers: modifiers) {
                if delegate?.recordView(self, canRecordKeyCombo: keyCombo) ?? true {
                    self.keyCombo = keyCombo
                    didChange?(keyCombo)
                    delegate?.recordView(self, didChangeKeyCombo: keyCombo)
                    endRecording()
                    return true
                }
            }
            return false
        } else if isRecording && key.isFunctionKey {
            if let keyCombo = KeyCombo(key: key, cocoaModifiers: []) {
                if delegate?.recordView(self, canRecordKeyCombo: keyCombo) ?? true {
                    self.keyCombo = keyCombo
                    didChange?(keyCombo)
                    delegate?.recordView(self, didChangeKeyCombo: keyCombo)
                    endRecording()
                    return true
                }
            }
            return false
        } else if Int(theEvent.keyCode) == kVK_Space {
            return beginRecording()
        }
        return false
    }

    override open func flagsChanged(with theEvent: NSEvent) {
        guard isRecording else {
            inputModifiers = NSEvent.ModifierFlags(rawValue: 0)
            super.flagsChanged(with: theEvent)
            return
        }
        modifierEventHandler.handleModifiersEvent(with: theEvent.modifierFlags, timestamp: theEvent.timestamp)
        inputModifiers = theEvent.modifierFlags
        needsDisplay = true
        super.flagsChanged(with: theEvent)
    }

}

// MARK: - Text Attributes
private extension RecordView {
    func modifierTextAttributes(_ modifiers: NSEvent.ModifierFlags, checkModifier: NSEvent.ModifierFlags) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.baseWritingDirection = .leftToRight
        let textColor: NSColor
        if !isEnabled {
            textColor = .disabledControlTextColor
        } else if modifiers.contains(checkModifier) {
            textColor = tintColor
        } else {
            textColor = .lightGray
        }
        return [.font: NSFont.systemFont(ofSize: floor(fontSize)),
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle]
    }

    func keyCodeTextAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.baseWritingDirection = .leftToRight
        return [.font: NSFont.systemFont(ofSize: floor(fontSize)),
                .foregroundColor: tintColor,
                .paragraphStyle: paragraphStyle]
    }
}

// MARK: - Recording
public extension RecordView {
    func beginRecording() -> Bool {
        guard isEnabled else { return false }
        guard !isRecording else { return true }

        needsDisplay = true

        if let delegate = delegate, !delegate.recordViewShouldBeginRecording(self) {
            NSSound.beep()
            return false
        }

        isRecording = true
        updateTrackingAreas()

        return true
    }

    func endRecording() {
        guard isRecording else { return }

        inputModifiers = NSEvent.ModifierFlags(rawValue: 0)
        doubleTapModifier = NSEvent.ModifierFlags(rawValue: 0)
        multiModifiers = false

        isRecording = false
        updateTrackingAreas()
        needsDisplay = true

        if window?.firstResponder == self && !canBecomeKeyView { window?.makeFirstResponder(nil) }
        delegate?.recordViewDidEndRecording(self)
    }
}

// MARK: - Clear Keys
public extension RecordView {
    func clear() {
        keyCombo = nil
        inputModifiers = NSEvent.ModifierFlags(rawValue: 0)
        needsDisplay = true
        didChange?(nil)
        delegate?.recordViewDidClearShortcut(self)
    }

    @objc func clearAndEndRecording() {
        clear()
        endRecording()
    }
}

// MARK: - Modifiers
private extension RecordView {
    func validateModifiers(_ modifiers: NSEvent.ModifierFlags?) -> Bool {
        guard let modifiers = modifiers else { return false }
        return modifiers.carbonModifiers() != 0
    }
}

// MARK: - Clear Button Mode
public extension RecordView {
    enum ClearButtonMode {
        case never
        case always
        case whenRecorded
    }
}

// MARK: - NSColor Extension
// nmacOS 10.14 polyfill
private extension NSColor {
    static let controlAccentPolyfill: NSColor = {
        if #available(macOS 10.14, *) {
            return NSColor.controlAccentColor
        } else {
            return NSColor(red: 0.10, green: 0.47, blue: 0.98, alpha: 1)
        }
    }()
}

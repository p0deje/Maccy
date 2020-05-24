//
//  ClearButton.swift
//
//  KeyHolder
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa

final class ClearButton: NSButton {

    // MARK: - Initialize
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initView()
    }

    private func initView() {
        isBordered = false
        wantsLayer = true
        layer?.masksToBounds = true
        title = ""
    }

    // MARK: - Layout
    // swiftlint:disable function_body_length
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        layer?.cornerRadius = bounds.height / 2
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        // Background Circle
        let circleFillLayer = CAShapeLayer()
        circleFillLayer.frame = bounds
        circleFillLayer.fillColor = (isHighlighted) ? NSColor.clearHighlightedBackgroundFill.cgColor : NSColor.clearBackgroundFill.cgColor
        let circlePath = CGMutablePath()
        circlePath.addEllipse(in: bounds)
        circlePath.closeSubpath()
        circleFillLayer.path = circlePath
        // Clear X
        let clearLayer = CAShapeLayer()
        clearLayer.frame = bounds
        let clearPath = CGMutablePath()
        clearPath.addEllipse(in: bounds)
        clearPath.closeSubpath()
        // Draw X
        let xMargin = bounds.width * 0.3
        let yMargin = bounds.height * 0.3
        let bottomAnchor = bounds.height - yMargin
        let rightAnchor = bounds.width - xMargin
        let lineWidth: CGFloat = 1.5
        let radius = lineWidth / 2
        let cornerWidth = lineWidth / sqrt(2)
        let harfCornerWidth = cornerWidth / 2
        clearPath.move(to: CGPoint(x: xMargin - harfCornerWidth, y: yMargin + harfCornerWidth))
        clearPath.addLine(to: CGPoint(x: bounds.midX - cornerWidth, y: bounds.midY))
        clearPath.addLine(to: CGPoint(x: xMargin - harfCornerWidth, y: bottomAnchor - harfCornerWidth))
        clearPath.addArc(tangent1End: CGPoint(x: xMargin - harfCornerWidth, y: bottomAnchor + harfCornerWidth), tangent2End: CGPoint(x: xMargin + harfCornerWidth, y: bottomAnchor + harfCornerWidth), radius: radius)
        clearPath.addLine(to: CGPoint(x: bounds.midX, y: bounds.midY + cornerWidth))
        clearPath.addLine(to: CGPoint(x: rightAnchor - harfCornerWidth, y: bottomAnchor + harfCornerWidth))
        clearPath.addArc(tangent1End: CGPoint(x: rightAnchor + harfCornerWidth, y: bottomAnchor + harfCornerWidth), tangent2End: CGPoint(x: rightAnchor + harfCornerWidth, y: bottomAnchor - harfCornerWidth), radius: radius)
        clearPath.addLine(to: CGPoint(x: bounds.midX + cornerWidth, y: bounds.midY))
        clearPath.addLine(to: CGPoint(x: rightAnchor + harfCornerWidth, y: yMargin + harfCornerWidth))
        clearPath.addArc(tangent1End: CGPoint(x: rightAnchor + harfCornerWidth, y: yMargin - harfCornerWidth), tangent2End: CGPoint(x: rightAnchor - harfCornerWidth, y: yMargin - harfCornerWidth), radius: radius)
        clearPath.addLine(to: CGPoint(x: bounds.midX, y: bounds.midY - cornerWidth))
        clearPath.addLine(to: CGPoint(x: xMargin + harfCornerWidth, y: yMargin - harfCornerWidth))
        clearPath.addArc(tangent1End: CGPoint(x: xMargin - harfCornerWidth, y: yMargin - harfCornerWidth), tangent2End: CGPoint(x: xMargin - harfCornerWidth, y: yMargin + harfCornerWidth), radius: radius)
        clearPath.closeSubpath()
        clearLayer.path = clearPath
        clearLayer.lineWidth = 0
        clearLayer.fillColor = NSColor.black.cgColor
        clearLayer.strokeColor = NSColor.black.cgColor
        clearLayer.fillRule = .evenOdd
        circleFillLayer.mask = clearLayer
        // Layer
        layer?.addSublayer(circleFillLayer)
    }
    // swiftlint:enable function_body_length

}

// MARK: - Color
private extension NSColor {
    static var clearBackgroundFill: NSColor {
        return NSColor(red: 0.749019608, green: 0.749019608, blue: 0.749019608, alpha: 1)
    }
    static var clearHighlightedBackgroundFill: NSColor {
        return NSColor(red: 0.525490196, green: 0.525490196, blue: 0.525490196, alpha: 1)
    }
}

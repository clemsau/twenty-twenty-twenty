#!/usr/bin/env swift
// Regenerate every icon asset:  swift Tools/GenerateIcons.swift
//
// Drawing the icons in code keeps the design reviewable in the diff and
// regenerable when it changes, rather than being an opaque binary blob.
//
// The "20"s are turned into CGPaths instead of being drawn as attributed
// strings, for two reasons found by looking at the output of the string route:
//
//   * Honest line weights. AppKit's `.strokeWidth` attribute is a PERCENTAGE of
//     the font size, not points. One constant therefore means a different real
//     weight on every canvas, and there is no way to hold an outline at or above
//     one device pixel on the 16pt tile. `CGContext` line widths are points.
//   * Honest bounds. `boundingBoxOfPath` is the tight outline of the digits, so
//     the stack can be centred on the ink you actually see rather than on the
//     typographic line box, which reserves ascender and descender space that
//     "20" never occupies. Centring on the line box is what pushed the first
//     draft's rear copy off the right edge.

import AppKit
import CoreText
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appending(path: "Sources/Assets.xcassets")

// MARK: - "20" as geometry

/// The outline of "20" at `fontSize`, baseline origin at (0, 0).
func twentyPath(fontSize: CGFloat, weight: NSFont.Weight) -> CGPath {
    let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
    let attributed = NSAttributedString(
        string: "20", attributes: [.font: font, .kern: -fontSize * 0.035])
    let line = CTLineCreateWithAttributedString(attributed)
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(), &glyphs)
        CTRunGetPositions(run, CFRange(), &positions)
        for index in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
            path.addPath(
                glyph,
                transform: CGAffineTransform(
                    translationX: positions[index].x, y: positions[index].y))
        }
    }
    return path
}

/// One copy of "20" in the receding stack.
struct Layer {
    /// Relative to the front copy. Below 1 is what makes the copy read as
    /// *further away* rather than merely shifted.
    let scale: CGFloat
    let opacity: CGFloat
    /// Points. Zero fills the glyph solid.
    let lineWidth: CGFloat
    /// How many offset steps behind the front copy this one sits.
    let stepsBack: CGFloat
}

/// Lays the stack out and reports the union of the ink boxes, so the caller can
/// centre the whole mark instead of guessing margins.
func stack(
    fontSize: CGFloat, step: CGVector, layers: [Layer], weight: NSFont.Weight
) -> ([CGPath], CGRect) {
    let base = twentyPath(fontSize: fontSize, weight: weight)
    let box = base.boundingBoxOfPath
    var paths: [CGPath] = []
    var union = CGRect.null

    for layer in layers {
        // Scale about the glyph's own centre, so shrinking a copy does not also
        // slide it sideways and fight the offset.
        var transform = CGAffineTransform.identity
            .translatedBy(x: layer.stepsBack * step.dx, y: layer.stepsBack * step.dy)
            .translatedBy(x: box.midX, y: box.midY)
            .scaledBy(x: layer.scale, y: layer.scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        let path = base.copy(using: &transform)!
        paths.append(path)
        // A stroke straddles the outline, so a hollow copy claims half a line
        // width of margin beyond its path.
        union = union.union(
            path.boundingBoxOfPath.insetBy(dx: -layer.lineWidth / 2, dy: -layer.lineWidth / 2))
    }
    return (paths, union)
}

/// The contours of a path, one path each.
func contours(of path: CGPath) -> [CGPath] {
    var result: [CGPath] = []
    var current = CGMutablePath()
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        switch element.type {
        case .moveToPoint:
            if !current.isEmpty { result.append(current.copy()!) }
            current = CGMutablePath()
            current.move(to: element.points[0])
        case .addLineToPoint:
            current.addLine(to: element.points[0])
        case .addQuadCurveToPoint:
            current.addQuadCurve(to: element.points[1], control: element.points[0])
        case .addCurveToPoint:
            current.addCurve(
                to: element.points[2], control1: element.points[0], control2: element.points[1])
        case .closeSubpath:
            current.closeSubpath()
        @unknown default:
            break
        }
    }
    if !current.isEmpty { result.append(current.copy()!) }
    return result
}

/// The glyph's outline with its counters filled in.
///
/// Filling each contour on its own is what closes them: the inside of a "0" is a
/// separate reversed contour, so on its own it fills as a solid ellipse, and the
/// union with the outer contour is the silhouette. This is what a solid copy has
/// to hide from the copies behind it. Using the glyph path itself instead leaves
/// the counters open, and a fragment of the copy behind then shows through the
/// hole in the front "0" — physically right, but at icon scale it reads as a
/// speck of dirt rather than as depth.
func silhouette(_ path: CGPath) -> CGPath {
    contours(of: path).reduce(CGMutablePath() as CGPath) { $0.union($1) }
}

/// The area a layer actually inks: the glyph when solid, the stroked outline
/// when hollow.
func inkedArea(_ path: CGPath, _ layer: Layer) -> CGPath {
    guard layer.lineWidth > 0 else { return path }
    return path.copy(
        strokingWithWidth: layer.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Draws a positioned stack back to front.
///
/// Each copy subtracts itself, grown by `halo`, from every copy behind it.
/// Without that the copies merely cross — a ghost's "2" runs straight through
/// the "0" in front of it — and the mark reads as a knot of loops rather than
/// three "20"s at different depths. The knockout is what turns overlap into
/// occlusion, which is the whole point of the design.
///
/// The gap is cut by subtracting paths rather than by painting with the `.clear`
/// blend mode: `.clear` is not honoured in a PDF context, where instead of
/// erasing it leaves the shape to be filled in the current colour and silently
/// turns the menu bar glyph into a black blob.
func render(
    paths: [CGPath], layers: [Layer], halo: CGFloat, ink: CGColor, in context: CGContext
) {
    let areas = zip(paths, layers).map(inkedArea)
    let knockouts: [CGPath] = zip(paths, layers).map { path, layer in
        // A hollow copy hides only its own line, grown by the halo — you see
        // through the rest of it, which is the point of an outline. A solid copy
        // hides its whole silhouette.
        guard layer.lineWidth == 0 else {
            return path.copy(
                strokingWithWidth: layer.lineWidth + halo * 2,
                lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
        let body = silhouette(path)
        let border = body.copy(
            strokingWithWidth: halo * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return body.union(border)
    }

    for (index, area) in areas.enumerated() {
        var visible = area
        if halo > 0 {
            for front in (index + 1)..<areas.count {
                visible = visible.subtracting(knockouts[front])
            }
        }
        context.saveGState()
        context.setAlpha(layers[index].opacity)
        context.setFillColor(ink)
        context.addPath(visible)
        context.fillPath()
        context.restoreGState()
    }
}

// MARK: - App icon

func drawAppIcon(side: CGFloat, in context: CGContext) {
    // Dark rounded square, at the corner radius macOS uses for app icons.
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    context.saveGState()
    context.addPath(
        CGPath(roundedRect: rect, cornerWidth: side * 0.2237, cornerHeight: side * 0.2237,
               transform: nil))
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 0.141, green: 0.149, blue: 0.173, alpha: 1),
                 CGColor(red: 0.051, green: 0.055, blue: 0.067, alpha: 1)] as CFArray,
        locations: [0, 1])!
    // The draws-before/after options matter: without them the gradient paints
    // only the band between the two points and leaves a corner transparent.
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side * 0.5, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    // Three "20"s receding to the top right: front solid, two hollow behind at
    // falling opacity.
    //
    // The recipe is graded by canvas size. One set of fractions cannot serve a
    // 64x range — the front "20" is 410px tall at 1024 and 6px at 16, and two
    // outlined copies crowding a 6px digit are grey noise, not a receding stack.
    // Shipping size-specific artwork is exactly what an .appiconset is for, and
    // it serves the spec's stated reason for using outlines at all: staying
    // legible small.
    let fontSize: CGFloat
    let step: CGVector
    let layers: [Layer]

    switch side {
    case 128...:
        // The sizes people actually look at. Full three-layer stack.
        fontSize = side * 0.385
        step = CGVector(dx: side * 0.185, dy: side * 0.150)
        let hairline = side * 0.024
        layers = [
            Layer(scale: 0.72, opacity: 0.24, lineWidth: hairline * 0.85, stepsBack: 2),
            Layer(scale: 0.86, opacity: 0.44, lineWidth: hairline, stepsBack: 1),
            Layer(scale: 1.00, opacity: 1.00, lineWidth: 0, stepsBack: 0),
        ]
    case 48...:
        // 64px: still three, but the ghosts need more contrast and a heavier
        // line to survive landing on ~1.5 device pixels.
        fontSize = side * 0.40
        step = CGVector(dx: side * 0.180, dy: side * 0.160)
        let hairline = max(side * 0.028, 1.0)
        layers = [
            Layer(scale: 0.76, opacity: 0.34, lineWidth: hairline * 0.9, stepsBack: 2),
            Layer(scale: 0.88, opacity: 0.54, lineWidth: hairline, stepsBack: 1),
            Layer(scale: 1.00, opacity: 1.00, lineWidth: 0, stepsBack: 0),
        ]
    case 24...:
        // 32px: two copies. A third would be a 6px-tall outline — grey fuzz, not
        // a "20" — and it would steal the room the front copy needs.
        fontSize = side * 0.455
        step = CGVector(dx: side * 0.250, dy: side * 0.175)
        layers = [
            Layer(scale: 0.84, opacity: 0.62, lineWidth: 1.0, stepsBack: 1),
            Layer(scale: 1.00, opacity: 1.00, lineWidth: 0, stepsBack: 0),
        ]
    default:
        // 16px: the front "20" alone, as large as the tile allows. A cap height
        // of 7px is already at the edge of readable; anything behind it destroys
        // the only part of the mark still carrying meaning at this size.
        fontSize = side * 0.56
        step = .zero
        layers = [Layer(scale: 1.00, opacity: 1.00, lineWidth: 0, stepsBack: 0)]
    }

    // Below 48px the stems of the bold face land on about one pixel and grey
    // out; the heavy face keeps them dark enough to read as type.
    let weight: NSFont.Weight = side < 48 ? .heavy : .bold
    let (paths, union) = stack(fontSize: fontSize, step: step, layers: layers, weight: weight)

    // Centre the stack's ink in the square, with a small downward nudge: the
    // ghosts read lighter than the solid copy, so a purely geometric centre
    // sits visibly high.
    var move = CGAffineTransform(
        translationX: (side - union.width) / 2 - union.minX,
        y: (side - union.height) / 2 - union.minY - side * 0.012)
    let placed = paths.map { $0.copy(using: &move)! }

    render(
        paths: placed, layers: layers,
        halo: side >= 48 ? side * 0.021 : 0.6,
        ink: CGColor(red: 0.969, green: 0.973, blue: 0.984, alpha: 1), in: context)
}

// MARK: - Menu bar glyph

/// 18pt is the conventional height for an `NSStatusItem` image. The ink inside
/// is deliberately smaller: the menu bar's own font has a cap height near 10pt,
/// and a glyph filling all 18 shouts next to the system's own items.
let menuBarHeight: CGFloat = 18
let menuBarFontSize = menuBarHeight * 0.66
/// Points, not a font-size percentage. 1.1pt is 2.2 device pixels on a Retina
/// display: heavy enough that the hollow "20" does not dissolve, light enough
/// that the counters of the zeros stay open.
let menuBarHairline: CGFloat = 1.0

/// Enabled is a solid "20" with one outlined "20" ghosted behind it; disabled is
/// a single hollow "20".
func menuBarLayers(enabled: Bool) -> (CGVector, [Layer]) {
    if enabled {
        return (
            CGVector(dx: menuBarHeight * 0.26, dy: menuBarHeight * 0.16),
            [
                Layer(scale: 0.82, opacity: 0.55, lineWidth: menuBarHairline * 0.9, stepsBack: 1),
                Layer(scale: 1.00, opacity: 1.00, lineWidth: 0, stepsBack: 0),
            ]
        )
    }
    return (.zero, [Layer(scale: 1, opacity: 1, lineWidth: menuBarHairline, stepsBack: 0)])
}

/// The layout of one state: its paths, the box of the front "20" alone, and the
/// box of everything it inks.
func menuBarStack(enabled: Bool)
    -> (paths: [CGPath], layers: [Layer], front: CGRect, union: CGRect)
{
    let (step, layers) = menuBarLayers(enabled: enabled)
    let (paths, union) = stack(
        fontSize: menuBarFontSize, step: step, layers: layers, weight: .bold)
    // Deliberately the bare glyph box, without the stroke's half line width: it
    // has to be the same anchor in both states, and only one of them is hollow.
    return (paths, layers, paths[paths.count - 1].boundingBoxOfPath, union)
}

/// Where the front "20" sits, in a canvas shared by both states.
///
/// The two states must put the front "20" in exactly the same place, or the mark
/// visibly jumps every time Reminders is toggled. Centring each state on its own
/// ink would do exactly that: the enabled state's ink includes the ghost reaching
/// up and to the right, so centring it drags the solid "20" down and left.
///
/// So: one canvas, wide enough for the enabled state's ink, and a single
/// front-glyph position used by both, chosen to split the difference between
/// what each state would want on its own.
let (menuBarSize, menuBarAnchor): (CGSize, CGPoint) = {
    let on = menuBarStack(enabled: true)
    let off = menuBarStack(enabled: false)
    let size = CGSize(width: (on.union.width + 2.4).rounded(.up), height: menuBarHeight)

    /// Where this state's front glyph would go if the state were centred on its
    /// own ink.
    func centred(_ front: CGRect, _ union: CGRect) -> CGPoint {
        CGPoint(
            x: (size.width - union.width) / 2 + (front.minX - union.minX),
            y: (size.height - union.height) / 2 + (front.minY - union.minY))
    }
    // Horizontally, the average of the two. The enabled state is wider, so no one
    // position centres both; splitting leaves each about 0.7pt off its own
    // centre, which is invisible, rather than leaving the disabled state — the
    // one the app launches in — visibly off to one side.
    //
    // Vertically, halfway between centring the front glyph, which leaves the
    // ghost crowding the top edge, and centring the enabled state's whole ink,
    // which sits the "20" itself below the menu bar's own text.
    let anchor = CGPoint(
        x: (centred(on.front, on.union).x + centred(off.front, off.union).x) / 2,
        y: ((size.height - on.front.height) / 2 + centred(on.front, on.union).y) / 2)
    return (size, anchor)
}()

/// Template artwork: solid black on transparency, recoloured by macOS for light,
/// dark and tinted menu bars. Never use colour here.
func drawMenuBarGlyph(enabled: Bool, size: CGSize, in context: CGContext) {
    let (paths, layers, front, union) = menuBarStack(enabled: enabled)
    var move = CGAffineTransform(
        translationX: menuBarAnchor.x - front.minX, y: menuBarAnchor.y - front.minY)
    let placed = paths.map { $0.copy(using: &move)! }

    let inked = union.applying(move).insetBy(dx: -menuBarHairline / 2, dy: -menuBarHairline / 2)
    if !CGRect(origin: .zero, size: size).contains(inked) {
        FileHandle.standardError.write(
            "  WARNING: the \(enabled ? "on" : "off") glyph overflows \(size): \(inked)\n"
                .data(using: .utf8)!)
    }
    render(
        paths: placed, layers: layers, halo: menuBarHairline * 0.65,
        ink: CGColor(gray: 0, alpha: 1), in: context)
}

// MARK: - Output

func writePNG(side: CGFloat, to url: URL, draw: (CGContext) -> Void) {
    let context = CGContext(
        data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    draw(context)
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(url.lastPathComponent)")
}

func writePDF(size: CGSize, to url: URL, draw: (CGContext) -> Void) {
    var box = CGRect(origin: .zero, size: size)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    draw(context)
    context.endPDFPage()
    context.closePDF()
    print("wrote \(url.lastPathComponent)")
}

// App icon: the sizes an .appiconset needs.
let iconDir = assets.appending(path: "AppIcon.appiconset")
try! FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
for side in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(side: CGFloat(side), to: iconDir.appending(path: "icon_\(side).png")) {
        drawAppIcon(side: CGFloat(side), in: $0)
    }
}

// Menu bar glyphs: vector PDFs, so they stay crisp at any menu bar scale.
for (name, enabled) in [("MenuBarOn", true), ("MenuBarOff", false)] {
    let dir = assets.appending(path: "\(name).imageset")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    writePDF(size: menuBarSize, to: dir.appending(path: "\(name).pdf")) {
        drawMenuBarGlyph(enabled: enabled, size: menuBarSize, in: $0)
    }
}

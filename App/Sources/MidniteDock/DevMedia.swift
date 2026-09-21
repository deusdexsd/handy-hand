import Foundation
import AVFoundation
import AppKit

/// Generator danych testowych: syntetyczne SFX o różnych kształtach i długościach, krótkie wideo, atrapa biblioteki FCP.
enum DevMedia {
    struct Spec { let name: String; let seconds: Double; let shape: String }
    static let sfx: [Spec] = [
        .init(name: "whoosh_fast", seconds: 0.8, shape: "swell"), .init(name: "whoosh_long", seconds: 2.4, shape: "swell"),
        .init(name: "whoosh_soft", seconds: 1.4, shape: "swell"), .init(name: "impact_deep", seconds: 1.9, shape: "impact"),
        .init(name: "impact_short", seconds: 0.5, shape: "impact"), .init(name: "impact_huge", seconds: 3.5, shape: "impact"),
        .init(name: "riser_tension", seconds: 4.2, shape: "riser"), .init(name: "riser_short", seconds: 2.1, shape: "riser"),
        .init(name: "click_ui", seconds: 0.3, shape: "click"), .init(name: "click_double", seconds: 0.6, shape: "click"),
        .init(name: "boom_low", seconds: 3.1, shape: "boom"), .init(name: "boom_sub", seconds: 5.5, shape: "boom"),
        .init(name: "swish_air", seconds: 0.9, shape: "swell"), .init(name: "beep_tone", seconds: 1.0, shape: "tone"),
        .init(name: "drone_pad", seconds: 7.0, shape: "tone"),
    ]

    static func generate(into dir: URL) throws {
        let fm = FileManager.default
        let sfxDir = dir.appendingPathComponent("SFX"), brollDir = dir.appendingPathComponent("B-roll")
        let lib = dir.appendingPathComponent("DevLibrary.fcpbundle/Zdarzenie A/Original Media")
        let render = dir.appendingPathComponent("DevLibrary.fcpbundle/Zdarzenie A/Render Files")
        for d in [sfxDir, brollDir, lib, render] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        for (i, s) in sfx.enumerated() { try tone(s, to: sfxDir.appendingPathComponent("\(s.name).wav"), seed: i + 1) }
        try tone(.init(name: "theme_calm_music", seconds: 48, shape: "tone"), to: sfxDir.appendingPathComponent("theme_calm_music.wav"), seed: 90)
        try tone(.init(name: "loop_dark_music", seconds: 95, shape: "tone"), to: sfxDir.appendingPathComponent("loop_dark_music.wav"), seed: 91)
        let pics = dir.appendingPathComponent("Zdjecia"); try fm.createDirectory(at: pics, withIntermediateDirectories: true)
        for (i, n) in ["plan_sesji", "logo_midnite", "kadr_miasto"].enumerated() { try image(n, hue: 0.1 + 0.3 * Double(i), w: 1920 - i * 320, h: 1080 - i * 180, to: pics.appendingPathComponent("\(n).\(i == 1 ? "png" : "jpg")")) }
        try tone(.init(name: "lib_hit", seconds: 1.2, shape: "impact"), to: lib.appendingPathComponent("lib_hit.wav"), seed: 40)
        try tone(.init(name: "lib_render_decoy", seconds: 1, shape: "click"), to: render.appendingPathComponent("render_decoy.wav"), seed: 41)
        try video("city_night", 4, hue: 0.62, to: brollDir.appendingPathComponent("city_night.mov"))
        try video("handheld_walk", 3.2, hue: 0.08, to: brollDir.appendingPathComponent("handheld_walk.mov"))
        try video("drone_coast", 18, hue: 0.5, to: brollDir.appendingPathComponent("drone_coast.mov"))
        try video("lib_broll", 2.4, hue: 0.85, to: lib.appendingPathComponent("lib_broll.mov"))
        // Folder z kopiami: 3 prawdziwe duplikaty (ta sama nazwa i długość) + 1 ta sama nazwa, ale inna długość (NIE duplikat)
        let backup = dir.appendingPathComponent("SFX Backup")
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        for n in ["whoosh_fast", "impact_deep", "click_ui"] {
            let dst = backup.appendingPathComponent("\(n).wav")
            try? fm.removeItem(at: dst); try fm.copyItem(at: sfxDir.appendingPathComponent("\(n).wav"), to: dst)
        }
        try tone(.init(name: "boom_low", seconds: 4.4, shape: "boom"), to: backup.appendingPathComponent("boom_low.wav"), seed: 77)
        try FileManager.default.createDirectory(at: brollDir.appendingPathComponent("Miasto"), withIntermediateDirectories: true)
        try video("street_rain", 5.5, hue: 0.7, to: brollDir.appendingPathComponent("Miasto/street_rain.mov"))
    }

    static func env(_ shape: String, _ t: Double) -> Double {
        switch shape {
        case "swell": return pow(sin(.pi * min(1, t * 0.98)), 1.6)
        case "impact": return t < 0.02 ? t / 0.02 : exp(-(t - 0.02) * 5.5)
        case "riser": return pow(t, 2.2)
        case "click": return exp(-t * 9)
        case "boom": return t < 0.03 ? t / 0.03 : exp(-(t - 0.03) * 2.6)
        default: return min(1, t * 30) * min(1, (1 - t) * 12)
        }
    }

    static func tone(_ s: Spec, to url: URL, seed: Int) throws {
        let sr = 44100.0
        let f = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
        let n = AVAudioFrameCount(sr * s.seconds)
        let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: n)!; b.frameLength = n
        var rng = SystemRandomNumberGenerator(); _ = rng
        var state = UInt64(seed) &* 6364136223846793005 &+ 1442695040888963407
        var lp: Double = 0
        for i in 0..<Int(n) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let nz = Double(Int64(bitPattern: state >> 11) % 2000) / 1000 - 1
            let t = Double(i) / Double(n)
            let e = env(s.shape, t)
            lp += (nz - lp) * (s.shape == "riser" ? 0.35 : 0.12)
            var v = lp * e * 1.6
            switch s.shape {
            case "impact": v += sin(2 * .pi * 55 * Double(i) / sr) * e * 0.7
            case "boom": v = sin(2 * .pi * (38 + 20 * (1 - t)) * Double(i) / sr) * e * 0.8 + lp * e * 0.3
            case "tone": v = sin(2 * .pi * (s.name.contains("drone") ? 110 : 880) * Double(i) / sr) * e * 0.35
            case "click": v = nz * e * 0.5
            default: break
            }
            b.floatChannelData![0][i] = Float(max(-1, min(1, v)) * 0.6)
        }
        try f.write(from: b)
    }

    static func image(_ name: String, hue: Double, w: Int, h: Int, to url: URL) throws {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor(hue: hue, saturation: 0.4, brightness: 0.55, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(NSColor(white: 1, alpha: 0.8).cgColor); ctx.fill(CGRect(x: w / 8, y: h / 3, width: w / 3, height: h / 4))
        let type = url.pathExtension == "png" ? "public.png" : "public.jpeg"
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        if !CGImageDestinationFinalize(dest) { throw CocoaError(.fileWriteUnknown) }
    }

    static func video(_ name: String, _ seconds: Double, hue: Double, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let (w, h, fps) = (640, 360, 25)
        let frames = Int(seconds * Double(fps))
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for f in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, ad.pixelBufferPool!, &pb)
            guard let buf = pb else { continue }
            CVPixelBufferLockBaseAddress(buf, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            let p = Double(f) / Double(frames)
            ctx.setFillColor(NSColor(hue: (hue + p * 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 0.5, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(NSColor(white: 1, alpha: 0.85).cgColor)
            ctx.fill(CGRect(x: 30 + p * Double(w - 130), y: 60, width: 60, height: 60))
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            (name.uppercased() as NSString).draw(at: CGPoint(x: 24, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 38, weight: .bold), .foregroundColor: NSColor.white])
            NSGraphicsContext.restoreGraphicsState()
            CVPixelBufferUnlockBaseAddress(buf, [])
            ad.append(buf, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}

import AVFoundation
import AppKit
import DockCore

/// Generuje malutkie pliki testowe (bez zależności): 1 s tonu WAV i 2 s wideo H.264 z numerem klatki.
enum TestMedia {
    static let dir = Log.root.appendingPathComponent("TestMedia")
    static let sfxURL = dir.appendingPathComponent("probe_sfx_beep.wav")
    static let videoURL = dir.appendingPathComponent("probe_broll_counter.mov")

    static var assets: [ProbeAsset] {
        [ProbeAsset(name: "probe_sfx_beep", url: sfxURL, kind: .audio, seconds: 1),
         ProbeAsset(name: "probe_broll_counter", url: videoURL, kind: .video, seconds: 2)]
    }

    static func ensure() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: sfxURL.path) { try makeTone(at: sfxURL) }
        if !FileManager.default.fileExists(atPath: videoURL.path) { try makeVideo(at: videoURL) }
    }

    static func makeTone(at url: URL, seconds: Double = 1.0, hz: Double = 880) throws {
        let sr = 48000.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(sr * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<Int(file.processingFormat.channelCount) {
            let p = buf.floatChannelData![ch]
            for i in 0..<Int(frames) {
                let t = Double(i) / sr
                let env = min(1, t * 40) * min(1, (seconds - t) * 8) // krótki fade in/out
                p[i] = Float(sin(2 * .pi * hz * t) * 0.4 * env)
            }
        }
        try file.write(from: buf)
    }

    static func makeVideo(at url: URL, frames: Int = 50, fps: Int32 = 25) throws {
        try? FileManager.default.removeItem(at: url)
        let (w, h) = (1920, 1080)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for f in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            guard let buffer = pb else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            let hue = CGFloat(f) / CGFloat(frames)
            ctx.setFillColor(NSColor(hue: hue, saturation: 0.7, brightness: 0.55, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 60 + f * 34, y: 120, width: 160, height: 160))
            let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            ("MIDNITEDOCK PROBE  \(f)" as NSString).draw(at: CGPoint(x: 80, y: 600), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 110, weight: .bold), .foregroundColor: NSColor.white,
            ])
            NSGraphicsContext.restoreGraphicsState()
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: fps))
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}

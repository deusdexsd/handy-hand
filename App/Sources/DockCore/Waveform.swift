import Foundation
import AVFoundation
import Accelerate

/// Peaki audio (0...1, znormalizowane) do rysowania waveformu; cache na dysku.
public enum WaveformPeaks {
    public static func compute(url: URL, bins: Int = 240) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return [] }
        let total = file.length
        let chunk: AVAudioFrameCount = 32768
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { return [] }
        var peaks = [Float](repeating: 0, count: bins)
        var pos: Int64 = 0
        let channels = Int(file.processingFormat.channelCount)
        while pos < total {
            do { try file.read(into: buf, frameCount: chunk) } catch { break }
            let n = Int(buf.frameLength)
            if n == 0 { break }
            guard let data = buf.floatChannelData else { break }
            var off = 0
            while off < n {
                let len = min(256, n - off)
                var m: Float = 0
                for c in 0..<channels {
                    var v: Float = 0
                    vDSP_maxmgv(data[c] + off, 1, &v, vDSP_Length(len))
                    m = max(m, v)
                }
                let bin = min(bins - 1, Int((pos + Int64(off)) * Int64(bins) / total))
                peaks[bin] = max(peaks[bin], m)
                off += len
            }
            pos += Int64(n)
        }
        let top = peaks.max() ?? 0
        return top > 0 ? peaks.map { $0 / top } : peaks
    }

    static func cacheURL(for url: URL, modified: Date, size: Int64) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MidniteDock/peaks", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let key = "\(url.path)|\(modified.timeIntervalSince1970)|\(size)"
        var h: UInt64 = 1469598103934665603
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return base.appendingPathComponent(String(h, radix: 16) + ".peaks")
    }

    public static func cached(url: URL, modified: Date, size: Int64) -> [Float] {
        let c = cacheURL(for: url, modified: modified, size: size)
        if let d = try? Data(contentsOf: c), d.count % 4 == 0, d.count > 0 {
            return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        let p = compute(url: url)
        if !p.isEmpty { p.withUnsafeBufferPointer { try? Data(buffer: $0).write(to: c) } }
        return p
    }
}

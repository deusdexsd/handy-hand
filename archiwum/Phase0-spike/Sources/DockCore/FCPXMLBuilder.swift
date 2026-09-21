import Foundation

/// Plik testowy / asset użytkownika opisany na potrzeby FCPXML.
public struct ProbeAsset: Sendable, Equatable {
    public enum Kind: String, Sendable { case audio, video }
    public var name: String
    public var url: URL
    public var kind: Kind
    /// Pełne sekundy (dla prostoty: długości wyrównane do klatek 25 fps).
    public var seconds: Int

    public init(name: String, url: URL, kind: Kind, seconds: Int) {
        self.name = name
        self.url = url
        self.kind = kind
        self.seconds = seconds
    }
}

/// Generator FCPXML 1.13 (FCP 12.3 zna do 1.14). Timeline 1080p25.
public enum FCPXMLBuilder {
    public static let version = "1.13"

    static func t(_ seconds: Int) -> String { seconds == 0 ? "0s" : "\(seconds * 2500)/2500s" }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func assetXML(id: String, _ a: ProbeAsset) -> String {
        let common = "id=\"\(id)\" name=\"\(esc(a.name))\" start=\"0s\" duration=\"\(t(a.seconds))\""
        let rep = "<media-rep kind=\"original-media\" src=\"\(esc(a.url.absoluteString))\"/>"
        switch a.kind {
        case .video:
            return "    <asset \(common) hasVideo=\"1\" format=\"r1\" videoSources=\"1\">\n      \(rep)\n    </asset>"
        case .audio:
            return "    <asset \(common) hasAudio=\"1\" audioSources=\"1\" audioChannels=\"2\" audioRate=\"48000\">\n      \(rep)\n    </asset>"
        }
    }

    static func clipAttrs(ref: String, _ a: ProbeAsset, offset: Int = 0, lane: Int? = nil) -> String {
        let laneAttr = lane.map { " lane=\"\($0)\"" } ?? ""
        let fmt = a.kind == .video ? " format=\"r1\"" : ""
        return "ref=\"\(ref)\" name=\"\(esc(a.name))\"\(laneAttr) offset=\"\(t(offset))\" start=\"0s\" duration=\"\(t(a.seconds))\"\(fmt) tcFormat=\"NDF\""
    }

    static func clipXML(ref: String, _ a: ProbeAsset, indent: String) -> String {
        "\(indent)<asset-clip \(clipAttrs(ref: ref, a))/>"
    }

    static func document(resources: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="\(version)">
          <resources>
            <format id="r1" name="FFVideoFormat1080p25" frameDuration="100/2500s" width="1920" height="1080" colorSpace="1-1-1 (Rec. 709)"/>
        \(resources)
          </resources>
        \(body)
        </fcpxml>
        """
    }

    /// (4a) Import klipów do zdarzenia: ląduje w Event Browser, nie na timeline.
    public static func eventImport(eventName: String, assets: [ProbeAsset]) -> String {
        let res = assets.enumerated().map { assetXML(id: "r\($0.offset + 2)", $0.element) }.joined(separator: "\n")
        let clips = assets.enumerated().map { clipXML(ref: "r\($0.offset + 2)", $0.element, indent: "      ") }.joined(separator: "\n")
        return document(resources: res, body: """
          <library>
            <event name="\(esc(eventName))">
        \(clips)
            </event>
          </library>
        """)
    }

    /// (4b) Nowy projekt z compound clipem (wideo + SFX przypięty jako connected clip):
    /// realny sposób na "wstaw sekwencję" przez FCPXML - powstaje NOWY projekt w zdarzeniu.
    public static func compoundProject(eventName: String, projectName: String,
                                       video: ProbeAsset, sfx: ProbeAsset) -> String {
        let compound = """
            <media id="r4" name="MidniteDock Compound">
              <sequence format="r1" duration="\(t(video.seconds))" tcStart="0s" tcFormat="NDF">
                <spine>
                  <asset-clip \(clipAttrs(ref: "r2", video))>
                    <asset-clip \(clipAttrs(ref: "r3", sfx, lane: 1))/>
                  </asset-clip>
                </spine>
              </sequence>
            </media>
        """
        let res = [assetXML(id: "r2", video), assetXML(id: "r3", sfx), compound].joined(separator: "\n")
        return document(resources: res, body: """
          <library>
            <event name="\(esc(eventName))">
              <project name="\(esc(projectName))">
                <sequence format="r1" duration="\(t(video.seconds))" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
                  <spine>
                    <ref-clip ref="r4" name="MidniteDock Compound" offset="0s" duration="\(t(video.seconds))"/>
                  </spine>
                </sequence>
              </project>
            </event>
          </library>
        """)
    }
}

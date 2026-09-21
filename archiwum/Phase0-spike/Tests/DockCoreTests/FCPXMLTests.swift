import XCTest
@testable import DockCore

/// Waliduje wygenerowany FCPXML względem DTD dostarczonego z Final Cut Pro (xmllint).
final class FCPXMLTests: XCTestCase {
    let dtd = "/Applications/Final Cut Pro.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv1_13.dtd"
    let sfx = ProbeAsset(name: "sfx & \"whoosh\"", url: URL(fileURLWithPath: "/tmp/a b/sfx.wav"), kind: .audio, seconds: 1)
    let vid = ProbeAsset(name: "broll", url: URL(fileURLWithPath: "/tmp/broll.mov"), kind: .video, seconds: 2)

    func validate(_ xml: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: dtd), "brak DTD z FCP")
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".fcpxml")
        try xml.write(to: f, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: f) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
        p.arguments = ["--noout", "--dtdvalid", URL(fileURLWithPath: dtd).absoluteString, f.path] // URL: ścieżka ma spacje
        let err = Pipe(); p.standardError = err
        try p.run(); p.waitUntilExit()
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(p.terminationStatus, 0, "xmllint: \(msg)", file: file, line: line)
    }

    func testEventImportValidatesAgainstFCPDTD() throws {
        try validate(FCPXMLBuilder.eventImport(eventName: "Probe", assets: [sfx, vid]))
    }

    func testCompoundProjectValidatesAgainstFCPDTD() throws {
        try validate(FCPXMLBuilder.compoundProject(eventName: "Probe", projectName: "P", video: vid, sfx: sfx))
    }

    func testPathsAreEscapedAndPercentEncoded() {
        let xml = FCPXMLBuilder.eventImport(eventName: "E", assets: [sfx])
        XCTAssertTrue(xml.contains("file:///tmp/a%20b/sfx.wav"))
        XCTAssertTrue(xml.contains("sfx &amp; &quot;whoosh&quot;"))
    }
}

import XCTest
import AVFoundation
@testable import DockCore

func item(_ name: String, _ d: Double, _ kind: MediaKind = .audio, src: UUID = UUID(), group: String? = nil, created: Date = Date()) -> MediaItem {
    MediaItem(path: "/x/\(name).wav", name: name, ext: "wav", kind: kind, duration: d, size: 1, created: created, modified: created, sourceID: src, group: group)
}

final class QueryTests: XCTestCase {
    var org = Organization()
    let items = [item("whoosh_fast", 0.8), item("impact_big", 1.9), item("riser_long", 4.2),
                 item("city_night", 4.0, .video), item("drone_long", 20, .video)]

    func testDurationRangeBoundaries() {
        let r = DurationRange(name: "1–3 s", kind: .audio, minSeconds: 1, maxSeconds: 3, shade: 0.5)
        XCTAssertFalse(r.contains(0.99)); XCTAssertTrue(r.contains(1)); XCTAssertTrue(r.contains(2.99)); XCTAssertFalse(r.contains(3))
        XCTAssertTrue(DurationRange(name: "", kind: .audio, minSeconds: 3, maxSeconds: nil, shade: 1).contains(999))
    }

    func testAutoName() {
        XCTAssertEqual(DurationRange.autoName(min: 0, max: 1), "Do 1 s")
        XCTAssertEqual(DurationRange.autoName(min: 1, max: 3), "1–3 s")
        XCTAssertEqual(DurationRange.autoName(min: 3, max: nil), "Powyżej 3 s")
        XCTAssertEqual(DurationRange.autoName(min: 0, max: 1.5), "Do 1,5 s")
    }

    func testSmartDurationIsPerKind() {
        var cfg = ViewConfig()
        let audioShort = org.durationRanges.first { $0.kind == .audio && $0.maxSeconds == 1 }!
        cfg.category = .duration(audioShort.id)
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).map(\.name), ["whoosh_fast"])
        let videoLong = org.durationRanges.first { $0.kind == .video && $0.maxSeconds == nil }!
        cfg.category = .duration(videoLong.id)
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).map(\.name), ["drone_long"])
    }

    func testKeywordRuleAndSearchWithinCategory() {
        var cfg = ViewConfig()
        cfg.category = .keyword(org.keywordRules.first { $0.name == "Whoosh" }!.id)
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).map(\.name), ["whoosh_fast"])
        cfg.category = .all
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "LONG", org: org).map(\.name).sorted(), ["drone_long", "riser_long"])
        cfg.category = .kind(.video)
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "long", org: org).map(\.name), ["drone_long"])
    }

    func testFavoritesCollectionsTagsFilters() {
        org.favorites = [items[0].path]
        org.collections = [MediaCollection(name: "Intro", paths: [items[1].path, items[2].path])]
        org.tags[items[2].path] = ["dramat"]
        var cfg = ViewConfig()
        cfg.category = .favorites
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).count, 1)
        cfg.category = .collection(org.collections[0].id)
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).count, 2)
        cfg.filters.tag = "dramat"
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).map(\.name), ["riser_long"])
        cfg.filters = Filters(kind: .video)
        cfg.category = .all
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).count, 2)
        XCTAssertTrue(cfg.filters.isActive)
    }

    func testDateFilterAndSort() {
        let old = item("old", 1, created: Date(timeIntervalSinceNow: -40 * 86400))
        let new = item("new", 2)
        var cfg = ViewConfig()
        cfg.filters.withinDays = 7
        XCTAssertEqual(LibraryQuery.apply([old, new], config: cfg, search: "", org: org).map(\.name), ["new"])
        cfg.filters = .none; cfg.sort = .duration; cfg.ascending = false
        XCTAssertEqual(LibraryQuery.apply([old, new], config: cfg, search: "", org: org).map(\.name), ["new", "old"])
    }

    func testShadeUsesUserRanges() {
        XCTAssertEqual(LibraryQuery.shade(for: items[0], ranges: org.durationRanges), 0.35)
        XCTAssertEqual(LibraryQuery.shade(for: items[2], ranges: org.durationRanges), 0.9)
        var custom = org.durationRanges
        custom.append(DurationRange(name: "Długie SFX", kind: .audio, minSeconds: 10, maxSeconds: nil, shade: 1))
        XCTAssertEqual(LibraryQuery.shade(for: item("long", 12), ranges: custom), 0.9) // pierwszy pasujący (>3 s) wygrywa
    }
}

final class DuplicateTests: XCTestCase {
    let a = UUID(), b = UUID()
    func item2(_ name: String, _ d: Double, src: UUID, size: Int64 = 1, path: String? = nil, kind: MediaKind = .audio) -> MediaItem {
        var i = item(name, d, kind, src: src); i.size = size; i.path = path ?? "/\(src)/\(name).wav"; return i
    }

    func testSameNameAndDurationCollapseToOnePerSourcePriority() {
        let items = [item2("Whoosh", 1.234, src: b), item2("whoosh", 1.2349, src: a), item2("other", 1, src: a)]
        let idx = DuplicateIndex.build(items, strict: false)
        let out = Deduper.collapse(items, index: idx, sourceOrder: [a, b])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.first { $0.name.lowercased() == "whoosh" }!.sourceID, a)   // źródło wyżej na liście wygrywa
    }

    func testDifferentDurationOrKindAreNotDuplicates() {
        let items = [item2("hit", 1.0, src: a), item2("hit", 1.5, src: b), item2("hit", 1.0, src: b, path: "/v/hit.mov", kind: .video)]
        let idx = DuplicateIndex.build(items, strict: false)
        XCTAssertEqual(Deduper.collapse(items, index: idx, sourceOrder: [a, b]).count, 3)
    }

    func testStrictModeAlsoNeedsSameSizeAndLargerWinsOnTie() {
        let items = [item2("x", 1, src: a, size: 100), item2("x", 1, src: a, size: 200, path: "/a/x2.wav")]
        XCTAssertEqual(Deduper.collapse(items, index: DuplicateIndex.build(items, strict: true), sourceOrder: [a]).count, 2)
        let loose = Deduper.collapse(items, index: DuplicateIndex.build(items, strict: false), sourceOrder: [a])
        XCTAssertEqual(loose.count, 1); XCTAssertEqual(loose[0].size, 200)
    }

    func testCategoryScopedDedupAndGroupAwareFavorites() {
        let items = [item2("boom", 2, src: a), item2("boom", 2, src: b)]
        let idx = DuplicateIndex.build(items, strict: false)
        var org = Organization(); org.favorites = [items[1].path]     // ulubiona jest kopia z drugiego źródła
        var cfg = ViewConfig()
        // Wszystko: raz, a ulubione dotyczy całej grupy niezależnie od tego, która kopia jest pokazana
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org, dups: idx, hideDuplicates: true, sourceOrder: [a, b]).count, 1)
        cfg.category = .favorites
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org, dups: idx, hideDuplicates: true, sourceOrder: [a, b]).count, 1)
        // Kategoria źródła b widzi swoją kopię, mimo że w "Wszystko" wygrywa a
        cfg.category = .source(b)
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org, dups: idx, hideDuplicates: true, sourceOrder: [a, b]).map(\.sourceID), [b])
        XCTAssertEqual(LibraryQuery.count(items, category: .all, org: org, dups: idx, hideDuplicates: true, sourceOrder: [a, b]), 1)
        XCTAssertEqual(LibraryQuery.count(items, category: .all, org: org, dups: idx, hideDuplicates: false), 2)
        XCTAssertEqual(idx.copies(of: items[0].path), 2)
    }
}

final class ClassAndImageTests: XCTestCase {
    func testAudioSplitsIntoSfxAndMusicByThreshold() {
        var org = Organization()
        XCTAssertEqual(org.mediaClass(of: item("a", 20)), .sfx)          // granica włącznie
        XCTAssertEqual(org.mediaClass(of: item("b", 20.5)), .music)
        org.sfxMaxSeconds = 45
        XCTAssertEqual(org.mediaClass(of: item("b", 30)), .sfx)
        XCTAssertEqual(org.mediaClass(of: item("v", 3, .video)), .video)
        XCTAssertEqual(org.mediaClass(of: item("i", 0, .image)), .image)
    }

    func testManualOverrideBeatsThresholdAndIgnoresNonAudioClasses() {
        var org = Organization()
        let long = item("song", 200), short = item("hit", 1)
        org.classOverrides[long.path] = .sfx; org.classOverrides[short.path] = .music
        XCTAssertEqual(org.mediaClass(of: long), .sfx); XCTAssertEqual(org.mediaClass(of: short), .music)
        let vid = item("v", 3, .video); org.classOverrides[vid.path] = .sfx
        XCTAssertEqual(org.mediaClass(of: vid), .video)                   // wideo nie zmienia klasy
    }

    func testClassCategoriesAndRangesUseClass() {
        var org = Organization(); org.sfxMaxSeconds = 20
        let items = [item("hit", 1), item("loop", 30), item("song", 200), item("clip", 4, .video), item("pic", 0, .image)]
        var cfg = ViewConfig()
        for (c, n) in [(MediaClass.sfx, 1), (.music, 2), (.video, 1), (.image, 1)] {
            cfg.category = .klass(c)
            XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).count, n, "\(c)")
        }
        let musicShort = org.durationRanges.first { $0.mediaClass == .music && $0.maxSeconds == 60 }!
        cfg.category = .duration(musicShort.id)
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).map(\.name), ["loop"])
        XCTAssertEqual(LibraryQuery.shade(for: items[2], org: org), 0.9)   // 200 s to muzyka "Powyżej 3 min"
        cfg.category = .all; cfg.filters.klass = .music
        XCTAssertEqual(LibraryQuery.apply(items, config: cfg, search: "", org: org).count, 2)
    }

    func testLegacyRangesMigrateToSfxAndGetMusicDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let rid = UUID().uuidString
        let json = "{\"org\":{\"durationRanges\":[{\"id\":\"" + rid + "\",\"name\":\"Do 1 s\",\"kind\":\"audio\",\"minSeconds\":0,\"maxSeconds\":1,\"shade\":0.4}]}}"
        try json.write(to: url, atomically: true, encoding: .utf8)
        let u = UserDataStore(url: url).load()
        XCTAssertEqual(u.org.durationRanges.first { $0.id.uuidString == rid }?.mediaClass, .sfx)
        XCTAssertEqual(u.org.durationRanges.filter { $0.mediaClass == .music }.count, 3)
        XCTAssertEqual(u.schemaVersion, 2)
        // po zapisie i ponownym odczycie nie dokładamy muzyki drugi raz
        UserDataStore(url: url).save(u)
        XCTAssertEqual(UserDataStore(url: url).load().org.durationRanges.filter { $0.mediaClass == .music }.count, 3)
    }

    func testAutoNameUsesMinutes() {
        XCTAssertEqual(DurationRange.autoName(min: 0, max: 60), "Do 1 min")
        XCTAssertEqual(DurationRange.autoName(min: 60, max: 180), "1–3 min")
        XCTAssertEqual(DurationRange.autoName(min: 180, max: nil), "Powyżej 3 min")
        XCTAssertEqual(DurationRange.autoName(min: 90, max: 150), "90–150 s")
    }

    func testImagesNotCollapsedWhenDimensionsDiffer() {
        func img(_ w: Int, src: UUID) -> MediaItem {
            var i = MediaItem(path: "/\(src)/IMG_001.jpg", name: "IMG_001", ext: "jpg", kind: .image, duration: 0, size: Int64(w) * 10,
                              created: Date(), modified: Date(), sourceID: src, group: nil, pixelWidth: w, pixelHeight: 1080)
            i.size = Int64(w) * 10; return i
        }
        let a = UUID(), b = UUID()
        let two = [img(1920, src: a), img(4000, src: b)]
        XCTAssertEqual(Deduper.collapse(two, index: DuplicateIndex.build(two, strict: false), sourceOrder: [a, b]).count, 2)
        let same = [img(1920, src: a), img(1920, src: b)]
        XCTAssertEqual(Deduper.collapse(same, index: DuplicateIndex.build(same, strict: false), sourceOrder: [a, b]).count, 1)
    }

    func testIndexerReadsImagesAndSingleFileSources() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("img-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = dir.appendingPathComponent("pic.png")
        let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let dest = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        try writeTone(dir.appendingPathComponent("a.wav"), seconds: 1)
        try "x".write(to: dir.appendingPathComponent("x.svg"), atomically: true, encoding: .utf8)
        let folder = await Indexer().scan(Source(name: "F", path: dir.path, kind: .folder), existing: [:])
        XCTAssertEqual(Set(folder.map(\.name)), ["pic", "a"])            // svg pominięty
        let p = folder.first { $0.name == "pic" }!
        XCTAssertEqual(p.kind, .image); XCTAssertEqual(p.pixelWidth, 64); XCTAssertEqual(p.pixelHeight, 32); XCTAssertEqual(p.duration, 0)
        // źródło z pojedynczymi plikami (bez folderu)
        let files = Source(name: "Pliki", path: "", kind: .files, filePaths: [png.path, dir.appendingPathComponent("a.wav").path, dir.appendingPathComponent("brak.wav").path])
        let items = await Indexer().scan(files, existing: [:])
        XCTAssertEqual(Set(items.map(\.name)), ["pic", "a"])
        XCTAssertEqual(files.watchPaths, [PathUtil.canonical(dir.path)].map { _ in dir.path }.sorted())
    }
}

final class ResizeTests: XCTestCase {
    let start = CGSize(width: 720, height: 460), screen = CGSize(width: 3008, height: 1692)

    func testCenteredPanelGrowsSymmetricallySoEdgeFollowsCursor() {
        let n = PanelResize.newSize(start: start, dx: 50, dy: 0, edges: .init(right: true), placement: .topCenter, screen: screen)
        XCTAssertEqual(n.width, 820)                              // 2 * 50: prawa krawędź idzie za kursorem
        let l = PanelResize.newSize(start: start, dx: -50, dy: 0, edges: .init(left: true), placement: .topCenter, screen: screen)
        XCTAssertEqual(l.width, 820)                              // lewa krawędź w lewo = szerzej
    }

    func testTopAnchoredHeightFollowsBottomEdge() {
        XCTAssertEqual(PanelResize.newSize(start: start, dx: 0, dy: -80, edges: .init(bottom: true), placement: .topCenter, screen: screen).height, 540)
        XCTAssertEqual(PanelResize.newSize(start: start, dx: 0, dy: 80, edges: .init(bottom: true), placement: .topCenter, screen: screen).height, 380)
    }

    func testBottomPlacementResizesFromTopEdge() {
        XCTAssertEqual(PanelResize.newSize(start: start, dx: 0, dy: 60, edges: .init(top: true), placement: .bottomCenter, screen: screen).height, 520)
        XCTAssertEqual(PanelResize.allowed(.init(top: true, bottom: true), placement: .bottomCenter), .init(top: true))
        XCTAssertEqual(PanelResize.allowed(.init(top: true, bottom: true), placement: .topCenter), .init(bottom: true))
    }

    func testCornerAnchoredPanelsOnlyResizeAwayFromTheCorner() {
        XCTAssertEqual(PanelResize.allowed(.init(left: true, right: true), placement: .topLeft), .init(right: true))
        XCTAssertEqual(PanelResize.allowed(.init(left: true, right: true), placement: .topRight), .init(left: true))
        XCTAssertEqual(PanelResize.newSize(start: start, dx: 40, dy: 0, edges: .init(right: true), placement: .topLeft, screen: screen).width, 760)   // 1:1, bez podwajania
    }

    func testClampedToMinimumAndScreen() {
        let tiny = PanelResize.newSize(start: start, dx: -900, dy: 900, edges: .init(right: true, bottom: true), placement: .topCenter, screen: screen)
        XCTAssertEqual(tiny, PanelResize.minSize)
        let huge = PanelResize.newSize(start: start, dx: 9000, dy: -9000, edges: .init(right: true, bottom: true), placement: .topCenter, screen: screen)
        XCTAssertEqual(huge, CGSize(width: 1600, height: 1000))
        let small = CGSize(width: 1000, height: 700)
        XCTAssertEqual(PanelResize.newSize(start: start, dx: 9000, dy: -9000, edges: .init(right: true, bottom: true), placement: .topCenter, screen: small),
                       CGSize(width: 968, height: 610))                     // nie większy niż ekran
    }
}

final class NavigationTests: XCTestCase {
    func testArrowsMoveWithinGridWithoutWrapping() {
        // 7 elementów, 3 kolumny: [0 1 2] [3 4 5] [6]
        XCTAssertEqual(GridNavigation.move(from: 4, count: 7, columns: 3, .right), 5)
        XCTAssertEqual(GridNavigation.move(from: 5, count: 7, columns: 3, .right), 6)      // idzie do następnego wiersza (jak Finder)
        XCTAssertEqual(GridNavigation.move(from: 6, count: 7, columns: 3, .right), 6)      // koniec: zostaje
        XCTAssertEqual(GridNavigation.move(from: 0, count: 7, columns: 3, .left), 0)
        XCTAssertEqual(GridNavigation.move(from: 4, count: 7, columns: 3, .up), 1)
        XCTAssertEqual(GridNavigation.move(from: 1, count: 7, columns: 3, .up), 1)         // pierwszy wiersz: zostaje
        XCTAssertEqual(GridNavigation.move(from: 1, count: 7, columns: 3, .down), 4)
        XCTAssertEqual(GridNavigation.move(from: 5, count: 7, columns: 3, .down), 6)       // niepełny wiersz: na ostatni element
        XCTAssertEqual(GridNavigation.move(from: 6, count: 7, columns: 3, .down), 6)
    }

    func testListModeAndEdgeCases() {
        XCTAssertEqual(GridNavigation.move(from: 2, count: 5, columns: 1, .down), 3)
        XCTAssertEqual(GridNavigation.move(from: 2, count: 5, columns: 1, .up), 1)
        XCTAssertEqual(GridNavigation.move(from: nil, count: 5, columns: 3, .down), 0)     // brak zaznaczenia: pierwszy
        XCTAssertEqual(GridNavigation.move(from: 99, count: 5, columns: 3, .down), 0)      // zaznaczony spoza listy (np. po filtrze)
        XCTAssertNil(GridNavigation.move(from: 0, count: 0, columns: 3, .down))
    }

    func testColumnCountMatchesAdaptiveGrid() {
        XCTAssertEqual(GridNavigation.columns(width: 540), 3)     // panel 720 pt bez sidebaru 178
        XCTAssertEqual(GridNavigation.columns(width: 300), 1)
        XCTAssertEqual(GridNavigation.columns(width: 20), 1)
        XCTAssertGreaterThan(GridNavigation.columns(width: 1200), 6)
    }

    func testScaleTicksPickReadableSteps() {
        XCTAssertEqual(ScaleTicks.step(forScale: 5), 1)
        XCTAssertEqual(ScaleTicks.step(forScale: 20), 5)
        XCTAssertEqual(ScaleTicks.step(forScale: 95), 30)
        XCTAssertEqual(ScaleTicks.step(forScale: 3), 0.5)
    }
}

final class ExportGlowTests: XCTestCase {
    func testPlanByTypeAndLengthAndCollisions() {
        var org = Organization(); org.sfxMaxSeconds = 20
        let a = item("whoosh", 0.8), b = item("song", 90), c = item("pic", 0, .image)
        var d = item("whoosh", 0.8); d.path = "/y/whoosh.wav"          // ta sama nazwa pliku w tym samym folderze docelowym
        let plan = LibraryExporter.plan(items: [a, b, c, d], org: org, layout: .byTypeAndLength)
        XCTAssertEqual(plan.map(\.relative), ["SFX/Do 1 s/whoosh.wav", "Muzyka/1–3 min/song.wav", "Obrazy/pic.wav", "SFX/Do 1 s/whoosh 2.wav"])
    }

    func testPlanByCollectionAndRun() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("exp-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("src"), withIntermediateDirectories: true)
        let f = tmp.appendingPathComponent("src/a:b.wav"); try "x".write(to: f, atomically: true, encoding: .utf8)
        var i = item("a", 1); i.path = f.path
        var org = Organization(); org.collections = [MediaCollection(name: "Intro/2026", paths: [f.path, "/nie/ma.wav"])]
        let plan = LibraryExporter.plan(items: [i], org: org, layout: .byCollection)
        XCTAssertEqual(plan.map(\.relative), ["Kolekcje/Intro-2026/a-b.wav"])       // niedozwolone znaki zamienione, nieistniejący plik pominięty
        let out = tmp.appendingPathComponent("out")
        var r = LibraryExporter.run(plan, to: out, mode: .copy)
        XCTAssertEqual(r.done, 1); XCTAssertEqual(r.skipped, 0)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent(plan[0].relative)), "x")
        r = LibraryExporter.run(plan, to: out, mode: .copy)
        XCTAssertEqual(r.done, 0); XCTAssertEqual(r.skipped, 1)                        // nigdy nie nadpisuje
        let out2 = tmp.appendingPathComponent("out2")
        XCTAssertEqual(LibraryExporter.run(plan, to: out2, mode: .link).done, 1)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: out2.appendingPathComponent(plan[0].relative).path), f.path)
    }

    func testGlowIntensityFallsOffSmoothly() {
        XCTAssertEqual(NotchGlow.intensity(distance: 0), 1)
        XCTAssertEqual(NotchGlow.intensity(distance: 26), 0)
        XCTAssertGreaterThan(NotchGlow.intensity(distance: 5), NotchGlow.intensity(distance: 15))
        XCTAssertEqual(NotchGlow.intensity(distance: 100), 0)
    }
}

final class GeometryTests: XCTestCase {
    let mbp = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1079),
                            safeAreaTop: 38, auxiliaryTopLeft: CGRect(x: 0, y: 1079, width: 764, height: 38),
                            auxiliaryTopRight: CGRect(x: 964, y: 1079, width: 764, height: 38))
    let dell = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 3008, height: 1692), visibleFrame: CGRect(x: 0, y: 0, width: 3008, height: 1662))
    let size = CGSize(width: 720, height: 460)

    func testRealNotchAutoHangsBelowNotch() {
        let l = NotchGeometry.layout(mbp, placement: .topCenter, mode: .auto, windowWidth: 720)
        XCTAssertFalse(l.showsCap)
        let f = NotchGeometry.windowFrame(size: size, layout: l, on: mbp)
        XCTAssertEqual(f.midX, 864); XCTAssertEqual(f.maxY, 1079)
    }

    func testVirtualNotchAlwaysOnRealNotchMac() {
        let l = NotchGeometry.layout(mbp, placement: .topCenter, mode: .always, windowWidth: 720)
        XCTAssertTrue(l.showsCap); XCTAssertEqual(l.capSize.width, 200)
        XCTAssertEqual(NotchGeometry.windowFrame(size: size, layout: l, on: mbp).maxY, 1117) // od samej góry ekranu
    }

    func testVirtualNotchOnExternalDisplayIsCenteredAtTop() {
        let l = NotchGeometry.layout(dell, placement: .topCenter, mode: .auto, windowWidth: 720)
        XCTAssertTrue(l.showsCap)
        let f = NotchGeometry.windowFrame(size: size, layout: l, on: dell)
        XCTAssertEqual(f.midX, 1504); XCTAssertEqual(f.maxY, 1692)
    }

    func testNeverOnExternalHangsBelowMenuBar() {
        let l = NotchGeometry.layout(dell, placement: .topCenter, mode: .never, windowWidth: 720)
        XCTAssertFalse(l.showsCap)
        XCTAssertEqual(NotchGeometry.windowFrame(size: size, layout: l, on: dell).maxY, 1662)
    }

    func testCornersAndBottom() {
        let left = NotchGeometry.windowFrame(size: size, layout: NotchGeometry.layout(dell, placement: .topLeft, mode: .auto, windowWidth: 720), on: dell)
        XCTAssertEqual(left.minX, 16)
        let right = NotchGeometry.windowFrame(size: size, layout: NotchGeometry.layout(dell, placement: .topRight, mode: .auto, windowWidth: 720), on: dell)
        XCTAssertEqual(right.maxX, 3008 - 16)
        let l = NotchGeometry.layout(dell, placement: .bottomCenter, mode: .auto, windowWidth: 720)
        XCTAssertTrue(l.atBottom)
        XCTAssertEqual(NotchGeometry.windowFrame(size: size, layout: l, on: dell).minY, 0)
    }

    func testPreferredScreen() {
        XCTAssertEqual(NotchGeometry.preferredScreen([dell, mbp], mouse: CGPoint(x: 100, y: 100)), mbp)
        XCTAssertEqual(NotchGeometry.preferredScreen([dell], mouse: nil), dell)
    }
}

final class PersistenceTests: XCTestCase {
    func testRoundTripAndMissingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("u.json")
        let store = UserDataStore(url: url)
        XCTAssertTrue(store.load().sources.isEmpty)   // brak pliku = domyślne dane, bez crasha
        var u = UserData()
        u.settings.placement = .topRight; u.settings.accent = .violet
        u.org.favorites = ["/a.wav"]; u.org.durationRanges.append(DurationRange(name: "Długie", kind: .audio, minSeconds: 10, maxSeconds: nil, shade: 1))
        u.org.presets = [Preset(name: "Whoosh krótkie", config: ViewConfig())]
        u.sources = [Source(name: "SFX", path: "/sfx", kind: .folder)]
        store.save(u)
        XCTAssertEqual(store.load(), u)
    }

    func testMissingKeysFallBackToDefaultsInsteadOfWipingUserData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let sid = UUID().uuidString
        let json = "{\"settings\":{\"placement\":\"topRight\"},\"sources\":[{\"id\":\"" + sid + "\",\"name\":\"SFX\",\"path\":\"/sfx\",\"kind\":\"folder\"}],\"org\":{\"favorites\":[\"/a.wav\"]}}"
        try json.write(to: url, atomically: true, encoding: .utf8)
        let u = UserDataStore(url: url).load()
        XCTAssertEqual(u.settings.placement, .topRight)
        XCTAssertEqual(u.settings.mode, .hover)
        XCTAssertEqual(u.sources.count, 1)
        XCTAssertEqual(u.org.favorites, ["/a.wav"])
        XCTAssertEqual(u.org.durationRanges.count, 9)
    }
}

func writeTone(_ url: URL, seconds: Double, impact: Bool = false) throws {
    let sr = 48000.0
    let f = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
    let n = AVAudioFrameCount(sr * seconds)
    let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: n)!; b.frameLength = n
    for i in 0..<Int(n) { let t = Double(i) / sr; b.floatChannelData![0][i] = Float(sin(2 * .pi * 440 * t) * (impact ? exp(-t * 8) : 0.5)) }
    try f.write(from: b)
}

final class IndexerTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("idx-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func testFolderScanFindsMediaWithDurationAndGroup() async throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Whoosh"), withIntermediateDirectories: true)
        try writeTone(root.appendingPathComponent("Whoosh/a.wav"), seconds: 1.5)
        try writeTone(root.appendingPathComponent("b.wav"), seconds: 0.5)
        try "x".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let src = Source(name: "T", path: root.path, kind: .folder)
        let items = await Indexer().scan(src, existing: [:])
        XCTAssertEqual(items.count, 2)
        let a = items.first { $0.name == "a" }!
        XCTAssertEqual(a.duration, 1.5, accuracy: 0.05); XCTAssertEqual(a.group, "Whoosh"); XCTAssertEqual(a.kind, .audio)
        XCTAssertNil(items.first { $0.name == "b" }!.group)
    }

    func testIncrementalScanReusesUnchangedAndDetectsNew() async throws {
        try writeTone(root.appendingPathComponent("a.wav"), seconds: 1)
        let src = Source(name: "T", path: root.path, kind: .folder)
        let first = await Indexer().scan(src, existing: [:])
        try writeTone(root.appendingPathComponent("c.wav"), seconds: 2)
        let second = await Indexer().scan(src, existing: Dictionary(uniqueKeysWithValues: first.map { ($0.path, $0) }))
        XCTAssertEqual(Set(second.map(\.name)), ["a", "c"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("a.wav"))
        let third = await Indexer().scan(src, existing: Dictionary(uniqueKeysWithValues: second.map { ($0.path, $0) }))
        XCTAssertEqual(third.map(\.name), ["c"])
    }

    func testFCPLibraryOnlyReadsOriginalMediaAndFollowsSymlinks() async throws {
        let lib = root.appendingPathComponent("Lib.fcpbundle")
        let om = lib.appendingPathComponent("Event 1/Original Media")
        let render = lib.appendingPathComponent("Event 1/Render Files")
        for d in [om, render] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try writeTone(om.appendingPathComponent("real.wav"), seconds: 1)
        try writeTone(render.appendingPathComponent("render.wav"), seconds: 1)
        let external = root.appendingPathComponent("external.wav")
        try writeTone(external, seconds: 2)
        try FileManager.default.createSymbolicLink(at: om.appendingPathComponent("linked.wav"), withDestinationURL: external)
        let items = await Indexer().scan(Source(name: "Lib", path: lib.path, kind: .fcpLibrary), existing: [:])
        XCTAssertEqual(Set(items.map(\.name)), ["real", "external"])
        XCTAssertEqual(items.first { $0.name == "external" }!.path, PathUtil.canonical(external.path))
        XCTAssertEqual(items.first { $0.name == "real" }!.group, "Event 1")
    }

    func testWaveformPeaksReflectEnvelope() throws {
        let f = root.appendingPathComponent("hit.wav")
        try writeTone(f, seconds: 1, impact: true)
        let p = WaveformPeaks.compute(url: f, bins: 100)
        XCTAssertEqual(p.count, 100)
        XCTAssertEqual(p.max()!, 1, accuracy: 0.001)
        XCTAssertGreaterThan(p[2], 0.6); XCTAssertLessThan(p[90], 0.05)   // szybki atak, długie wybrzmiewanie
    }

    func testWatcherReportsNewFile() async throws {
        let exp = expectation(description: "fsevent")
        exp.assertForOverFulfill = false
        let w = FolderWatcher(paths: [root.path], latency: 0.2) { _ in exp.fulfill() }
        try await Task.sleep(nanoseconds: 500_000_000)
        try writeTone(root.appendingPathComponent("new.wav"), seconds: 0.3)
        await fulfillment(of: [exp], timeout: 5)
        w.stop()
    }
}

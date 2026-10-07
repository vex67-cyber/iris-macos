import AppKit
import Foundation

// MARK: - 壁纸来源

public enum WallpaperSource: String, CaseIterable, Identifiable, Sendable {
    case none
    case bing
    case picsum

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return L10n.s("不使用壁纸", "None")
        case .bing: return L10n.s("必应每日壁纸", "Bing daily")
        case .picsum: return L10n.s("Picsum 随机", "Picsum random")
        }
    }

    public var subtitle: String {
        switch self {
        case .none: return L10n.s("休息时使用纯色渐变背景", "Use a plain gradient while resting")
        case .bing: return L10n.s("必应首页的每日精选，免费、无需 API Key", "Bing's daily pick — free, no API key")
        case .picsum: return L10n.s("Unsplash 图库随机美图，免费、无需 API Key", "Random photos from Unsplash via Lorem Picsum")
        }
    }

    public var symbolName: String {
        switch self {
        case .none: return IrisCompat.symbolName("circle.slash", fallback: "slash.circle")
        case .bing: return IrisCompat.symbolName("sparkles", fallback: "star")
        case .picsum: return IrisCompat.symbolName("photo.stack", fallback: "photo")
        }
    }
}

// MARK: - 刷新策略

public enum WallpaperRefresh: String, CaseIterable, Identifiable, Sendable {
    case everyBreak
    case everyLongBreak
    case daily

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .everyBreak: return L10n.s("每次休息", "Every break")
        case .everyLongBreak: return L10n.s("每次长休息", "Every long break")
        case .daily: return L10n.s("每天", "Daily")
        }
    }

    /// 距上次拉取超过这个时间就刷新
    public var interval: TimeInterval {
        switch self {
        case .everyBreak: return 0
        case .everyLongBreak: return 50 * 60
        case .daily: return 20 * 60 * 60
        }
    }
}

// MARK: - 缓存条目

public struct WallpaperEntry: Codable, Equatable {
    public var file: String
    public var credit: String
    public var token: String
    public var date: Date
}

// MARK: - 壁纸仓库

/// 从免费、免 Key 的公共 API 拉取休息壁纸，落盘缓存，离线可用。
///
/// - 必应每日壁纸：`HPImageArchive.aspx`（官方接口）
/// - Lorem Picsum：`picsum.photos`（Unsplash 图库，带作者署名）
///
/// 全部使用回调式 URLSession（不依赖 async/await），因此在 macOS 11 上也能跑。
/// 隐私：只在启用壁纸时访问上述两个域名，不发送任何用户信息。
public final class WallpaperStore: ObservableObject, @unchecked Sendable {

    public static let shared = WallpaperStore()

    @Published public private(set) var image: NSImage?
    /// 缩略图：设置窗口预览用，避免对 4K 大图做模糊（非常吃 CPU）
    @Published public private(set) var previewImage: NSImage?
    /// 图片身份（用于交叉淡入动画）
    @Published public private(set) var token: String = ""
    @Published public private(set) var credit: String = ""
    @Published public private(set) var isDownloading = false
    @Published public private(set) var lastError: String?

    private let cacheDir: URL
    private var entries: [WallpaperEntry] = []
    private var lastFetch: Date = .distantPast
    private var inflight = false

    private let maxEntries = 8

    init(cacheDir: URL? = nil) {
        let base = cacheDir ?? StatsStore.defaultDirectory().appendingPathComponent("Wallpapers", isDirectory: true)
        self.cacheDir = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        loadManifest()
        loadLatestCached()
    }

    // MARK: - 对外入口

    /// 按策略决定是否需要拉新图。已有缓存时先显示缓存，新图到达后自动淡入替换。
    public func refresh(source: WallpaperSource, policy: WallpaperRefresh, force: Bool = false) {
        guard source != .none else {
            clear()
            return
        }
        guard !inflight else { return }

        let needsFetch = force || Date().timeIntervalSince(lastFetch) >= policy.interval
        guard needsFetch else {
            loadLatestCached()
            return
        }

        inflight = true
        isDownloading = true
        lastFetch = Date()

        WallpaperStore.fetchPayload(source: source) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.finishWithError(error)

            case .success(let payload):
                WallpaperStore.downloadImage(payload.url) { [weak self] imageResult in
                    guard let self else { return }
                    switch imageResult {
                    case .failure(let error):
                        self.finishWithError(error)
                    case .success(let data):
                        let processed = WallpaperStore.downscale(data) ?? data
                        do {
                            let entry = try self.persist(data: processed,
                                                         credit: payload.credit,
                                                         token: payload.token)
                            DispatchQueue.main.async {
                                self.inflight = false
                                self.isDownloading = false
                                self.lastError = nil
                                self.apply(entry)
                            }
                        } catch {
                            self.finishWithError(error)
                        }
                    }
                }
            }
        }
    }

    public func clear() {
        DispatchQueue.main.async {
            self.image = nil
            self.previewImage = nil
            self.token = ""
            self.credit = ""
        }
    }

    public var cacheCount: Int { entries.count }

    public func clearCache() {
        for entry in entries {
            try? FileManager.default.removeItem(at: fileURL(for: entry))
        }
        entries = []
        saveManifest()
        clear()
    }

    private func finishWithError(_ error: Error) {
        DispatchQueue.main.async {
            self.inflight = false
            self.isDownloading = false
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - 应用与缓存

    private func apply(_ entry: WallpaperEntry) {
        let url = fileURL(for: entry)
        guard let image = NSImage(contentsOf: url) else { return }
        self.image = image
        self.token = entry.token
        self.credit = entry.credit
        self.previewImage = WallpaperStore.makeThumbnail(url: url)
    }

    /// 直接从磁盘生成小缩略图（走 CGImageSourceThumbnail，不解码整张大图）。
    private static func makeThumbnail(url: URL, maxPixel: CGFloat = 720) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func loadLatestCached() {
        guard image == nil, let latest = entries.max(by: { $0.date < $1.date }) else { return }
        apply(latest)
    }

    private func loadManifest() {
        let url = cacheDir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let list = try? decoder.decode([WallpaperEntry].self, from: data) {
            entries = list.sorted { $0.date < $1.date }
        }
    }

    private func saveManifest() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: cacheDir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func fileURL(for entry: WallpaperEntry) -> URL {
        cacheDir.appendingPathComponent(entry.file)
    }

    private func persist(data: Data, credit: String, token: String) throws -> WallpaperEntry {
        let file = "wallpaper-\(Int(Date().timeIntervalSince1970)).jpg"
        try data.write(to: cacheDir.appendingPathComponent(file), options: .atomic)

        let entry = WallpaperEntry(file: file, credit: credit, token: token, date: Date())
        entries.append(entry)
        entries.sort { $0.date < $1.date }

        while entries.count > maxEntries {
            let old = entries.removeFirst()
            try? FileManager.default.removeItem(at: fileURL(for: old))
        }
        saveManifest()
        return entry
    }

    // MARK: - 网络（回调式，兼容 macOS 11）

    struct Payload {
        var url: URL
        var credit: String
        var token: String
    }

    enum WallpaperError: LocalizedError {
        case badResponse(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .badResponse(let what): return L10n.s("下载壁纸失败：\(what)", "Wallpaper download failed: \(what)")
            case .empty: return L10n.s("图片数据异常", "Unexpected image data")
            }
        }
    }

    static func fetchPayload(source: WallpaperSource,
                             completion: @escaping (Result<Payload, Error>) -> Void) {
        switch source {
        case .none:
            completion(.failure(WallpaperError.badResponse("no source")))
        case .bing:
            fetchBing(completion: completion)
        case .picsum:
            fetchPicsum(completion: completion)
        }
    }

    static func requestJSON(_ url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Iris/1.0 (macOS eye-care reminder)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(WallpaperError.badResponse("HTTP \(http.statusCode)")))
                return
            }
            guard let data, !data.isEmpty else {
                completion(.failure(WallpaperError.empty))
                return
            }
            completion(.success(data))
        }.resume()
    }

    static func downloadImage(_ url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Iris/1.0 (macOS eye-care reminder)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(WallpaperError.badResponse("HTTP \(http.statusCode)")))
                return
            }
            guard let data, data.count > 20_000 else {
                completion(.failure(WallpaperError.empty))
                return
            }
            completion(.success(data))
        }.resume()
    }

    // MARK: 必应每日壁纸

    private struct BingResponse: Decodable {
        struct Image: Decodable {
            let urlbase: String
            let copyright: String
            let title: String
            let startdate: String
        }
        let images: [Image]
    }

    private static func fetchBing(completion: @escaping (Result<Payload, Error>) -> Void) {
        var comps = URLComponents(string: "https://www.bing.com/HPImageArchive.aspx")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: String(Int.random(in: 0..<8))),
            URLQueryItem(name: "n", value: "1"),
            URLQueryItem(name: "mkt", value: L10n.isChinese ? "zh-CN" : "en-US"),
        ]
        guard let apiURL = comps.url else {
            completion(.failure(WallpaperError.badResponse("bing url")))
            return
        }

        requestJSON(apiURL) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                do {
                    let decoded = try JSONDecoder().decode(BingResponse.self, from: data)
                    guard let first = decoded.images.first else {
                        completion(.failure(WallpaperError.empty))
                        return
                    }
                    let uhd = first.urlbase.hasSuffix("_UHD") ? first.urlbase : first.urlbase + "_UHD.jpg"
                    guard let imageURL = URL(string: "https://www.bing.com" + uhd) else {
                        completion(.failure(WallpaperError.badResponse("bing image url")))
                        return
                    }
                    let credit = first.copyright
                        .split(separator: "(").first
                        .map { String($0).trimmingCharacters(in: .whitespaces) } ?? first.title
                    completion(.success(Payload(url: imageURL,
                                                credit: credit.isEmpty ? first.title : credit,
                                                token: "bing-\(first.startdate)")))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: Picsum

    private struct PicsumItem: Decodable {
        let id: String
        let author: String
    }

    private static func fetchPicsum(completion: @escaping (Result<Payload, Error>) -> Void) {
        var comps = URLComponents(string: "https://picsum.photos/v2/list")!
        comps.queryItems = [
            URLQueryItem(name: "page", value: String(Int.random(in: 1...30))),
            URLQueryItem(name: "limit", value: "30"),
        ]
        guard let listURL = comps.url else {
            completion(.failure(WallpaperError.badResponse("picsum url")))
            return
        }

        requestJSON(listURL) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                do {
                    let items = try JSONDecoder().decode([PicsumItem].self, from: data)
                    guard let picked = items.randomElement(),
                          let imageURL = URL(string: "https://picsum.photos/id/\(picked.id)/3840/2160") else {
                        completion(.failure(WallpaperError.empty))
                        return
                    }
                    completion(.success(Payload(
                        url: imageURL,
                        credit: L10n.s("摄影：\(picked.author) · Lorem Picsum",
                                       "Photo by \(picked.author) · Lorem Picsum"),
                        token: "picsum-\(picked.id)")))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - 缩放

    /// 缩到屏幕够用的尺寸再缓存，兼顾清晰度与内存。
    static func downscale(_ data: Data, maxPixel: CGFloat? = nil) -> Data? {
        let limit = maxPixel ?? WallpaperStore.targetPixelSize()
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.84])
    }

    private static func targetPixelSize() -> CGFloat {
        let widest = NSScreen.screens.map { $0.frame.width }.max() ?? 1920
        return min(3200, widest * 2)
    }
}

import CryptoKit
import Foundation

/// 生成方式（バージョン）。
/// - latest   : 最新版。大文字・小文字・数字を必ず2文字ずつ（記号ありは記号も2文字）含める方式。
/// - original : 旧版（最初のバージョン）。英数字からランダムに選び、記号ありは記号を2文字入れる方式。
///
/// 2つは同じキーワードでも結果が異なります。過去に作ったパスワードに合わせて切り替えて使います。
enum PasswordScheme: String, CaseIterable, Identifiable {
    case latest
    case original

    var id: String { rawValue }

    /// 画面に出す名前
    var title: String {
        switch self {
        case .latest: return "最新版"
        case .original: return "旧版"
        }
    }

    /// 記号ありで必要な最低文字数
    var minSymbolLength: Int {
        switch self {
        case .latest: return 8
        case .original: return 2
        }
    }
}

/// 3wordPasGen の生成ロジック（旧版・最新版の両方）。
/// Python 版（`3wordPasGen.py`）と同じキーワードから同じパスワードになるよう移植しています。
enum PasswordGenerator {

    // MARK: - 文字セット（見間違えやすい l 1 O 0 は除外）

    /// 旧版が使う英数字（l 1 O 0 を除く）
    static let base: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    ).filter { !"l1O0".contains($0) }

    static let upper: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").filter { $0 != "O" }
    static let lower: [Character] = Array("abcdefghijklmnopqrstuvwxyz").filter { $0 != "l" }
    static let digits: [Character] = Array("0123456789").filter { !"10".contains($0) }
    static let symbols: [Character] = Array("!#@$%&*()=+?/")

    enum GenerationError: LocalizedError {
        case tooShort(String)
        var errorDescription: String? {
            switch self { case .tooShort(let m): return m }
        }
    }

    // MARK: - 乱数の種づくり（Python: random.seed(sha512(...).hexdigest())）

    private static func seededRNG(_ keywords: [String]) -> PythonRandom {
        let combined = keywords.joined()  // キーワードを区切りなしで結合
        let hex = SHA512.hash(data: Data(combined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return PythonRandom(seed: hex)
    }

    // MARK: - 旧版（最初のバージョン）

    static func generateOriginal(_ keywords: [String], useSymbols: Bool, length: Int) throws -> String {
        var rng = seededRNG(keywords)
        if useSymbols {
            guard length >= 2 else { throw GenerationError.tooShort("記号ありは最低2文字必要です。") }
            let selected = rng.sample(symbols, count: 2)
            let remaining = rng.choices(base, count: length - 2)
            var list = selected + remaining
            rng.shuffle(&list)
            return String(list)
        }
        return String(rng.choices(base, count: length))
    }

    // MARK: - 最新版（文字種を必ず含める）

    static func generateLatest(_ keywords: [String], useSymbols: Bool, length: Int) throws -> String {
        var rng = seededRNG(keywords)
        var chars: [Character] = []
        chars += rng.sample(upper, count: 2)   // 大文字を必ず2文字
        chars += rng.sample(lower, count: 2)   // 小文字を必ず2文字
        chars += rng.sample(digits, count: 2)  // 数字を必ず2文字
        var used = 6

        if useSymbols {
            guard length >= 8 else { throw GenerationError.tooShort("記号ありは最低8文字必要です。") }
            chars += rng.sample(symbols, count: 2)  // 記号を必ず2文字
            used += 2
        }

        let pool = upper + lower + digits + (useSymbols ? symbols : [])
        chars += rng.choices(pool, count: max(0, length - used))  // 残りは全種から
        rng.shuffle(&chars)
        return String(chars)
    }

    // MARK: - 方式を選んで生成

    static func generate(scheme: PasswordScheme, keywords: [String], useSymbols: Bool, length: Int) throws -> String {
        switch scheme {
        case .latest:   return try generateLatest(keywords, useSymbols: useSymbols, length: length)
        case .original: return try generateOriginal(keywords, useSymbols: useSymbols, length: length)
        }
    }

    // MARK: - 入力の前処理（Python の .strip() と NFKC 正規化）

    /// Python の `str.isspace()` が真になる文字（`str.strip()` が取り除く文字）
    private static let pythonWhitespace: Set<UInt32> = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0xA0,
        0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
        0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    ]

    /// `zenkaku_to_hankaku(text.strip())` と同じ：前後の空白を除いてから NFKC 正規化
    static func normalizeKeyword(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        while let first = scalars.first, pythonWhitespace.contains(first.value) { scalars.removeFirst() }
        while let last = scalars.last, pythonWhitespace.contains(last.value) { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view).precomposedStringWithCompatibilityMapping  // NFKC
    }

    // MARK: - Python 版との互換性チェック（Python で実際に生成した値／12文字）

    private static let vectors: [(scheme: PasswordScheme, input: [String], symbols: String, noSymbols: String)] = [
        // 最新版
        (.latest, ["apple", "banana", "cherry"], "4iB!n5$bF)Rt", "54fREi2kBbje"),
        (.latest, ["", "", ""], "Wo75SdD6*r?s", "YSj7DtSoN6Ys"),
        (.latest, ["パスワード", "東京", "🍎"], "2V!PsGvs9(*3", "envVPsG23gcY"),
        (.latest, ["Hello World", "123", "!?"], "8Mez*wUKv2@U", "oUoe8qQIKKv2"),
        (.latest, ["ａｐｐｌｅ", "  banana ", "ｶﾀｶﾅ"], "7!D@D3rXDG/e", "rFDxDN37XtDe"),
        // 旧版（最初のバージョン）
        (.original, ["apple", "banana", "cherry"], "jWeK2)zEFJ!c", "FWcjEFK2eJzo"),
        (.original, ["", "", ""], "KBVh)FwY#AMQ", "HAMKQFYwhBVw"),
        (.original, ["パスワード", "東京", "🍎"], "y$7+GpMDGC3E", "L7G3CyEpMGDD"),
        (.original, ["Hello World", "123", "!?"], "y&iviqNkNa=Q", "tiyiNQqkNvaz"),
        (.original, ["ａｐｐｌｅ", "  banana ", "ｶﾀｶﾅ"], "#2YdXixNR?iP", "QYi2RidXPNxJ"),
    ]

    /// 起動時に、両方式とも Python 版と同じ結果になるかを確認する。
    /// 失敗した場合、この端末で生成したパスワードを信用してはいけない。
    static func passesCompatibilityCheck() -> Bool {
        for v in vectors {
            let keywords = v.input.map(normalizeKeyword)
            guard
                let sym = try? generate(scheme: v.scheme, keywords: keywords, useSymbols: true, length: 12),
                let no = try? generate(scheme: v.scheme, keywords: keywords, useSymbols: false, length: 12),
                sym == v.symbols, no == v.noSymbols
            else {
                return false
            }
        }
        return true
    }
}

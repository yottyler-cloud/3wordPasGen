import CommonCrypto
import CryptoKit
import Foundation

/// 生成方式（バージョン）。同じキーワードでも方式ごとに結果が異なります。
/// 過去に作ったパスワードに合わせて切り替えて使います。
/// - original : 最初の版。英数字からランダムに選び、記号ありは記号を2文字入れる方式。
/// - latest   : 現行（青）。大文字・小文字・数字を必ず2文字ずつ（記号ありは記号も2文字）含める方式。
///              ブラウザ版 web/3wordPasGen.html・Python 版 3wordPasGen.py と同じ。
/// - v2       : 新方式（緑）。暗証番号＋キーワード3つ＋サイト名を PBKDF2 で重く計算してから選ぶ方式。
///              ブラウザ版 web/3wordPasGen2.html・Python 版 3wordPasGen2.py と同じ。
enum PasswordScheme: String, CaseIterable, Identifiable {
    case original
    case latest
    case v2

    var id: String { rawValue }

    /// 画面に出す名前
    var title: String {
        switch self {
        case .original: return "最初の版"
        case .latest: return "現行"
        case .v2: return "新方式"
        }
    }

    /// 選べる文字数と初期値
    var lengths: [Int] { self == .v2 ? [12, 16, 20] : [8, 12, 16, 20] }
    var defaultLength: Int { self == .v2 ? 16 : 12 }
}

/// 3wordPasGen の生成ロジック（3方式すべて）。
/// Python 版と同じ入力から同じパスワードになるよう移植しています。
enum PasswordGenerator {

    // MARK: - 文字セット（見間違えやすい l 1 O 0 は除外）

    /// 最初の版が使う英数字（l 1 O 0 を除く）
    static let base: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    ).filter { !"l1O0".contains($0) }

    static let upper: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").filter { $0 != "O" }
    static let lower: [Character] = Array("abcdefghijklmnopqrstuvwxyz").filter { $0 != "l" }
    static let digits: [Character] = Array("0123456789").filter { !"10".contains($0) }
    static let symbols: [Character] = Array("!#@$%&*()=+?/")

    enum GenerationError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let m): return m }
        }
    }

    // MARK: - 最初の版・現行（Python: random.seed(sha512(キーワード連結).hexdigest())）

    private static func sha512Hex(_ text: String) -> String {
        SHA512.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func generateOriginal(_ keywords: [String], useSymbols: Bool, length: Int) throws -> String {
        var rng = PythonRandom(seed: sha512Hex(keywords.joined()))
        if useSymbols {
            guard length >= 2 else { throw GenerationError.invalid("記号ありは最低2文字必要です。") }
            let selected = rng.sample(symbols, count: 2)
            let remaining = rng.choices(base, count: length - 2)
            var list = selected + remaining
            rng.shuffle(&list)
            return String(list)
        }
        return String(rng.choices(base, count: length))
    }

    static func generateLatest(_ keywords: [String], useSymbols: Bool, length: Int) throws -> String {
        try passwordFromSeed(sha512Hex(keywords.joined()), useSymbols: useSymbols, length: length)
    }

    /// 文字種を必ず含める選び方（現行と新方式で共通。違うのはシードの作り方だけ）
    static func passwordFromSeed(_ seed: String, useSymbols: Bool, length: Int) throws -> String {
        var rng = PythonRandom(seed: seed)
        var chars: [Character] = []
        chars += rng.sample(upper, count: 2)   // 大文字を必ず2文字
        chars += rng.sample(lower, count: 2)   // 小文字を必ず2文字
        chars += rng.sample(digits, count: 2)  // 数字を必ず2文字
        var used = 6

        if useSymbols {
            guard length >= 8 else { throw GenerationError.invalid("記号ありは最低8文字必要です。") }
            chars += rng.sample(symbols, count: 2)  // 記号を必ず2文字
            used += 2
        }

        let pool = upper + lower + digits + (useSymbols ? symbols : [])
        chars += rng.choices(pool, count: max(0, length - used))  // 残りは全種から
        rng.shuffle(&chars)
        return String(chars)
    }

    static func generate(scheme: PasswordScheme, keywords: [String], useSymbols: Bool, length: Int) throws -> String {
        switch scheme {
        case .original: return try generateOriginal(keywords, useSymbols: useSymbols, length: length)
        case .latest: return try generateLatest(keywords, useSymbols: useSymbols, length: length)
        case .v2: throw GenerationError.invalid("新方式は deriveSeedV2 を使ってください。")
        }
    }

    // MARK: - 新方式（3wordPasGen2.py の make_seed と同じ）

    static let v2VersionTag = "3wordPasGen2"
    static let v2Iterations: UInt32 = 210_000   // 変えるとパスワードが変わる
    static let v2TestIterations: UInt32 = 1_000 // 互換性チェック用
    static let minPinLength = 4

    /// 入力のチェック。問題があればメッセージ、なければ nil（引数は正規化済み）
    static func validateV2(pin: String, site: String) -> String? {
        if pin.unicodeScalars.count < minPinLength { return "暗証番号は\(minPinLength)文字以上にしてください。" }
        if site.isEmpty { return "サイト名を入力してください。" }
        return nil
    }

    /// 正規化済みの入力からシード（PBKDF2-HMAC-SHA512 の16進）を作る。ここが重い計算
    static func deriveSeedV2(pin: String, keywords: [String], site: String,
                             iterations: UInt32 = v2Iterations) throws -> String {
        if let message = validateV2(pin: pin, site: site) { throw GenerationError.invalid(message) }
        let secret = Array(([pin] + keywords + [site]).joined(separator: "\0").utf8)
        let salt = Array((v2VersionTag + "\0" + site).utf8)
        var derived = [UInt8](repeating: 0, count: 64)
        let status = secret.withUnsafeBufferPointer { secretPtr in
            secretPtr.baseAddress!.withMemoryRebound(to: Int8.self, capacity: secret.count) { password in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password, secret.count,
                    salt, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    iterations,
                    &derived, derived.count)
            }
        }
        guard status == Int32(kCCSuccess) else { throw GenerationError.invalid("計算できませんでした。") }
        return derived.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 入力の前処理（Python の .strip() と NFKC 正規化）

    /// Python の `str.isspace()` が真になる文字（`str.strip()` / `str.split()` が空白とみなす文字）
    private static let pythonWhitespace: Set<UInt32> = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0xA0,
        0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
        0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    ]

    /// `zenkaku_to_hankaku(text.strip())` と同じ：前後の空白を除いてから NFKC 正規化。
    /// キーワードと暗証番号に使う
    static func normalizeKeyword(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        while let first = scalars.first, pythonWhitespace.contains(first.value) { scalars.removeFirst() }
        while let last = scalars.last, pythonWhitespace.contains(last.value) { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view).precomposedStringWithCompatibilityMapping  // NFKC
    }

    /// サイト名の表記をそろえる（3wordPasGen2.py の normalize_site と同じ）
    /// 例: "https://www.Amazon.co.jp/gp/cart" → "amazon.co.jp"
    static func normalizeSite(_ text: String) -> String {
        // 全角→半角（NFKC）、小文字化、空白をすべて除去
        var s = Array(text.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars)
            .filter { !pythonWhitespace.contains($0.value) }

        // 先頭の「https://」など（スキーム）を除去：[a-z][a-z0-9+.-]*://
        func isLetter(_ c: Unicode.Scalar) -> Bool { ("a"..."z").contains(c) }
        func isDigit(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) }
        if let first = s.first, isLetter(first) {
            var i = 1
            while i < s.count, isLetter(s[i]) || isDigit(s[i]) || "+.-".unicodeScalars.contains(s[i]) { i += 1 }
            if i + 2 < s.count, s[i] == ":", s[i + 1] == "/", s[i + 2] == "/" {
                s.removeFirst(i + 3)
            }
        }

        // 最初の「/」「?」「#」以降（パスなど）を除去
        if let cut = s.firstIndex(where: { "/?#".unicodeScalars.contains($0) }) {
            s.removeSubrange(cut...)
        }

        // 末尾の「:8080」など（ポート番号）を除去：:[0-9]*$
        if let colon = s.lastIndex(of: ":"), s[(colon + 1)...].allSatisfy(isDigit) {
            s.removeSubrange(colon...)
        }

        // 先頭の「www.」、末尾の「.」を除去
        if s.count >= 4, String(String.UnicodeScalarView(s[0..<4])) == "www." { s.removeFirst(4) }
        while s.last == "." { s.removeLast() }

        return String(String.UnicodeScalarView(s))
    }

    // MARK: - Python 版との互換性チェック（Python で実際に生成した値）

    /// 最初の版・現行（12文字）
    private static let vectors: [(scheme: PasswordScheme, input: [String], symbols: String, noSymbols: String)] = [
        // 現行
        (.latest, ["apple", "banana", "cherry"], "4iB!n5$bF)Rt", "54fREi2kBbje"),
        (.latest, ["", "", ""], "Wo75SdD6*r?s", "YSj7DtSoN6Ys"),
        (.latest, ["パスワード", "東京", "🍎"], "2V!PsGvs9(*3", "envVPsG23gcY"),
        (.latest, ["Hello World", "123", "!?"], "8Mez*wUKv2@U", "oUoe8qQIKKv2"),
        (.latest, ["ａｐｐｌｅ", "  banana ", "ｶﾀｶﾅ"], "7!D@D3rXDG/e", "rFDxDN37XtDe"),
        // 最初の版
        (.original, ["apple", "banana", "cherry"], "jWeK2)zEFJ!c", "FWcjEFK2eJzo"),
        (.original, ["", "", ""], "KBVh)FwY#AMQ", "HAMKQFYwhBVw"),
        (.original, ["パスワード", "東京", "🍎"], "y$7+GpMDGC3E", "L7G3CyEpMGDD"),
        (.original, ["Hello World", "123", "!?"], "y&iviqNkNa=Q", "tiyiNQqkNvaz"),
        (.original, ["ａｐｐｌｅ", "  banana ", "ｶﾀｶﾅ"], "#2YdXixNR?iP", "QYi2RidXPNxJ"),
    ]

    /// 新方式：サイト名の正規化
    private static let siteVectors: [(String, String)] = [
        ("https://www.Amazon.co.jp/gp/cart", "amazon.co.jp"),
        ("  ＷＷＷ．Ｇｏｏｇｌｅ．ｃｏｍ  ", "google.com"),
        ("http://localhost:8080/path?q=1#top", "localhost"),
        ("example.com.", "example.com"),
        ("My Bank", "mybank"),
        ("accounts.google.com", "accounts.google.com"),
        ("ゆうちょ", "ゆうちょ"),
    ]

    private typealias V2Vector = (pin: String, keywords: [String], site: String, length: Int, symbols: String, noSymbols: String)

    /// 新方式：v2TestIterations（1,000回）で計算した値
    private static let v2Vectors: [V2Vector] = [
        ("1234", ["apple", "banana", "cherry"], "amazon.co.jp", 16, "+2jDozKTM38RV=zD", "42RDovzTK3IdCqkN"),
        ("０９８７", ["ａｐｐｌｅ", "  banana ", "ｶﾀｶﾅ"], "https://www.Amazon.co.jp/gp/cart", 12, "(og4TDC+/b2(", "Co94TDanwb25"),
        ("秘密の芯!", ["パスワード", "東京", "🍎"], "Google", 20, "bXm7yuov$EMv=2amw/5E", "WTevymgn4DMm62Vew95E"),
        ("abcd", ["", "", ""], "x", 16, "y%6Eh+&QWm6w9#/j", "j4HoSuhEQej9639p"),
        ("1234", ["ab", "c", ""], "example.com", 16, "#xoae(LNF5p#3ZKI", "bVJxoWhI9INE53Zy"),
        ("1234", ["a", "bc", ""], "example.com", 16, "N/ML/Tk86ukkEYo=", "9EeUKLmKo86PMdik"),
    ]

    /// 新方式：本番の v2Iterations（210,000回）で計算した値
    private static let v2FullVectors: [V2Vector] = [
        ("1234", ["apple", "banana", "cherry"], "amazon.co.jp", 16, "=Re2z7y&gYgn6)MS", "exNR672LzFFYghuF"),
    ]

    private static func check(_ vectors: [V2Vector], iterations: UInt32) -> Bool {
        vectors.allSatisfy { v in
            guard let seed = try? deriveSeedV2(pin: normalizeKeyword(v.pin),
                                               keywords: v.keywords.map(normalizeKeyword),
                                               site: normalizeSite(v.site),
                                               iterations: iterations) else { return false }
            return (try? passwordFromSeed(seed, useSymbols: true, length: v.length)) == v.symbols
                && (try? passwordFromSeed(seed, useSymbols: false, length: v.length)) == v.noSymbols
        }
    }

    /// 起動時に、3方式とも Python 版と同じ結果になるかを確認する（新方式の重い計算を含むので
    /// メインスレッド以外で呼ぶこと）。失敗した場合、この端末で生成したパスワードを信用してはいけない。
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
        return siteVectors.allSatisfy { normalizeSite($0.0) == $0.1 }
            && check(v2Vectors, iterations: v2TestIterations)
            && check(v2FullVectors, iterations: v2Iterations)
    }
}

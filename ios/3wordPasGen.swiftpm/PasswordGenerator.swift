import CryptoKit
import Foundation

/// 3wordPasGen.py の生成ロジックをそのまま移植したもの。
/// 同じキーワードなら Python 版と同じパスワードになります。
enum PasswordGenerator {

    /// 英大文字・小文字・数字から、見間違えやすい l 1 O 0 を除いたもの
    static let baseChars: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    ).filter { !"l1O0".contains($0) }

    /// 記号（並び順も Python 版と同じである必要があります）
    static let symbolChars: [Character] = Array("!#@$%&*()=+?/")

    enum GenerationError: Error {
        case lengthTooShort
    }

    // MARK: - パスワード生成（Python の generate_password）

    static func generate(keywords: [String], useSymbols: Bool = true, length: Int = 12) throws -> String {
        let combined = keywords.joined()  // キーワードを区切りなしで結合
        let hexDigest = SHA512.hash(data: Data(combined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        var rng = PythonRandom(seed: hexDigest)  // 同じキーワードで同じパスワードになる

        if useSymbols {
            guard length >= 2 else { throw GenerationError.lengthTooShort }
            let selectedSymbols = rng.sample(symbolChars, count: 2)
            let remainingChars = rng.choices(baseChars, count: length - 2)
            var passwordList = selectedSymbols + remainingChars
            rng.shuffle(&passwordList)
            return String(passwordList)
        } else {
            return String(rng.choices(baseChars, count: length))
        }
    }

    // MARK: - 入力の前処理（Python の .strip() と zenkaku_to_hankaku）

    /// Python の `str.isspace()` が真になる文字（`str.strip()` が取り除く文字）
    private static let pythonWhitespace: Set<UInt32> = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0xA0,
        0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
        0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    ]

    /// `zenkaku_to_hankaku(text.strip())` と同じ処理：前後の空白を除いてから NFKC 正規化
    static func normalizeKeyword(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        while let first = scalars.first, pythonWhitespace.contains(first.value) {
            scalars.removeFirst()
        }
        while let last = scalars.last, pythonWhitespace.contains(last.value) {
            scalars.removeLast()
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view).precomposedStringWithCompatibilityMapping  // NFKC
    }

    // MARK: - Python 版との互換性チェック

    /// Python 版 3wordPasGen.py で実際に生成した値（入力は前処理前の文字列）
    private static let compatibilityVectors: [(input: [String], symbols: String, noSymbols: String)] = [
        (["apple", "banana", "cherry"], "jWeK2)zEFJ!c", "FWcjEFK2eJzo"),
        (["", "", ""], "KBVh)FwY#AMQ", "HAMKQFYwhBVw"),
        (["パスワード", "東京", "🍎"], "y$7+GpMDGC3E", "L7G3CyEpMGDD"),
        (["Hello World", "123", "!?"], "y&iviqNkNa=Q", "tiyiNQqkNvaz"),
        (["ａｐｐｌｅ", "  banana ", "ｶﾀｶﾅ"], "#2YdXixNR?iP", "QYi2RidXPNxJ"),
    ]

    /// 起動時に、Python 版と同じ結果が出るかを確認する。
    /// 失敗した場合は、この端末で生成したパスワードを信用してはいけない。
    static func passesCompatibilityCheck() -> Bool {
        for vector in compatibilityVectors {
            let keywords = vector.input.map(normalizeKeyword)
            guard
                let symbols = try? generate(keywords: keywords, useSymbols: true),
                let noSymbols = try? generate(keywords: keywords, useSymbols: false),
                symbols == vector.symbols,
                noSymbols == vector.noSymbols
            else {
                return false
            }
        }
        return true
    }
}

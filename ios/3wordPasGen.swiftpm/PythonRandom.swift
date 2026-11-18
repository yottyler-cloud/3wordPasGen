import CryptoKit
import Foundation

/// Python の `random` モジュール（CPython の Mersenne Twister, MT19937）のうち、
/// パスワード生成で使う部分を「Python と完全に同じ結果」になるよう移植したもの。
///
/// Python 版 3wordPasGen.py と同じキーワードから同じパスワードを再現するために必要です。
/// 対応している呼び出し:
///   - random.seed(文字列)        → `PythonRandom(seed:)`
///   - random.random()            → `random()`
///   - random.choices(seq, k=n)   → `choices(_:count:)`
///   - random.sample(seq, k)      → `sample(_:count:)`
///   - random.shuffle(list)       → `shuffle(_:)`
struct PythonRandom {
    private static let n = 624
    private static let m = 397

    private var mt = [UInt32](repeating: 0, count: PythonRandom.n)
    private var index = PythonRandom.n

    // MARK: - 初期化

    /// `random.seed(text)`（version=2、文字列シード）と同じ初期化。
    ///
    /// Python は「文字列の UTF-8 バイト列 + その SHA-512 ダイジェスト」を
    /// ビッグエンディアンの巨大な整数とみなし、それを下位から 32 ビットずつ区切った配列で
    /// `init_by_array` を呼びます。
    init(seed text: String) {
        let textBytes = Array(text.utf8)
        var bytes = textBytes + Array(SHA512.hash(data: textBytes))

        // ビッグエンディアン整数として 4 バイト単位に揃える（先頭をゼロ埋め）
        while bytes.count % 4 != 0 {
            bytes.insert(0, at: 0)
        }

        // 下位ワードから順に並べる（リトルエンディアンのワード順）
        var key: [UInt32] = []
        var i = bytes.count
        while i > 0 {
            i -= 4
            let word = UInt32(bytes[i]) << 24
                | UInt32(bytes[i + 1]) << 16
                | UInt32(bytes[i + 2]) << 8
                | UInt32(bytes[i + 3])
            key.append(word)
        }
        // 整数の上位にある 0 のワードは使われない
        while key.count > 1 && key.last == 0 {
            key.removeLast()
        }
        if key.isEmpty {
            key = [0]
        }

        initByArray(key)
    }

    private mutating func initGenrand(_ s: UInt32) {
        mt[0] = s
        for i in 1..<PythonRandom.n {
            mt[i] = 1_812_433_253 &* (mt[i - 1] ^ (mt[i - 1] >> 30)) &+ UInt32(i)
        }
        index = PythonRandom.n
    }

    private mutating func initByArray(_ key: [UInt32]) {
        let n = PythonRandom.n
        initGenrand(19_650_218)
        var i = 1
        var j = 0
        for _ in 0..<max(n, key.count) {
            mt[i] = (mt[i] ^ ((mt[i - 1] ^ (mt[i - 1] >> 30)) &* 1_664_525)) &+ key[j] &+ UInt32(j)
            i += 1
            j += 1
            if i >= n { mt[0] = mt[n - 1]; i = 1 }
            if j >= key.count { j = 0 }
        }
        for _ in 0..<(n - 1) {
            mt[i] = (mt[i] ^ ((mt[i - 1] ^ (mt[i - 1] >> 30)) &* 1_566_083_941)) &- UInt32(i)
            i += 1
            if i >= n { mt[0] = mt[n - 1]; i = 1 }
        }
        mt[0] = 0x8000_0000
        index = n
    }

    // MARK: - 乱数の生成

    private mutating func twist() {
        let n = PythonRandom.n
        let m = PythonRandom.m
        for k in 0..<n {
            let y = (mt[k] & 0x8000_0000) | (mt[(k + 1) % n] & 0x7FFF_FFFF)
            let mag: UInt32 = (y & 1) != 0 ? 0x9908_B0DF : 0
            mt[k] = mt[(k + m) % n] ^ (y >> 1) ^ mag
        }
        index = 0
    }

    /// 32 ビットの乱数（CPython の genrand_uint32）
    mutating func nextUInt32() -> UInt32 {
        if index >= PythonRandom.n {
            twist()
        }
        var y = mt[index]
        index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9D2C_5680
        y ^= (y << 15) & 0xEFC6_0000
        y ^= y >> 18
        return y
    }

    /// `random.random()`：[0, 1) の浮動小数点数（53 ビット精度）
    mutating func random() -> Double {
        let a = Double(nextUInt32() >> 5)
        let b = Double(nextUInt32() >> 6)
        return (a * 67_108_864.0 + b) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// `random.getrandbits(k)`（1 <= k <= 32 のみ対応）
    mutating func getrandbits(_ k: Int) -> UInt32 {
        precondition(k >= 1 && k <= 32, "getrandbits は 1〜32 ビットのみ対応")
        return nextUInt32() >> UInt32(32 - k)
    }

    /// `random._randbelow(n)`：[0, n) の整数
    mutating func randbelow(_ n: Int) -> Int {
        precondition(n > 0 && n <= Int(UInt32.max), "randbelow の範囲外: \(n)")
        let k = Int.bitWidth - n.leadingZeroBitCount  // = n.bit_length()
        var r = Int(getrandbits(k))
        while r >= n {
            r = Int(getrandbits(k))
        }
        return r
    }

    // MARK: - 列の操作

    /// `random.choices(population, k=count)`（重みなし）
    mutating func choices<T>(_ population: [T], count: Int) -> [T] {
        let n = Double(population.count)
        var result: [T] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            // Python: population[floor(random() * n)]（値は常に正なので切り捨て = floor）
            result.append(population[Int(random() * n)])
        }
        return result
    }

    /// `random.sample(population, k=count)`
    mutating func sample<T>(_ population: [T], count k: Int) -> [T] {
        let n = population.count
        precondition(k >= 0 && k <= n, "Sample larger than population or is negative")
        var result: [T] = []
        result.reserveCapacity(k)

        // Python と同じ基準でアルゴリズムを切り替える（結果を一致させるため）
        var setsize = 21
        if k > 5 {
            let exponent = (log(Double(k * 3)) / log(4.0)).rounded(.up)
            setsize += Int(pow(4.0, exponent))
        }

        if n <= setsize {
            var pool = population
            for i in 0..<k {
                let j = randbelow(n - i)
                result.append(pool[j])
                pool[j] = pool[n - i - 1]  // 選んだ要素を末尾の未選択要素で置き換える
            }
        } else {
            var selected = Set<Int>()
            for _ in 0..<k {
                var j = randbelow(n)
                while selected.contains(j) {
                    j = randbelow(n)
                }
                selected.insert(j)
                result.append(population[j])
            }
        }
        return result
    }

    /// `random.shuffle(list)`
    mutating func shuffle<T>(_ list: inout [T]) {
        guard list.count > 1 else { return }
        for i in stride(from: list.count - 1, through: 1, by: -1) {
            let j = randbelow(i + 1)
            list.swapAt(i, j)
        }
    }
}

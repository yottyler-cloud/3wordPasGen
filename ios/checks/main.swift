// GitHub Actions（macOS）で生成ロジックを確かめるための小さなプログラム。
// アプリ本体には含まれない。
import Foundation

let n = PasswordGenerator.normalizeKeyword
let start = Date()
let ok = PasswordGenerator.passesCompatibilityCheck()
print("compatibility check:", ok ? "OK" : "NG", String(format: "(%.2fs)", Date().timeIntervalSince(start)))

let site = PasswordGenerator.normalizeSite("https://www.amazon.co.jp/")
let seed = try PasswordGenerator.deriveSeedV2(pin: n("1234"), keywords: ["あまぞん", "ログイン", "パスワード"].map(n), site: site)
let a = try PasswordGenerator.passwordFromSeed(seed, useSymbols: true, length: 16)
let b = try PasswordGenerator.passwordFromSeed(seed, useSymbols: false, length: 16)
print("v2 sample:", site, a, b)
let expected = (a, b) == ("&ky8TTu$vGQwZ!Z7", "VQd8M4QUvGpwxmZ7")
print("v2 sample matches iPad/Python:", expected)
exit(ok && expected ? 0 : 1)

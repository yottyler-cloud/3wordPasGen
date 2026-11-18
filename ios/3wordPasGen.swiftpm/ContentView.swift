import SwiftUI
import UIKit

/// Python 版（Pythonista の ui）と同じ構成の画面：
/// キーワード入力 ×3、生成 / リセット、記号あり / なしの結果とコピー、ステータス表示
struct ContentView: View {
    @State private var keywords = ["", "", ""]
    @State private var passwordWithSymbols = ""
    @State private var passwordWithoutSymbols = ""
    @State private var status = ""
    @State private var compatibilityOK = true

    var body: some View {
        NavigationStack {
            Form {
                if !compatibilityOK {
                    Section {
                        Text("⚠️ Python 版と同じ結果になりません。この端末で生成したパスワードは使わないでください。")
                            .foregroundStyle(.red)
                    }
                }

                // --- キーワード入力欄 ---
                Section {
                    ForEach(0..<3, id: \.self) { i in
                        TextField("キーワード\(i + 1)", text: $keywords[i])
                            // 自動で大文字になったり変換されたりすると別のパスワードになるため無効化
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.default)
                    }
                }

                // --- 生成 / リセット ---
                Section {
                    HStack(spacing: 16) {
                        Button("生成", action: generatePasswords)
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        Button("リセット", action: resetFields)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }

                // --- 結果（記号あり / なし）とコピー ---
                Section {
                    resultRow(label: "記号あり", password: passwordWithSymbols, copyTitle: "記号ありコピー")
                    resultRow(label: "記号なし", password: passwordWithoutSymbols, copyTitle: "記号なしコピー")
                }

                // --- ステータスメッセージ ---
                if !status.isEmpty {
                    Section {
                        Text(status)
                            .foregroundStyle(.gray)
                    }
                }
            }
            .navigationTitle("パスワード生成")
        }
        .onAppear {
            compatibilityOK = PasswordGenerator.passesCompatibilityCheck()
        }
    }

    private func resultRow(label: String, password: String, copyTitle: String) -> some View {
        HStack {
            Text("\(label): \(password)")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button(copyTitle) {
                copyPassword(password, title: copyTitle)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 処理

    /// 生成ボタン処理
    private func generatePasswords() {
        let normalized = keywords.map(PasswordGenerator.normalizeKeyword)
        do {
            passwordWithSymbols = try PasswordGenerator.generate(keywords: normalized, useSymbols: true)
            passwordWithoutSymbols = try PasswordGenerator.generate(keywords: normalized, useSymbols: false)
        } catch {
            status = "生成に失敗しました"
        }
    }

    /// コピー処理（共通）
    private func copyPassword(_ password: String, title: String) {
        if password.isEmpty {
            status = "先に生成してください"
        } else {
            UIPasteboard.general.string = password
            status = "\(title) をコピーしました"
        }
    }

    /// リセット処理
    private func resetFields() {
        keywords = ["", "", ""]
        passwordWithSymbols = ""
        passwordWithoutSymbols = ""
        status = "リセットしました"
    }
}

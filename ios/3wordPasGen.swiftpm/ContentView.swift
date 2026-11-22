import SwiftUI
import UIKit

/// パスワード生成画面。
/// 方式（最初の版 / 現行 / 新方式）を切り替え、文字数を選び、記号あり / なしを同時に生成します。
/// パスワードは伏せ字（●）で表示し、目のマークで表示を切り替えます。
/// 入力した内容は保存しません（覚えるのは最後に選んだ方式だけ）。
struct ContentView: View {
    @AppStorage("scheme") private var schemeRaw = PasswordScheme.latest.rawValue
    @State private var pin = ""
    @State private var showPin = false
    @State private var keywords: [String] = ["", "", ""]
    @State private var site = ""
    @State private var length = PasswordScheme.latest.defaultLength
    @State private var pwSymbols = ""
    @State private var pwNoSymbols = ""
    @State private var showSymbols = false
    @State private var showNoSymbols = false
    @State private var v2Seed = ""          // 新方式の重い計算の結果（文字数を変えたときに使い回す）
    @State private var generatedSite = ""
    @State private var generationID = UUID()
    @State private var isWorking = false
    @State private var isChecking = true
    @State private var compatibilityOK = true
    @State private var status = ""
    @State private var statusIsError = false

    /// 暗証番号の伏せ字は、文字数に関係なく常にこの数だけ出す（のぞき見で桁数が分からないように）
    private let pinMask = String(repeating: "●", count: 10)

    private var scheme: PasswordScheme { PasswordScheme(rawValue: schemeRaw) ?? .latest }
    private var schemeBinding: Binding<PasswordScheme> {
        Binding(get: { scheme }, set: { schemeRaw = $0.rawValue })
    }
    private var accent: Color { scheme == .v2 ? .green : .blue }
    private var hasResult: Bool { !pwSymbols.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if !compatibilityOK {
                    Section {
                        Text("⚠️ Python 版と同じ結果になりません。この端末で生成したパスワードは使わないでください。")
                            .foregroundStyle(.red)
                    }
                }

                // --- 方式の切り替え ---
                Section {
                    Picker("方式", selection: schemeBinding) {
                        ForEach(PasswordScheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("方式")
                } footer: {
                    Text(schemeDescription)
                }

                // --- 暗証番号（新方式のみ） ---
                if scheme == .v2 {
                    Section {
                        HStack {
                            ZStack(alignment: .leading) {
                                TextField("暗証番号", text: $pin)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .privacySensitive()
                                    // 伏せているあいだは本物の文字もカーソルも透明にする（文字数が分からないように）
                                    .foregroundStyle(showPin || pin.isEmpty ? Color.primary : Color.clear)
                                    .tint(showPin ? nil : Color.clear)
                                if !showPin && !pin.isEmpty {
                                    Text(pinMask).allowsHitTesting(false)
                                }
                            }
                            Button {
                                showPin.toggle()
                            } label: {
                                Image(systemName: showPin ? "eye.slash" : "eye")
                                    .accessibilityLabel(showPin ? "暗証番号を隠す" : "暗証番号を表示")
                            }
                            .buttonStyle(.borderless)
                        }
                    } header: {
                        Text("暗証番号（全サイト共通・4文字以上・数字以外も可）")
                    }
                }

                // --- キーワード ---
                Section {
                    ForEach(0..<3, id: \.self) { i in
                        TextField("キーワード\(i + 1)", text: $keywords[i])
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if scheme != .v2 {
                        Button("キーワード一括コピー", action: copyKeywords)
                    }
                } header: {
                    Text("キーワード")
                }

                // --- サイト名（新方式のみ） ---
                if scheme == .v2 {
                    Section {
                        TextField("例: amazon.co.jp", text: $site)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Text(sitePreview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("キーワード・サイト名をコピー", action: copyKeywords)
                    } header: {
                        Text("サイト名（URL を貼り付けても OK）")
                    }
                }

                // --- 文字数 ---
                Section {
                    Picker("文字数", selection: $length) {
                        ForEach(scheme.lengths, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("文字数")
                }

                // --- 生成 / リセット ---
                Section {
                    Button(action: generatePasswords) {
                        HStack {
                            Spacer()
                            if isWorking || isChecking { ProgressView().padding(.trailing, 6) }
                            Text(isChecking ? "確認中…" : isWorking ? "計算中…" : "生成")
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || isChecking || !compatibilityOK)

                    Button(role: .destructive, action: resetFields) {
                        Text("リセット").frame(maxWidth: .infinity)
                    }
                }

                // --- 結果 ---
                Section {
                    resultRow(label: "記号あり", password: pwSymbols, show: $showSymbols)
                    resultRow(label: "記号なし", password: pwNoSymbols, show: $showNoSymbols)
                } footer: {
                    Text("数字は青、小文字は赤で表示します。目のマークで表示 / 伏せ字を切り替えます。")
                }

                if !status.isEmpty {
                    Section { Text(status).foregroundStyle(statusIsError ? .red : .secondary) }
                }
            }
            .navigationTitle(scheme == .v2 ? "パスワード生成（新方式）" : "パスワード生成")
        }
        .tint(accent)
        .task {
            // 起動時に Python 版と同じ結果になるか確認（新方式の重い計算を含むので裏で行う）
            let ok = await Task.detached(priority: .userInitiated) {
                PasswordGenerator.passesCompatibilityCheck()
            }.value
            compatibilityOK = ok
            isChecking = false
        }
        .onAppear { length = scheme.defaultLength }
        .onChange(of: schemeRaw) {
            if !scheme.lengths.contains(length) { length = scheme.defaultLength }
            clearResults()
            status = ""
        }
        .onChange(of: length) { if hasResult { showResults() } }
        // 入力を変えたら、古い入力で作ったパスワードは消す（別サイト用を取り違えないように）
        .onChange(of: pin) { inputChanged() }
        .onChange(of: keywords) { inputChanged() }
        .onChange(of: site) { inputChanged() }
    }

    private var schemeDescription: String {
        switch scheme {
        case .original: return "最初の版＝一番最初に作った方式。"
        case .latest: return "現行＝大文字・小文字・数字を必ず含む方式（ブラウザ版の青いアプリと同じ）。"
        case .v2: return "新方式＝暗証番号＋キーワード3つ＋サイト名から、わざと重い計算で作る方式（緑のアプリと同じ）。"
        }
    }

    private var sitePreview: String {
        let normalized = PasswordGenerator.normalizeSite(site)
        return normalized.isEmpty ? "小文字にそろえ、https:// ・ www. ・ / 以降は取り除いて使います" : "使う表記: \(normalized)"
    }

    // MARK: - 結果の行

    @ViewBuilder
    private func resultRow(label: String, password: String, show: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: show.wrappedValue ? "eye.slash" : "eye")
                        .accessibilityLabel(show.wrappedValue ? "パスワードを隠す" : "パスワードを表示")
                }
                .buttonStyle(.borderless)
                .disabled(password.isEmpty)

                Button("コピー") { copyPassword(password, label: label) }
                    .buttonStyle(.borderless)
            }
            Group {
                if password.isEmpty {
                    Text(" ")
                } else if show.wrappedValue {
                    coloredPassword(password)
                } else {
                    Text(String(repeating: "●", count: password.count)).foregroundStyle(.secondary)
                }
            }
            .font(.system(.title3, design: .monospaced))
            .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    /// 数字を青、小文字を赤、それ以外を通常色で表示する（Python 版と同じ色分け）
    private func coloredPassword(_ pw: String) -> Text {
        pw.reduce(Text("")) { acc, ch in
            acc + Text(String(ch)).foregroundColor(color(for: ch))
        }
    }

    private func color(for ch: Character) -> Color {
        if ("0"..."9").contains(ch) { return .blue }
        if ("a"..."z").contains(ch) { return .red }
        return .primary
    }

    // MARK: - 処理

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }

    private func clearResults() {
        pwSymbols = ""
        pwNoSymbols = ""
        showSymbols = false
        showNoSymbols = false
        v2Seed = ""
        generatedSite = ""
        generationID = UUID()   // 計算中の結果は捨てる
        isWorking = false
    }

    private func inputChanged() {
        if hasResult || isWorking {
            clearResults()
            setStatus("入力が変わったので、もう一度「生成」してください")
        }
    }

    /// 生成済みの結果を、選択中の文字数で表示し直す
    private func showResults() {
        do {
            let keywords = self.keywords.map(PasswordGenerator.normalizeKeyword)
            if scheme == .v2 {
                pwSymbols = try PasswordGenerator.passwordFromSeed(v2Seed, useSymbols: true, length: length)
                pwNoSymbols = try PasswordGenerator.passwordFromSeed(v2Seed, useSymbols: false, length: length)
                setStatus("「\(generatedSite)」用・\(length)文字で生成しました")
            } else {
                pwSymbols = try PasswordGenerator.generate(scheme: scheme, keywords: keywords, useSymbols: true, length: length)
                pwNoSymbols = try PasswordGenerator.generate(scheme: scheme, keywords: keywords, useSymbols: false, length: length)
                setStatus("\(scheme.title)・\(length)文字で生成しました")
            }
        } catch {
            clearResults()
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func generatePasswords() {
        clearResults()
        guard scheme == .v2 else {
            showResults()
            return
        }
        let pin = PasswordGenerator.normalizeKeyword(self.pin)
        let keywords = self.keywords.map(PasswordGenerator.normalizeKeyword)
        let site = PasswordGenerator.normalizeSite(self.site)
        if let message = PasswordGenerator.validateV2(pin: pin, site: site) {
            setStatus(message, error: true)
            return
        }
        // 重い計算（PBKDF2）は裏で行い、画面は止めない
        let id = UUID()
        generationID = id
        isWorking = true
        setStatus("計算中…（わざと重くしてあります）")
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PasswordGenerator.deriveSeedV2(pin: pin, keywords: keywords, site: site) }
            }.value
            guard generationID == id else { return }   // 計算中に入力が変わった
            isWorking = false
            switch result {
            case .success(let seed):
                v2Seed = seed
                generatedSite = site
                showResults()
            case .failure(let error):
                setStatus(error.localizedDescription, error: true)
            }
        }
    }

    private func copyPassword(_ password: String, label: String) {
        if password.isEmpty {
            setStatus("先に生成してください")
            return
        }
        UIPasteboard.general.string = password
        let target = scheme == .v2 ? generatedSite : scheme.title
        setStatus("\(label)（\(target)・\(length)文字）をコピーしました")
    }

    /// キーワード3つ（新方式はサイト名も）を1行に1つずつコピー。暗証番号は含めない
    private func copyKeywords() {
        var lines = keywords
        if scheme == .v2 { lines.append(PasswordGenerator.normalizeSite(site)) }
        if lines.allSatisfy({ $0.isEmpty }) {
            setStatus("先にキーワードを入力してください")
            return
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        setStatus(scheme == .v2 ? "キーワード3つとサイト名をコピーしました（暗証番号は含みません）" : "キーワード3つをコピーしました")
    }

    private func resetFields() {
        pin = ""
        showPin = false
        keywords = ["", "", ""]
        site = ""
        clearResults()
        length = scheme.defaultLength
        setStatus("リセットしました")
    }
}

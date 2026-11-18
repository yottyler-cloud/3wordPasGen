import ui                     # iOS向けのGUIライブラリ
import hashlib                # SHA-512でハッシュ値生成
import random                 # シャッフルやランダム選択に使用
import string                 # 英数字セットの取得に使用
import unicodedata            # 全角→半角変換に使用
import clipboard              # クリップボード操作

# ----------------------------
# パスワード生成関数
# ----------------------------
def generate_password(keywords, use_symbols=True, length=12):
    combined = ''.join(keywords)  # キーワードを結合
    hash_digest = hashlib.sha512(combined.encode()).hexdigest()
    random.seed(hash_digest)      # 同じキーワードで同じパスワードになる

    allowed_chars_base = ''.join(c for c in string.ascii_letters + string.digits if c not in 'l1O0')
    symbol_chars = '!#@$%&*()=+?/'

    if use_symbols:
        if length < 2:
            raise ValueError("Password length must be at least 2 to include symbols.")
        selected_symbols = random.sample(symbol_chars, 2)
        remaining_chars = random.choices(allowed_chars_base, k=length - 2)
        password_list = selected_symbols + remaining_chars
        random.shuffle(password_list)
        return ''.join(password_list)
    else:
        return ''.join(random.choices(allowed_chars_base, k=length))

# ----------------------------
# 全角→半角変換
# ----------------------------
def zenkaku_to_hankaku(text):
    return unicodedata.normalize('NFKC', text)

# ----------------------------
# パスワード生成ボタン処理
# ----------------------------
def generate_passwords(sender):
    kw1 = zenkaku_to_hankaku(view['kw1'].text.strip())
    kw2 = zenkaku_to_hankaku(view['kw2'].text.strip())
    kw3 = zenkaku_to_hankaku(view['kw3'].text.strip())

    keywords = [kw1, kw2, kw3]

    pw_symbols = generate_password(keywords, use_symbols=True)
    pw_nosymbols = generate_password(keywords, use_symbols=False)

    view['pw_symbols'].text = '記号あり: ' + pw_symbols
    view['pw_nosymbols'].text = '記号なし: ' + pw_nosymbols

    # パスワードの保存(コピー時に参照)
    view['pw_symbols'].password_text = pw_symbols
    view['pw_nosymbols'].password_text = pw_nosymbols

# ----------------------------
# コピー処理(共通)
# ----------------------------
def copy_password(sender):
    pw = getattr(sender.superview[sender.password_label], 'password_text', None)
    if pw:
        clipboard.set(pw)
        view['status'].text = f'{sender.title} をコピーしました'
    else:
        view['status'].text = '先に生成してください'

# ----------------------------
# リセット処理
# ----------------------------
def reset_fields(sender):
    # 入力欄クリア
    for i in range(1, 4):
        view[f'kw{i}'].text = ''
    # パスワード表示クリア
    view['pw_symbols'].text = ''
    view['pw_nosymbols'].text = ''
    # コピー元データもクリア
    view['pw_symbols'].password_text = ''
    view['pw_nosymbols'].password_text = ''
    # ステータス表示クリア
    view['status'].text = 'リセットしました'

# ----------------------------
# GUI構築
# ----------------------------
view = ui.View(name='パスワード生成', bg_color='white', frame=(0, 0, 400, 400))

# --- キーワード入力欄 ---
for i in range(3):
    tf = ui.TextField(name=f'kw{i+1}', placeholder=f'キーワード{i+1}', frame=(20, 20 + i*50, 360, 40))
    tf.border_width = 1
    view.add_subview(tf)

# --- 生成ボタン ---
btn = ui.Button(title='生成', frame=(80, 180, 100, 40), bg_color='lightblue')
btn.action = generate_passwords
view.add_subview(btn)

# --- リセットボタン ---
reset_btn = ui.Button(title='リセット', frame=(220, 180, 100, 40), bg_color='lightgray')
reset_btn.action = reset_fields
view.add_subview(reset_btn)

# --- 結果ラベル(記号あり/なし) ---
lbl1 = ui.Label(name='pw_symbols', frame=(20, 240, 280, 30))
lbl2 = ui.Label(name='pw_nosymbols', frame=(20, 270, 280, 30))
view.add_subview(lbl1)
view.add_subview(lbl2)

# --- コピー用ボタン(記号あり) ---
copy_btn1 = ui.Button(name='copy_symbols', title='記号ありコピー', frame=(300, 240, 80, 30), bg_color='lightgray')
copy_btn1.password_label = 'pw_symbols'
copy_btn1.action = copy_password
view.add_subview(copy_btn1)

# --- コピー用ボタン(記号なし) ---
copy_btn2 = ui.Button(name='copy_nosymbols', title='記号なしコピー', frame=(300, 270, 80, 30), bg_color='lightgray')
copy_btn2.password_label = 'pw_nosymbols'
copy_btn2.action = copy_password
view.add_subview(copy_btn2)

# --- ステータスメッセージ表示欄 ---
status = ui.Label(name='status', frame=(20, 330, 360, 30))
status.text_color = 'gray'
view.add_subview(status)

# --- 表示開始 ---
view.present('sheet')

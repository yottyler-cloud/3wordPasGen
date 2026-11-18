import ui
import hashlib
import random
import string
import unicodedata
import clipboard
from objc_util import ObjCClass, ns
# --- 文字種別カラー変更バージョン ---
# --- iOSネイティブ機能の準備 ---
NSMutableAttributedString = ObjCClass('NSMutableAttributedString')
UIFont = ObjCClass('UIFont')
UIColor = ObjCClass('UIColor')

# ----------------------------
# 1. 彩色済みテキストをセットする関数
# ----------------------------
def set_colored_text(textview, pw_text):
    """
    TextViewに色付きテキストをセットする
    数字: 青, 小文字: 赤, その他: 黒
    """
    # 属性付き文字列を作成
    attr_str = NSMutableAttributedString.alloc().initWithString_(pw_text)

    # 全体のフォントサイズを設定
    font = UIFont.systemFontOfSize_(18)
    attr_str.addAttribute_value_range_('NSFont', font, (0, len(pw_text)))

    for i, char in enumerate(pw_text):
        color = UIColor.blackColor()
        if char.isdigit():
            color = UIColor.blueColor()
        elif char.islower():
            color = UIColor.redColor()

        attr_str.addAttribute_value_range_('NSColor', color, (i, 1))

    # PythonistaのTextViewに反映
    textview.objc_instance.setAttributedText_(attr_str)

# ----------------------------
# 2. パスワード生成ロジック
# ----------------------------
def generate_password(keywords, use_symbols=True, length=12):
    combined = ''.join(keywords)
    hash_digest = hashlib.sha512(combined.encode()).hexdigest()
    random.seed(hash_digest)

    uppercase = ''.join(c for c in string.ascii_uppercase if c not in 'O')
    lowercase = ''.join(c for c in string.ascii_lowercase if c not in 'l')
    digits = ''.join(c for c in string.digits if c not in '10')
    symbols = '!#@$%&*()=+?/'

    password_chars = []
    password_chars += random.sample(uppercase, 2)
    password_chars += random.sample(lowercase, 2)
    password_chars += random.sample(digits, 2)
    used_length = 6

    if use_symbols:
        if length < 8:
            raise ValueError("記号ありの場合は最低8文字必要です。")
        password_chars += random.sample(symbols, 2)
        used_length += 2

    remaining_length = length - used_length
    pool = uppercase + lowercase + digits + (symbols if use_symbols else '')
    password_chars += random.choices(pool, k=remaining_length)
    random.shuffle(password_chars)
    return ''.join(password_chars)

def zenkaku_to_hankaku(text):
    return unicodedata.normalize('NFKC', text)

# ----------------------------
# 3. ボタン処理系
# ----------------------------
def generate_passwords(sender):
    kw1 = zenkaku_to_hankaku(view['kw1'].text.strip())
    kw2 = zenkaku_to_hankaku(view['kw2'].text.strip())
    kw3 = zenkaku_to_hankaku(view['kw3'].text.strip())
    keywords = [kw1, kw2, kw3]

    try:
        pw_symbols = generate_password(keywords, use_symbols=True)
        pw_nosymbols = generate_password(keywords, use_symbols=False)

        # ここで先ほどの関数を呼び出し
        set_colored_text(view['pw_symbols'], pw_symbols)
        set_colored_text(view['pw_nosymbols'], pw_nosymbols)

        view['pw_symbols'].password_raw = pw_symbols
        view['pw_nosymbols'].password_raw = pw_nosymbols
        view['status'].text = '生成しました'
    except ValueError as e:
        view['status'].text = str(e)

def copy_password(sender):
    target_name = 'pw_symbols' if 'symbols' in sender.name else 'pw_nosymbols'
    pw = getattr(view[target_name], 'password_raw', None)
    if pw:
        clipboard.set(pw)
        view['status'].text = f'{sender.title} をコピーしました'
    else:
        view['status'].text = '先に生成してください'

def reset_fields(sender):
    for i in range(1, 4):
        view[f'kw{i}'].text = ''
    view['pw_symbols'].text = ''
    view['pw_nosymbols'].text = ''
    view['pw_symbols'].password_raw = ''
    view['pw_nosymbols'].password_raw = ''
    view['status'].text = 'リセットしました'

# ----------------------------
# 4. GUI構築
# ----------------------------
view = ui.View(name='パスワード生成', bg_color='white', frame=(0, 0, 400, 450))

for i in range(3):
    tf = ui.TextField(name=f'kw{i+1}', placeholder=f'キーワード{i+1}', frame=(20, 20 + i*50, 360, 40))
    tf.border_width = 1
    view.add_subview(tf)

btn = ui.Button(title='生成', frame=(80, 180, 100, 40), bg_color='#e1f5fe')
btn.action = generate_passwords
view.add_subview(btn)

reset_btn = ui.Button(title='リセット', frame=(220, 180, 100, 40), bg_color='#f5f5f5')
reset_btn.action = reset_fields
view.add_subview(reset_btn)

# 表示エリア (TextView)
lbl1 = ui.TextView(name='pw_symbols', frame=(20, 240, 260, 40), editable=False, scroll_enabled=False)
lbl1.border_width = 0.5
lbl1.border_color = '#cccccc'
lbl2 = ui.TextView(name='pw_nosymbols', frame=(20, 290, 260, 40), editable=False, scroll_enabled=False)
lbl2.border_width = 0.5
lbl2.border_color = '#cccccc'
view.add_subview(lbl1)
view.add_subview(lbl2)

# コピーボタン
copy_btn1 = ui.Button(name='copy_symbols', title='記号ありコピ', frame=(290, 245, 90, 30), bg_color='#eeeeee')
copy_btn1.action = copy_password
view.add_subview(copy_btn1)

copy_btn2 = ui.Button(name='copy_nosymbols', title='記号なしコピ', frame=(290, 295, 90, 30), bg_color='#eeeeee')
copy_btn2.action = copy_password
view.add_subview(copy_btn2)

status = ui.Label(name='status', frame=(20, 350, 360, 30), alignment=ui.ALIGN_CENTER)
status.text_color = 'gray'
view.add_subview(status)

view.present('sheet')

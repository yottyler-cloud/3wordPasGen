"""3wordPasGen2（新方式・Pythonista 用）

現行の 3wordPasGen.py とは別の方式です。結果は現行と変わります。

材料:
  1. 暗証番号（全サイト共通の秘密の芯。必須・4文字以上・文字種自由）
  2. キーワード × 3
  3. サイト名（必須。表記をそろえてから使う）

しくみ:
  各入力を正規化 → 暗証番号・キーワード3つ・サイト名を NUL 区切りで連結
  → PBKDF2-HMAC-SHA512（ソルト "3wordPasGen2" + NUL + サイト名、210,000回、64バイト）
  → 16進文字列 → random.seed() → 文字選び（現行と同じ手順）
  区切りを入れるので「ab」+「c」と「a」+「bc」は別のパスワードになる。
  PBKDF2 で1回の計算を重くし、パスワードが漏れたときにキーワードを総当たりで
  逆算されにくくしている（SHA-512 一発の現行方式より約40万倍重い）。

Pythonista 以外（PC の Python など）で実行した場合は、
画面を出さずに互換性チェック用の値を表示する。
"""
import hashlib
import random
import re
import string
import unicodedata

VERSION_TAG = '3wordPasGen2'
MIN_PIN_LENGTH = 4
ITERATIONS = 210000   # PBKDF2 のくり返し回数（変えるとパスワードが変わる）
TEST_ITERATIONS = 1000  # 互換性チェック用（起動を速くするため少なめ）
LENGTHS = (12, 16, 20)
DEFAULT_LENGTH = 16

UPPERCASE = ''.join(c for c in string.ascii_uppercase if c not in 'O')
LOWERCASE = ''.join(c for c in string.ascii_lowercase if c not in 'l')
DIGITS = ''.join(c for c in string.digits if c not in '10')
SYMBOLS = '!#@$%&*()=+?/'


# ----------------------------
# 1. 入力の正規化
# ----------------------------
def normalize_text(text):
    """前後の空白を除去し、全角→半角（NFKC）。キーワード・暗証番号用"""
    return unicodedata.normalize('NFKC', text.strip())


def normalize_site(text):
    """サイト名の表記をそろえる

    1. 全角→半角（NFKC）、小文字化、空白をすべて除去
    2. 先頭の「https://」など（スキーム）を除去
    3. 最初の「/」「?」「#」以降（パスなど）を除去
    4. 末尾の「:443」など（ポート番号）を除去
    5. 先頭の「www.」、末尾の「.」を除去
    例: "https://www.Amazon.co.jp/gp/cart" → "amazon.co.jp"
    """
    s = unicodedata.normalize('NFKC', text).lower()
    s = ''.join(s.split())
    s = re.sub(r'^[a-z][a-z0-9+.\-]*://', '', s)
    s = re.split(r'[/?#]', s, maxsplit=1)[0]
    s = re.sub(r':[0-9]*$', '', s)
    if s.startswith('www.'):
        s = s[4:]
    s = s.rstrip('.')
    return s


# ----------------------------
# 2. パスワード生成ロジック
# ----------------------------
def make_seed(pin, keywords, site, iterations=ITERATIONS):
    """正規化済みの入力からシード（PBKDF2-HMAC-SHA512 の16進）を作る。ここが重い計算"""
    if len(pin) < MIN_PIN_LENGTH:
        raise ValueError(f'暗証番号は{MIN_PIN_LENGTH}文字以上にしてください。')
    if not site:
        raise ValueError('サイト名を入力してください。')
    secret = '\0'.join([pin, *keywords, site]).encode('utf-8')
    salt = (VERSION_TAG + '\0' + site).encode('utf-8')
    return hashlib.pbkdf2_hmac('sha512', secret, salt, iterations, 64).hex()


def password_from_seed(seed, use_symbols=True, length=DEFAULT_LENGTH):
    """シードから文字を選ぶ（現行方式と同じ手順。こちらは軽い）"""
    rng = random.Random(seed)

    password_chars = []
    password_chars += rng.sample(UPPERCASE, 2)
    password_chars += rng.sample(LOWERCASE, 2)
    password_chars += rng.sample(DIGITS, 2)
    used_length = 6

    if use_symbols:
        if length < 8:
            raise ValueError('記号ありの場合は最低8文字必要です。')
        password_chars += rng.sample(SYMBOLS, 2)
        used_length += 2

    remaining_length = length - used_length
    pool = UPPERCASE + LOWERCASE + DIGITS + (SYMBOLS if use_symbols else '')
    password_chars += rng.choices(pool, k=remaining_length)
    rng.shuffle(password_chars)
    return ''.join(password_chars)


# ----------------------------
# 3. 互換性チェック用の値（ブラウザ版の COMPATIBILITY_VECTORS と同じもの）
# ----------------------------
# 照合用（ITERATIONS 回の本番設定で計算した値。起動時に1件だけ確かめる）
FULL_TEST_INPUT = ('1234', ['apple', 'banana', 'cherry'], 'amazon.co.jp', 16)

TEST_INPUTS = [
    ('1234', ['apple', 'banana', 'cherry'], 'amazon.co.jp', 16),
    ('０９８７', ['ａｐｐｌｅ', '  banana ', 'ｶﾀｶﾅ'], 'https://www.Amazon.co.jp/gp/cart', 12),
    ('秘密の芯!', ['パスワード', '東京', '🍎'], 'Google', 20),
    ('abcd', ['', '', ''], 'x', 16),
    ('1234', ['ab', 'c', ''], 'example.com', 16),
    ('1234', ['a', 'bc', ''], 'example.com', 16),
]

SITE_TESTS = [
    'https://www.Amazon.co.jp/gp/cart',
    '  ＷＷＷ．Ｇｏｏｇｌｅ．ｃｏｍ  ',
    'http://localhost:8080/path?q=1#top',
    'example.com.',
    'My Bank',
    'accounts.google.com',
    'ゆうちょ',
]


def print_test_vectors():
    print('// サイト名の正規化')
    for s in SITE_TESTS:
        print(f'[{s!r}, {normalize_site(s)!r}],')
    for title, inputs, iterations in (
            (f'パスワード（{TEST_ITERATIONS}回）', TEST_INPUTS, TEST_ITERATIONS),
            (f'パスワード（本番 {ITERATIONS}回）', [FULL_TEST_INPUT], ITERATIONS)):
        print('// ' + title)
        for row in test_vectors(inputs, iterations):
            print(repr(row) + ',')


def test_vectors(inputs, iterations):
    rows = []
    for pin, kws, site, length in inputs:
        seed = make_seed(normalize_text(pin), [normalize_text(x) for x in kws], normalize_site(site), iterations)
        rows.append([pin, kws, site, length,
                     password_from_seed(seed, True, length), password_from_seed(seed, False, length)])
    return rows


# ----------------------------
# 4. Pythonista の画面
# ----------------------------
def run_app():
    import ui
    import clipboard
    from objc_util import ObjCClass

    NSMutableAttributedString = ObjCClass('NSMutableAttributedString')
    UIFont = ObjCClass('UIFont')
    UIColor = ObjCClass('UIColor')
    state = {'length': DEFAULT_LENGTH}

    def set_colored_text(textview, pw_text):
        """数字: 青, 小文字: 赤, その他: 黒"""
        attr_str = NSMutableAttributedString.alloc().initWithString_(pw_text)
        font = UIFont.systemFontOfSize_(18)
        attr_str.addAttribute_value_range_('NSFont', font, (0, len(pw_text)))
        for i, char in enumerate(pw_text):
            color = UIColor.blackColor()
            if char.isdigit():
                color = UIColor.blueColor()
            elif char.islower():
                color = UIColor.redColor()
            attr_str.addAttribute_value_range_('NSColor', color, (i, 1))
        textview.objc_instance.setAttributedText_(attr_str)

    def update_site_preview(sender=None):
        site = normalize_site(view['site'].text)
        view['site_preview'].text = f'使う表記: {site}' if site else ''

    def generate_passwords(sender):
        pin = normalize_text(view['pin'].text)
        keywords = [normalize_text(view[f'kw{i}'].text) for i in range(1, 4)]
        site = normalize_site(view['site'].text)
        update_site_preview()
        try:
            seed = make_seed(pin, keywords, site)
            for name, use_symbols in (('pw_symbols', True), ('pw_nosymbols', False)):
                pw = password_from_seed(seed, use_symbols, state['length'])
                set_colored_text(view[name], pw)
                view[name].password_raw = pw
            view['status'].text = f'生成しました（{site}・{state["length"]}文字）'
        except ValueError as e:
            view['status'].text = str(e)

    def copy_password(sender):
        target_name = 'pw_symbols' if sender.name == 'copy_symbols' else 'pw_nosymbols'
        pw = getattr(view[target_name], 'password_raw', None)
        if pw:
            clipboard.set(pw)
            view['status'].text = f'{sender.title} をコピーしました'
        else:
            view['status'].text = '先に生成してください'

    def set_length(sender):
        state['length'] = LENGTHS[sender.selected_index]

    def reset_fields(sender):
        for name in ('pin', 'kw1', 'kw2', 'kw3', 'site'):
            view[name].text = ''
        for name in ('pw_symbols', 'pw_nosymbols'):
            view[name].text = ''
            view[name].password_raw = ''
        view['site_preview'].text = ''
        view['status'].text = 'リセットしました'

    view = ui.View(name='パスワード生成（新方式）', bg_color='white', frame=(0, 0, 400, 600))

    fields = [('pin', '暗証番号（4文字以上）')] + [(f'kw{i}', f'キーワード{i}') for i in range(1, 4)] \
        + [('site', 'サイト名（例: amazon.co.jp）')]
    for i, (name, placeholder) in enumerate(fields):
        tf = ui.TextField(name=name, placeholder=placeholder, frame=(20, 20 + i * 50, 360, 40))
        tf.border_width = 1
        tf.autocapitalization_type = ui.AUTOCAPITALIZE_NONE
        tf.autocorrection_type = False
        tf.spellchecking_type = False
        if name == 'pin':
            tf.secure = True
        if name == 'site':
            tf.action = update_site_preview
        view.add_subview(tf)

    preview = ui.Label(name='site_preview', frame=(20, 265, 360, 24))
    preview.text_color = 'gray'
    view.add_subview(preview)

    seg = ui.SegmentedControl(frame=(20, 295, 360, 32))
    seg.segments = [f'{n}文字' for n in LENGTHS]
    seg.selected_index = LENGTHS.index(DEFAULT_LENGTH)
    seg.action = set_length
    view.add_subview(seg)

    btn = ui.Button(title='生成', frame=(80, 340, 100, 40), bg_color='#e1f5fe')
    btn.action = generate_passwords
    view.add_subview(btn)

    reset_btn = ui.Button(title='リセット', frame=(220, 340, 100, 40), bg_color='#f5f5f5')
    reset_btn.action = reset_fields
    view.add_subview(reset_btn)

    for i, (name, copy_name, title) in enumerate((
            ('pw_symbols', 'copy_symbols', '記号ありコピ'),
            ('pw_nosymbols', 'copy_nosymbols', '記号なしコピ'))):
        tv = ui.TextView(name=name, frame=(20, 400 + i * 50, 260, 40), editable=False, scroll_enabled=False)
        tv.border_width = 0.5
        tv.border_color = '#cccccc'
        view.add_subview(tv)
        cb = ui.Button(name=copy_name, title=title, frame=(290, 405 + i * 50, 90, 30), bg_color='#eeeeee')
        cb.action = copy_password
        view.add_subview(cb)

    status = ui.Label(name='status', frame=(20, 510, 360, 30), alignment=ui.ALIGN_CENTER)
    status.text_color = 'gray'
    view.add_subview(status)

    view.present('sheet')


if __name__ == '__main__':
    try:
        import ui  # noqa: F401  Pythonista のときだけ存在する
    except ImportError:
        print_test_vectors()
    else:
        run_app()

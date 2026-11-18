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
    """ブラウザ版（web/3wordPasGen2.html）に近い画面"""
    import ui
    import clipboard
    from objc_util import ObjCClass

    NSMutableAttributedString = ObjCClass('NSMutableAttributedString')
    UIFont = ObjCClass('UIFont')
    UIColor = ObjCClass('UIColor')

    # --- 色（ブラウザ版のライト表示と同じ） ---
    BG = '#eaf6ee'
    CARD = '#ffffff'
    TEXT = '#1c1c1e'
    MUTED = '#6e7c73'
    LINE = '#d1ddd5'
    ACCENT = '#178a4a'
    BUTTON = '#dcefe2'
    DANGER = '#d70015'
    CLEAR = (0, 0, 0, 0)
    PIN_MASK = '●' * 10   # 暗証番号の伏せ字は、文字数に関係なく常に10個

    def uicolor(hex_color):
        r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
        return UIColor.colorWithRed_green_blue_alpha_(r, g, b, 1.0)

    COLOR_TEXT = uicolor(TEXT)
    COLOR_DIGIT = uicolor('#0040dd')
    COLOR_LOWER = uicolor('#e0001b')
    PW_FONT = UIFont.fontWithName_size_('Menlo', 19) or UIFont.systemFontOfSize_(19)

    state = {
        'length': DEFAULT_LENGTH,
        'seed': '',
        'site': '',
        'pin_visible': False,
        'pw': {'pw_symbols': '', 'pw_nosymbols': ''},
        'visible': {'pw_symbols': False, 'pw_nosymbols': False},
    }

    def eye_image(visible):
        """目のマーク（表示中は斜線入り）。アイコンが無ければ None"""
        try:
            return ui.Image.named('iob:eye_disabled_24' if visible else 'iob:eye_24')
        except Exception:
            return None

    def set_eye(button, visible):
        image = eye_image(visible)
        if image is not None:
            button.image = image
            button.title = ''
        else:
            button.title = '隠す' if visible else '表示'

    # --- パスワードの表示（伏せ字は●、表示中は数字を青・小文字を赤） ---
    def set_password_text(textview, text, colored):
        attr_str = NSMutableAttributedString.alloc().initWithString_(text)
        if text:
            attr_str.addAttribute_value_range_('NSFont', PW_FONT, (0, len(text)))
            for i, char in enumerate(text):
                color = COLOR_TEXT
                if colored and char in '23456789':
                    color = COLOR_DIGIT
                elif colored and 'a' <= char <= 'z':
                    color = COLOR_LOWER
                attr_str.addAttribute_value_range_('NSColor', color, (i, 1))
        textview.objc_instance.setAttributedText_(attr_str)

    def render(name):
        pw = state['pw'][name]
        visible = state['visible'][name]
        if not pw:
            set_password_text(view[name], '', False)
        elif visible:
            set_password_text(view[name], pw, True)
        else:
            set_password_text(view[name], '●' * len(pw), False)

    def set_visible(name, visible):
        state['visible'][name] = visible
        set_eye(view['eye_' + name], visible)
        render(name)

    def set_status(text, error=False):
        view['status'].text = text
        view['status'].text_color = DANGER if error else MUTED

    def clear_passwords():
        for name in state['pw']:
            state['pw'][name] = ''
            set_visible(name, False)
        state['seed'] = ''
        state['site'] = ''

    # --- 暗証番号（本物の文字は透明にして、●10個を重ねて表示する） ---
    def update_pin():
        pin_field = view['pin']
        hidden = not state['pin_visible']
        pin_field.text_color = CLEAR if hidden else TEXT
        pin_field.tint_color = CLEAR if hidden else ACCENT   # カーソル位置からも文字数が分からないように
        view['pin_mask'].hidden = not (hidden and pin_field.text)
        set_eye(view['eye_pin'], state['pin_visible'])

    def toggle_pin(sender):
        state['pin_visible'] = not state['pin_visible']
        update_pin()

    # --- サイト名：実際に使う表記をその場で表示 ---
    def update_site_preview():
        site = normalize_site(view['site'].text)
        view['site_preview'].text = (f'使う表記: {site}' if site
                                     else '小文字にそろえ、https:// ・ www. ・ / 以降は取り除いて使います')

    # --- 生成 ---
    def show_passwords():
        for name, use_symbols in (('pw_symbols', True), ('pw_nosymbols', False)):
            state['pw'][name] = password_from_seed(state['seed'], use_symbols, state['length'])
            render(name)
        set_status(f'「{state["site"]}」用・{state["length"]}文字で生成しました')

    def generate(sender=None):
        for name in FIELD_ORDER:
            view[name].end_editing()
        pin = normalize_text(view['pin'].text)
        keywords = [normalize_text(view[f'kw{i}'].text) for i in range(1, 4)]
        site = normalize_site(view['site'].text)
        clear_passwords()
        try:
            state['seed'] = make_seed(pin, keywords, site)
        except ValueError as e:
            set_status(str(e), error=True)
            return
        state['site'] = site
        show_passwords()

    def set_length(sender):
        state['length'] = LENGTHS[sender.selected_index]
        if state['seed']:
            show_passwords()

    def copy_password(sender):
        name = sender.name.replace('copy_', '')
        pw = state['pw'][name]
        if not pw:
            set_status('先に生成してください')
            return
        clipboard.set(pw)
        kind = '記号あり' if name == 'pw_symbols' else '記号なし'
        set_status(f'{kind}（{state["site"]}・{state["length"]}文字）をコピーしました')

    def copy_keywords(sender):
        values = [view[f'kw{i}'].text for i in range(1, 4)]
        site = normalize_site(view['site'].text)
        if not any(values) and not site:
            set_status('先にキーワードを入力してください')
            return
        clipboard.set('\n'.join(values + [site]))
        set_status('キーワード3つとサイト名をコピーしました（暗証番号は含みません）')

    def reset(sender):
        for name in FIELD_ORDER:
            view[name].text = ''
            view[name].end_editing()
        state['pin_visible'] = False
        update_pin()
        clear_passwords()
        update_site_preview()
        state['length'] = DEFAULT_LENGTH
        view['length'].selected_index = LENGTHS.index(DEFAULT_LENGTH)
        set_status('リセットしました')

    # --- 入力欄の動き ---
    FIELD_ORDER = ['pin', 'kw1', 'kw2', 'kw3', 'site']

    class FieldDelegate(object):
        def textfield_did_change(self, textfield):
            if textfield.name == 'pin':
                update_pin()
            if textfield.name == 'site':
                update_site_preview()
            # 入力を変えたら、古い入力で作ったパスワードは消す（別サイト用を取り違えないように）
            if state['seed']:
                clear_passwords()
                set_status('入力が変わったので、もう一度「生成」してください')

        def textfield_should_return(self, textfield):
            # Enter で次の欄へ、最後の欄なら生成
            i = FIELD_ORDER.index(textfield.name)
            if i < len(FIELD_ORDER) - 1:
                view[FIELD_ORDER[i + 1]].begin_editing()
            else:
                generate()
            return True

    delegate = FieldDelegate()

    # --- 画面の組み立て ---
    # フルスクリーンで表示し、中身は最大720の幅で中央に置く（ブラウザ版と同じ）
    screen_w, screen_h = ui.get_screen_size()
    width = min(720, screen_w)
    pad = 16
    card_w = width - pad * 2

    button_frames = []   # ボタンの大きさ（Pythonista が勝手に縮めることがあるので、あとで指定し直す）

    class Root(ui.View):
        def layout(self):
            # 回転などで大きさが変わったら、中身を中央に置き直す
            content.x = max(0, (self.width - width) / 2)
            scroll.content_size = (self.width, content.height)
            for b, frame in button_frames:
                b.frame = frame

    root = Root()
    root.name = 'パスワード生成（新方式）'
    root.bg_color = BG
    root.frame = (0, 0, screen_w, screen_h)
    scroll = ui.ScrollView(frame=root.bounds, flex='WH', bg_color=BG)
    root.add_subview(scroll)
    content = ui.View(frame=(0, 0, width, 760), bg_color=BG)
    scroll.add_subview(content)
    y = [16]

    def add(sub):
        content.add_subview(sub)
        return sub

    def label(text, frame, size=17, color=TEXT, bold=False, align=ui.ALIGN_LEFT, parent=None, name=None):
        lb = ui.Label(frame=frame, text=text, text_color=color, alignment=align)
        if name:
            lb.name = name
        lb.font = ('<system-bold>' if bold else '<system>', size)
        lb.number_of_lines = 0
        (parent or content).add_subview(lb)
        return lb

    def card(height):
        c = add(ui.View(frame=(pad, y[0], card_w, height), bg_color=CARD))
        c.corner_radius = 14
        y[0] += height + 18
        return c

    def separator(parent, top):
        parent.add_subview(ui.View(frame=(0, top, card_w, 1), bg_color=LINE))

    def section(text):
        label(text, (pad + 12, y[0], card_w - 12, 20), size=13, color=MUTED)
        y[0] += 26

    def field(parent, name, placeholder, top, right_space=0):
        tf = ui.TextField(name=name, frame=(16, top, card_w - 32 - right_space, 52), placeholder=placeholder)
        tf.bordered = False
        tf.bg_color = CARD
        tf.text_color = TEXT
        tf.font = ('<system>', 17)
        tf.autocapitalization_type = ui.AUTOCAPITALIZE_NONE
        tf.autocorrection_type = False
        tf.spellchecking_type = False
        tf.delegate = delegate
        parent.add_subview(tf)
        return tf

    def button(parent, title, frame, action, primary=False, name=None):
        b = ui.Button()
        if name:
            b.name = name
        b.title = title
        b.font = ('<system>', 17)
        b.bg_color = ACCENT if primary else BUTTON
        b.tint_color = '#ffffff' if primary else ACCENT
        b.corner_radius = frame[3] / 2
        b.action = action
        parent.add_subview(b)
        b.frame = frame   # 大きさは最後に指定する
        button_frames.append((b, frame))
        return b

    # 見出し（「パスワード生成（新方式）」は上のタイトルバーに出るので、ここは印と説明だけ）
    y[0] = 20
    badge = label('新方式', (pad + 4, y[0], 64, 26), size=14, color='#ffffff', bold=True, align=ui.ALIGN_CENTER)
    badge.bg_color = ACCENT
    badge.corner_radius = 6
    label('暗証番号 ＋ キーワード3つ ＋ サイト名。現行方式とは別のパスワードになります。',
          (pad + 80, y[0] - 7, card_w - 84, 40), size=14, color=MUTED)
    y[0] += 44

    # 暗証番号
    section('暗証番号（全サイト共通・4文字以上・数字以外も可）')
    c = card(52)
    field(c, 'pin', '暗証番号', 0, right_space=48)
    mask = label(PIN_MASK, (16, 0, card_w - 80, 52), size=17, parent=c, name='pin_mask')
    mask.touch_enabled = False
    mask.hidden = True
    button(c, '', (card_w - 50, 6, 40, 40), toggle_pin, name='eye_pin')

    # キーワード
    section('キーワード')
    c = card(52 * 3 + 2)
    for i in range(3):
        field(c, f'kw{i + 1}', f'キーワード{i + 1}', i * 53)
        if i:
            separator(c, i * 53 - 1)

    # サイト名
    section('サイト名（URL を貼り付けても OK）')
    c = card(52 + 1 + 40 + 1 + 56)
    field(c, 'site', '例: amazon.co.jp', 0)
    separator(c, 52)
    label('', (16, 53, card_w - 32, 40), size=14, color=MUTED, parent=c, name='site_preview')
    separator(c, 93)
    button(c, 'キーワード・サイト名をコピー', (card_w - 16 - 300, 94 + 8, 300, 40), copy_keywords)

    # 文字数
    c = card(56)
    label('文字数', (16, 0, 100, 56), parent=c)
    seg = ui.SegmentedControl(name='length', frame=(card_w - 16 - 180, 12, 180, 32))
    seg.segments = [str(n) for n in LENGTHS]
    seg.selected_index = LENGTHS.index(DEFAULT_LENGTH)
    seg.tint_color = ACCENT
    seg.action = set_length
    c.add_subview(seg)

    # 生成・リセット
    c = card(68)
    half = (card_w - 16 * 2 - 12) / 2
    button(c, '生成', (16, 12, half, 44), generate, primary=True)
    button(c, 'リセット', (16 + half + 12, 12, half, 44), reset)

    # 結果
    c = card(96 * 2 + 1)
    for i, (name, title) in enumerate((('pw_symbols', '記号あり:'), ('pw_nosymbols', '記号なし:'))):
        top = i * 97
        if i:
            separator(c, top - 1)
        label(title, (16, top + 8, 120, 40), parent=c)
        button(c, '', (card_w - 16 - 90 - 10 - 40, top + 8, 40, 40),
               lambda sender, n=name: set_visible(n, not state['visible'][n]), name='eye_' + name)
        button(c, 'コピー', (card_w - 16 - 90, top + 8, 90, 40), copy_password, name='copy_' + name)
        tv = ui.TextView(name=name, frame=(12, top + 50, card_w - 24, 40), editable=False, scroll_enabled=False)
        tv.bg_color = CARD
        c.add_subview(tv)

    # 状態表示・注記
    label('', (pad + 4, y[0] - 8, card_w - 8, 44), size=15, color=MUTED, name='status')
    y[0] += 44
    label('今まで作ったパスワードは 3wordPasGen.py（現行方式）で作れます。',
          (pad + 4, y[0], card_w - 8, 40), size=14, color=MUTED)
    y[0] += 56
    content.height = y[0]

    # 部品を名前で取り出せるよう、カードの中もまとめて登録
    named = {}

    def collect(v):
        for sub in v.subviews:
            if sub.name:
                named[sub.name] = sub
            collect(sub)

    collect(scroll)

    class Finder(object):
        def __getitem__(self, key):
            return named[key]

    view = Finder()
    update_pin()
    update_site_preview()
    for name in state['pw']:
        set_visible(name, False)
    root.layout()
    root.present('fullscreen')


if __name__ == '__main__':
    try:
        import ui  # noqa: F401  Pythonista のときだけ存在する
    except ImportError:
        print_test_vectors()
    else:
        run_app()

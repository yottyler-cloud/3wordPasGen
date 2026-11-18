"""3wordPasGen.html / 3wordPasGen2.html の <script> / <style> を書き換えたら実行する。

ページ内の CSP（通信禁止の設定）は、許可するスクリプトとスタイルを
SHA-256 ハッシュで指定している。中身を変えるとハッシュが合わなくなり
ページが動かなくなるため、このスクリプトで最新のハッシュに書き換える。

使い方: python3 web/update_csp.py   （両方のページを更新。中身が同じなら何も変わらない）
"""
import base64
import hashlib
import pathlib
import re

for name in ("3wordPasGen.html", "3wordPasGen2.html"):
    path = pathlib.Path(__file__).with_name(name)
    html = path.read_text(encoding="utf-8")

    def digest(tag):
        blocks = re.findall(rf"<{tag}>(.*?)</{tag}>", html, flags=re.S)
        assert len(blocks) == 1, f"<{tag}> must appear exactly once"
        return "sha256-" + base64.b64encode(hashlib.sha256(blocks[0].encode()).digest()).decode()

    html = re.sub(r"script-src '[^']*'", f"script-src '{digest('script')}'", html, count=1)
    html = re.sub(r"style-src '[^']*'", f"style-src '{digest('style')}'", html, count=1)
    path.write_text(html, encoding="utf-8")
    print(f"CSP updated: {name}")

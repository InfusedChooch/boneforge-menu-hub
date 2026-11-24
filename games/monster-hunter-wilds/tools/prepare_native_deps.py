"""Fetch the exact headers/Lua sources used by the installed REFramework build."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / 'native' / 'vendor'
REF = 'e6c8c59264ec5053a09e1a8530262fd4f36804d1'
IMGUI = '85b2fe8486190fa9326565a2fb5fccb6caea4396'

def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'GHLQOL-native-build'})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()

def main():
    tree = json.loads(fetch(f'https://api.github.com/repos/praydog/REFramework/git/trees/{REF}?recursive=1'))
    files = [
        ('praydog/REFramework', REF, 'include/reframework/API.h', 'reframework/include/reframework/API.h'),
        ('praydog/REFramework', REF, 'src/cimgui/cimgui.h', 'reframework/cimgui.h'),
        ('praydog/REFramework', REF, 'src/re2-imgui/re2_imconfig.hpp', 'imgui/re2_imconfig.hpp'),
        ('praydog/REFramework', REF, 'LICENSE', 'reframework/LICENSE'),
        ('praydog/REFramework', REF, 'dependencies/lua/README', 'lua/README'),
        ('ocornut/imgui', IMGUI, 'imgui.h', 'imgui/imgui.h'),
        ('ocornut/imgui', IMGUI, 'imconfig.h', 'imgui/imconfig.h'),
        ('ocornut/imgui', IMGUI, 'LICENSE.txt', 'imgui/LICENSE.txt'),
    ]
    for item in tree['tree']:
        path = item['path']
        if path.startswith('dependencies/lua/src/') and path.endswith(('.c', '.h')):
            files.append(('praydog/REFramework', REF, path, 'lua/' + Path(path).name))
    def download(item):
        repo, ref, path, target = item
        url = f'https://raw.githubusercontent.com/{repo}/{ref}/{path}'
        data = fetch(url)
        destination = ROOT / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        return target, {'url': url, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
    with ThreadPoolExecutor(max_workers=8) as pool:
        manifest = dict(pool.map(download, files))
    (ROOT / 'manifest.json').write_text(json.dumps({'reframework': REF, 'imgui': IMGUI, 'files': manifest}, indent=2))
    print(f'Prepared {len(manifest)} pinned native build files')

if __name__ == '__main__':
    main()

"""Generate deterministic C++ payloads; never touch installed game files."""
from dataclasses import dataclass
from pathlib import Path
import argparse
import hashlib
import json

PROJECT = Path(__file__).resolve().parents[1]
COMPANIONS = ()
ENGINE_NAMES = ('GenSeries_ParryWindow', 'WpSeries_GreatSword')


@dataclass(frozen=True)
class Payload:
    name: str
    source: str
    data: bytes

    @property
    def sha256(self):
        return hashlib.sha256(self.data).hexdigest()

    def metadata(self):
        return {'name': self.name, 'source': self.source, 'bytes': len(self.data), 'sha256': self.sha256}


def collect(source_root, bridge=None, *, lua_source_root=None):
    source_root = Path(source_root)
    lua_files = {}
    roots = [source_root]
    if lua_source_root is not None:
        roots.append(Path(lua_source_root))
    for root in roots:
        autorun = root / 'reframework/autorun'
        for path in autorun.rglob('*.lua'):
            lua_files[path.relative_to(autorun)] = path
    modules = []
    for relative, path in sorted(lua_files.items()):
        name = relative.with_suffix('').as_posix().replace('/', '.')
        if name != 'GHLQOL' and not name.startswith(('GHLQOL.', 'ParryMeister.')):
            raise ValueError(f'Unexpected embedded module: {relative}')
        data = path.read_bytes().decode('utf-8-sig').encode('utf-8')
        modules.append(Payload(name, relative.as_posix(), data))
    names = [module.name for module in modules]
    if 'GHLQOL' not in names or len(names) != len(set(names)):
        raise ValueError('Embedded modules need one GHLQOL entrypoint and unique require names')
    companions = []
    for name in COMPANIONS:
        data = (source_root / 'reframework/plugins' / name).read_bytes()
        if not data.startswith(b'MZ'):
            raise ValueError(f'{name} is not a PE binary')
        companions.append(Payload(name, f'reframework/plugins/{name}', data))
    bridge_data = Path(bridge).read_bytes() if bridge else b''
    if bridge and not bridge_data.startswith(b'MZ'):
        raise ValueError('The supplied bootstrap bridge is not a PE binary')
    bootstrap = Payload('GHLQOL-bootstrap.dll', 'generated/native-bridge', bridge_data)
    return modules, companions, bootstrap


def collect_engines(source_root):
    project = Path(source_root).parent
    payload_root = project / 'native/payloads'
    provenance = json.loads((payload_root / 'provenance.json').read_text(encoding='utf-8'))
    engines = []
    for name in ENGINE_NAMES:
        record = provenance['engines'][name]
        path = payload_root / (name + '.luac')
        data = path.read_bytes()
        if not data.startswith(b'\x1bLua\x54') or hashlib.sha256(data).hexdigest() != record['sha256']:
            raise ValueError(f'{name} bytecode does not match verified provenance')
        original = project / 'source/reframework/plugins' / (name + '.dll')
        if hashlib.sha256(original.read_bytes()).hexdigest() != record['original_dll_sha256']:
            raise ValueError(f'{name} original engine changed; repeat the extraction/parity checks')
        if not record.get('ordinary_global_environment_only'):
            raise ValueError(f'{name} has unverified captured state')
        engines.append(Payload(name, f'native/payloads/{path.name}', data))
    return engines


def bootstrap_source(payload_id, count):
    # This closure runs once, even after a partially successful initialization.
    return f'''-- Generated GHL QOL embedded startup. No files are extracted.
if rawget(_G, "__ghl_embedded_status") then return end
assert(type(re)=="table" and type(re.on_frame)=="function", "REFramework frame API unavailable")
local status={{state="Waiting",payload="{payload_id}",modules={count},engines=2,companion_dlls=0}}
_G.__ghl_embedded_status=status
local attempted=false
local function report(level,message)
    local writer=log and log[level]
    if type(writer)=="function" then pcall(writer,"[GHL QOL Embedded] "..message) end
end
re.on_frame(function()
    if attempted then return end
    attempted=true
    if rawget(_G,"__ghl_qol_loaded") then
        status.state="Existing loader"
        report("warn","Existing GHL QOL loader owns this Lua state; embedded startup skipped")
        return
    end
    local ok,err=xpcall(function()
        require("GHLQOL.storage").install()
        local profiles=require("GHLQOL.profiles")
        profiles.install()
        profiles.start(function()require("GHLQOL")end)
    end,debug.traceback)
    local loaded=rawget(_G,"__ghl_qol_status")
    if not ok or type(loaded)~="table" or loaded.loaded~=true then
        status.state="Failed"
        status.error=tostring(not ok and err or (loaded and loaded.error) or "GHL QOL did not finish initialization"):sub(1,2000)
        report("error",status.error)
        return
    end
    status.state="Loaded"
    report("info","Embedded modules started once; settings use Documents/WildsMenu")
end)
'''.encode('utf-8')


def byte_array(symbol, data):
    # An empty bridge is permitted for Lua-only tests, not for a root release.
    rows = [','.join(f'0x{value:02x}' for value in data[i:i + 24]) for i in range(0, len(data), 24)]
    return f'inline constexpr unsigned char {symbol}[] = {{\n' + ',\n'.join(rows or ['0']) + '\n};\n'


def generate(source_root, output_dir, bridge=None, *, lua_source_root=None):
    modules, companions, bootstrap = collect(source_root, bridge, lua_source_root=lua_source_root)
    engines = collect_engines(source_root)
    manifest = {'format': 1, 'entrypoint': 'GHLQOL', 'startup': 'first-frame-once',
                'startup_template_sha256': hashlib.sha256(bootstrap_source('', len(modules))).hexdigest(),
                'modules': [item.metadata() for item in modules],
                'companions': [item.metadata() for item in companions],
                'engines': [item.metadata() for item in engines],
                'bootstrap': bootstrap.metadata()}
    payload_id = hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    manifest['payload_id'] = payload_id
    startup = bootstrap_source(payload_id, len(modules))
    manifest['startup_sha256'] = hashlib.sha256(startup).hexdigest()
    header = ['// Generated by tools/generate_embedded_payload.py. Do not edit.\n#pragma once\n#include <cstddef>\n',
              'namespace ghl::embedded {\n',
              'struct LuaModule { const char* name; const char* source; const unsigned char* data; std::size_t size; const char* sha256; };\n',
              'struct EmbeddedBinary { const char* name; const unsigned char* data; std::size_t size; const char* sha256; };\n',
              f'inline constexpr char payload_id[] = "{payload_id}";\n']
    for i, item in enumerate(modules):
        header.append(byte_array(f'module_{i}', item.data))
    header.append('inline constexpr LuaModule modules[] = {\n')
    for i, item in enumerate(modules):
        header.append(f'{{{json.dumps(item.name)}, {json.dumps("@embedded/" + item.source)}, module_{i}, {len(item.data)}, "{item.sha256}"}},\n')
    header.extend(['};\n', 'inline constexpr std::size_t module_count = sizeof(modules) / sizeof(modules[0]);\n'])
    for i, item in enumerate(engines):
        header.append(byte_array(f'engine_{i}', item.data))
    header.append('inline constexpr EmbeddedBinary engines[] = {\n')
    for i, item in enumerate(engines):
        header.append(f'{{{json.dumps(item.name)}, engine_{i}, {len(item.data)}, "{item.sha256}"}},\n')
    header.extend(['};\n', 'inline constexpr std::size_t engine_count = sizeof(engines) / sizeof(engines[0]);\n',
                   byte_array('bootstrap_bytes', bootstrap.data),
                   f'inline constexpr EmbeddedBinary bootstrap = {{"{bootstrap.name}", bootstrap_bytes, {len(bootstrap.data)}, "{bootstrap.sha256}"}};\n',
                   byte_array('bootstrap_script', startup),
                   f'inline constexpr std::size_t bootstrap_script_size = {len(startup)};\n',
                   '} // namespace ghl::embedded\n'])
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = {'embedded_payload.hpp': ''.join(header).encode('utf-8'),
               'embedded_payload.json': (json.dumps(manifest, indent=2) + '\n').encode('utf-8')}
    for name, data in outputs.items():
        target = output_dir / name
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=PROJECT / 'source')
    parser.add_argument('--lua-source-root', type=Path, help='Lua sources with priority over the local content root')
    parser.add_argument('--output-dir', type=Path, default=PROJECT / 'native/generated')
    parser.add_argument('--bridge', type=Path)
    args = parser.parse_args()
    try:
        manifest = generate(args.source_root, args.output_dir, args.bridge, lua_source_root=args.lua_source_root)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f'Cannot generate embedded payload: {error}\n')
    print(json.dumps({'modules': len(manifest['modules']), 'engines': len(manifest['engines']), 'companions': len(manifest['companions']),
                      'bridge_bytes': manifest['bootstrap']['bytes'], 'payload_id': manifest['payload_id']}, indent=2))


if __name__ == '__main__':
    main()

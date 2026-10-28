#!/usr/bin/env python3
"""Build Vata's file-icon bundle: map extensions to the SVG set, rasterize
with rsvg-convert, emit FileIconMap.swift. Rerun when assets change."""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "assets", "fileicons")
OUT = os.path.join(ROOT, "Sources", "FileIcons")
os.makedirs(OUT, exist_ok=True)

def have(stem, light=False):
    for prefix in (["file-type-light-", "file-type-"] if light else ["file-type-", "file-type-light-"]):
        for suffix in ("", "2"):
            p = os.path.join(SRC, f"{prefix}{stem}{suffix}.svg")
            if os.path.exists(p):
                return os.path.basename(p)
    return None

# extension -> icon stem (curated; stem match tried after this table)
OVERRIDES = {
    "py": "python", "pyw": "python", "pyi": "python",
    "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "react",
    "ts": "typescript", "mts": "typescript", "cts": "typescript", "tsx": "react_ts",
    "rb": "ruby", "php": "php", "java": "java", "kt": "kotlin", "kts": "kotlin",
    "swift": "swift", "go": "go", "rs": "rust", "c": "c", "h": "cheader",
    "cpp": "cpp", "hpp": "cppheader", "cc": "cpp", "cxx": "cpp", "cs": "csharp",
    "m": "matlab", "mm": "objectivec", "sh": "shell", "bash": "shell", "zsh": "shell",
    "fish": "shell", "ps1": "powershell", "bat": "bat", "cmd": "cmd",
    "html": "html", "htm": "html", "css": "css", "scss": "scss", "sass": "sass",
    "less": "less", "vue": "vue", "svelte": "svelte", "astro": "astro",
    "json": "json", "jsonc": "json", "yaml": "yaml", "yml": "yaml", "toml": "toml",
    "xml": "xml", "plist": "plist", "md": "markdown", "markdown": "markdown",
    "txt": "text", "log": "log", "csv": "csv", "tsv": "csv",
    "png": "image", "jpg": "image", "jpeg": "image", "gif": "image",
    "webp": "image", "avif": "avif", "svg": "svg", "ico": "image", "bmp": "image",
    "tiff": "image", "tif": "image", "heic": "image", "psd": "photoshop",
    "ai": "ai", "sketch": "sketch", "fig": "figma",
    "mp3": "audio", "wav": "audio", "flac": "audio", "ogg": "audio", "m4a": "audio",
    "mp4": "video", "mov": "video", "mkv": "video", "avi": "video", "webm": "video",
    "zip": "zip", "tar": "zip", "gz": "zip", "bz2": "zip", "xz": "zip", "7z": "zip",
    "rar": "zip", "dmg": "dmg", "pkg": "installer", "iso": "iso",
    "pdf": "pdf", "doc": "word", "docx": "word", "xls": "excel", "xlsx": "excel",
    "ppt": "powerpoint", "pptx": "powerpoint", "key": "keynote", "numbers": "numbers",
    "pages": "pages", "sqlite": "sqlite", "db": "database", "sql": "sql",
    "r": "r", "jl": "julia", "lua": "lua", "pl": "perl", "pm": "perl",
    "scala": "scala", "hs": "haskell", "elm": "elm", "ex": "elixir", "exs": "elixir",
    "erl": "erlang", "hrl": "erlang", "clj": "clojure", "dart": "dart",
    "tf": "terraform", "dockerfile": "docker", "vagrantfile": "vagrant",
    "lock": "lock", "env": "env", "gitignore": "git", "gitattributes": "git",
    "cfg": "config", "ini": "config", "conf": "config",
    "tex": "tex", "bib": "bibtex", "org": "org", "rst": "rst", "adoc": "asciidoc",
    "wasm": "wasm", "o": "binary", "a": "binary", "so": "binary", "dylib": "binary",
    "exe": "exe", "dll": "dll", "class": "java", "jar": "jar",
    "woff": "font", "woff2": "font", "ttf": "font", "otf": "font", "eot": "font",
    "ipynb": "jupyter", "rdata": "r", "rds": "r", "mat": "matlab",
    "proto": "protobuf", "graphql": "graphql", "gql": "graphql",
    "vim": "vim", "el": "emacs", "tmux": "tmux",
    "applescript": "applescript", "scpt": "applescript",
}

FOLDERS = {
    ".git": "git", ".github": "github", ".vscode": "vscode", ".idea": "idea",
    "node_modules": "node", "__pycache__": "python", ".venv": "python",
    "venv": "python", "dist": "dist", "build": "build", "out": "out",
    "src": "src", "source": "src", "test": "test", "tests": "test",
    "docs": "docs", "doc": "docs", "assets": "assets", "images": "images",
    "img": "images", "fonts": "fonts", "font": "fonts", "css": "css",
    "public": "public", "static": "static", "templates": "templates",
    "components": "components", "app": "app", "lib": "lib", "bin": "bin",
    "scripts": "scripts", "tools": "tools", "docker": "docker",
    ".docker": "docker", "config": "config", "configs": "config",
    "locales": "locale", "i18n": "locale",
}

def folder_svg(name):
    for cand in (f"folder-type-{name}.svg", f"folder-type-light-{name}.svg"):
        if os.path.exists(os.path.join(SRC, cand)):
            return cand
    return None

extmap, used = {}, set()
stems = set()
for f in os.listdir(SRC):
    m = re.match(r"file-type-(light-)?(.+?)(2)?\.svg$", f)
    if m:
        stems.add(m.group(2))

candidates = set(OVERRIDES.values())
for ext, stem in OVERRIDES.items():
    hit = have(stem) or (have(ext) if ext in stems else None)
    if hit:
        extmap[ext] = os.path.splitext(hit)[0]
        used.add(hit)
# stem==ext direct matches for common short exts
for stem in sorted(stems):
    if len(stem) <= 5 and stem not in extmap and have(stem):
        hit = have(stem)
        extmap[stem] = os.path.splitext(hit)[0]
        used.add(hit)

foldermap = {}
for name, stem in FOLDERS.items():
    hit = folder_svg(stem)
    if hit:
        foldermap[name] = os.path.splitext(hit)[0]
        used.add(hit)
for base in ("default-file.svg", "default-folder.svg", "default-folder-opened.svg",
             "default-root-folder.svg", "default-root-folder-opened.svg"):
    if os.path.exists(os.path.join(SRC, base)):
        used.add(base)

# rasterize @32px and @64px
for svg in sorted(used):
    stem = os.path.splitext(svg)[0]
    src = os.path.join(SRC, svg)
    subprocess.run(["rsvg-convert", "-w", "32", "-h", "32", "-o",
                    os.path.join(OUT, f"{stem}.png"), src], check=True)
    subprocess.run(["rsvg-convert", "-w", "64", "-h", "64", "-o",
                    os.path.join(OUT, f"{stem}@2x.png"), src], check=True)

with open(os.path.join(ROOT, "Sources", "FileIconMap.swift"), "w") as f:
    f.write("// GENERATED by gen-icons.py — do not edit.\n")
    f.write("import Foundation\n\nstruct FileIconMap {\n")
    f.write("    static let byExtension: [String: String] = [\n")
    for ext in sorted(extmap):
        f.write(f'        "{ext}": "{extmap[ext]}",\n')
    f.write("    ]\n    static let byFolder: [String: String] = [\n")
    for name in sorted(foldermap):
        f.write(f'        "{name}": "{foldermap[name]}",\n')
    f.write("    ]\n}\n")

print(f"extensions={len(extmap)} folders={len(foldermap)} rasterized={len(used)}")

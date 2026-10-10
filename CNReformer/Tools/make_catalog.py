#!/usr/bin/env python3
"""Create an HTTPS-folder catalog; does not upload files or change source documents."""
import argparse
import json
from pathlib import Path
from urllib.parse import quote

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('folder', type=Path)
args = parser.parse_args()
folder = args.folder.resolve(strict=True)
if not folder.is_dir():
    parser.error('folder must be a directory')
items = []
for file in sorted(folder.rglob('*')):
    if not file.is_file() or file.suffix.lower() not in {'.pdf', '.key', '.ppt', '.pptx'}:
        continue
    relative = file.relative_to(folder).as_posix()
    if any(part.startswith('.') for part in file.relative_to(folder).parts):
        continue
    items.append({'id': relative, 'title': file.stem, 'url': quote(relative, safe='/')})
output = folder / 'cnreformer.json'
output.write_text(json.dumps({'version': 1, 'documents': items}, ensure_ascii=False, indent=2) + '\n')
print(f'Wrote {len(items)} documents to {output}')

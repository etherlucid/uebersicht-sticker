#!/usr/bin/env python3
import sys
import os
import json
import math

def process_webp(source_path, dest_dir=None):
    if not os.path.exists(source_path):
        return None

    if not dest_dir:
        dest_dir = os.path.dirname(os.path.abspath(source_path))

    os.makedirs(dest_dir, exist_ok=True)
    base_name = os.path.splitext(os.path.basename(source_path))[0]
    # Remove any existing trailing _sheet if present
    if base_name.endswith('_sheet'):
        base_name = base_name[:-6]

    meta_path = os.path.join(dest_dir, f"{base_name}_meta.json")
    sheet_path = os.path.join(dest_dir, f"{base_name}_sheet.webp")

    # If meta and sheet already exist and are newer than source, return existing meta
    if os.path.exists(meta_path) and os.path.exists(sheet_path):
        source_mtime = os.path.getmtime(source_path)
        meta_mtime = os.path.getmtime(meta_path)
        sheet_mtime = os.path.getmtime(sheet_path)
        if meta_mtime >= source_mtime and sheet_mtime >= source_mtime:
            try:
                with open(meta_path, 'r') as f:
                    return json.load(f)
            except Exception:
                pass

    from PIL import Image, ImageSequence

    try:
        im = Image.open(source_path)
    except Exception as e:
        print(f"Error opening image: {e}", file=sys.stderr)
        return None

    is_animated = getattr(im, 'is_animated', False) and getattr(im, 'n_frames', 1) > 1

    if not is_animated:
        w, h = im.size
        clean_filename = os.path.basename(source_path)
        rel_sheet = f"sticker.widget/stickers/{clean_filename}"
        meta = {
            "isAnimated": False,
            "width": w,
            "height": h,
            "totalFrames": 1,
            "cols": 1,
            "rows": 1,
            "frameDuration": 0,
            "sheet": rel_sheet
        }
        with open(meta_path, 'w') as f:
            json.dump(meta, f, indent=2)
        return meta

    frames = [f.convert('RGBA') for f in ImageSequence.Iterator(im)]
    n = len(frames)
    w, h = frames[0].size

    durs = [f.info.get('duration', 70) for f in ImageSequence.Iterator(im)]
    durs = [d if d > 10 else 70 for d in durs]
    avg_dur = round(sum(durs) / len(durs)) if durs else 70

    cols = math.ceil(math.sqrt(n * (h / w))) if w > 0 else 12
    cols = max(1, min(cols, 20))
    rows = math.ceil(n / cols)

    sheet = Image.new('RGBA', (cols * w, rows * h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        c = i % cols
        r = i // cols
        sheet.paste(f, (c * w, r * h))

    sheet.save(sheet_path, quality=95, method=2)

    rel_sheet = f"sticker.widget/stickers/{base_name}_sheet.webp"
    meta = {
        "isAnimated": True,
        "width": w,
        "height": h,
        "totalFrames": n,
        "cols": cols,
        "rows": rows,
        "frameDuration": avg_dur,
        "sheet": rel_sheet
    }

    with open(meta_path, 'w') as f:
        json.dump(meta, f, indent=2)

    return meta

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: sheet_generator.py <source_path> [dest_dir]", file=sys.stderr)
        sys.exit(1)

    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else None
    res = process_webp(src, dst)
    if res:
        print(json.dumps(res))
    else:
        sys.exit(1)

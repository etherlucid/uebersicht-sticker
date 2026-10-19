#!/usr/bin/env python3
import sys
import os
import json
import math

def extract_frames(im):
    from PIL import Image, ImageSequence
    w, h = im.size
    frames = []
    durs = []

    is_anim = getattr(im, 'is_animated', False) and getattr(im, 'n_frames', 1) > 1
    if not is_anim:
        return [im.convert('RGBA')], [0], False

    fmt = (im.format or '').upper()

    if fmt == 'GIF':
        last_frame = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        prev_frame = None

        for i in range(im.n_frames):
            im.seek(i)
            dur = im.info.get('duration', 70)
            if not dur or dur <= 10:
                dur = 70
            durs.append(dur)

            disposal = getattr(im, 'disposal_method', None) or im.info.get('disposal', 0)
            cur = im.convert('RGBA')

            if disposal == 3:
                prev_frame = last_frame.copy()

            composed = last_frame.copy()
            if cur.size == (w, h):
                composed.alpha_composite(cur)
            else:
                composed.paste(cur, (0, 0), cur)
            frames.append(composed.copy())

            if disposal == 2:
                last_frame = Image.new('RGBA', (w, h), (0, 0, 0, 0))
            elif disposal == 3:
                last_frame = prev_frame if prev_frame else Image.new('RGBA', (w, h), (0, 0, 0, 0))
            else:
                last_frame = composed
    else:
        for f in ImageSequence.Iterator(im):
            dur = f.info.get('duration', 70)
            if not dur or dur <= 10:
                dur = 70
            durs.append(dur)
            frames.append(f.convert('RGBA'))

    return frames, durs, True

def process_image(source_path, dest_dir=None):
    if not os.path.exists(source_path):
        return None

    if not dest_dir:
        dest_dir = os.path.dirname(os.path.abspath(source_path))

    os.makedirs(dest_dir, exist_ok=True)
    clean_filename = os.path.basename(source_path)
    base_name = os.path.splitext(clean_filename)[0]

    # Remove any existing trailing _sheet if present
    if base_name.endswith('_sheet'):
        base_name = base_name[:-6]

    meta_path = os.path.join(dest_dir, f"{base_name}_meta.json")
    sheet_path = os.path.join(dest_dir, f"{base_name}_sheet.webp")

    # If meta already exists and is newer than source, check if we can reuse
    if os.path.exists(meta_path):
        source_mtime = os.path.getmtime(source_path)
        meta_mtime = os.path.getmtime(meta_path)
        if meta_mtime >= source_mtime:
            try:
                with open(meta_path, 'r') as f:
                    cached_meta = json.load(f)
                if cached_meta.get("isAnimated"):
                    if os.path.exists(sheet_path) and os.path.getmtime(sheet_path) >= source_mtime:
                        return cached_meta
                else:
                    return cached_meta
            except Exception:
                pass

    from PIL import Image

    try:
        im = Image.open(source_path)
    except Exception as e:
        print(f"Error opening image: {e}", file=sys.stderr)
        return None

    frames, durs, is_animated = extract_frames(im)

    if not is_animated:
        w, h = im.size
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

    n = len(frames)
    if n == 0:
        return None

    w, h = frames[0].size
    avg_dur = round(sum(durs) / len(durs)) if durs else 70

    cols = math.ceil(math.sqrt(n * (h / w))) if w > 0 else 12
    cols = max(1, min(cols, 20))
    rows = math.ceil(n / cols)

    sheet = Image.new('RGBA', (cols * w, rows * h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        c = i % cols
        r = i // cols
        sheet.paste(f, (c * w, r * h))

    sheet.save(sheet_path, 'WEBP', quality=95, method=2)

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

process_webp = process_image

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: sheet_generator.py <source_path> [dest_dir]", file=sys.stderr)
        sys.exit(1)

    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else None
    res = process_image(src, dst)
    if res:
        print(json.dumps(res))
    else:
        sys.exit(1)

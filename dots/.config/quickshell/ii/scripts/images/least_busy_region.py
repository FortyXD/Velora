#!/usr/bin/env python3
import os
os.environ["OPENCV_LOG_LEVEL"] = "SILENT"
import cv2
import numpy as np
import argparse
import json
from functools import lru_cache

# Several desktop widgets may analyze a wallpaper at once.
cv2.setNumThreads(1)

def center_crop(img, target_w, target_h):
    h, w = img.shape[:2]
    if w == target_w and h == target_h:
        return img
    x1 = max(0, (w - target_w) // 2)
    y1 = max(0, (h - target_h) // 2)
    x2 = x1 + target_w
    y2 = y1 + target_h
    return img[y1:y2, x1:x2]

def find_least_busy_region(image_path, region_width=300, region_height=200, screen_width=None, screen_height=None, verbose=False, stride=2, screen_mode="fill", horizontal_padding=50, vertical_padding=50, busiest=False, slot=0, gap=120):
    img = cv2.cvtColor(load_wallpaper(image_path, screen_width, screen_height, screen_mode), cv2.COLOR_BGR2GRAY)
    h, w = img.shape
    stride = max(1, int(stride) if stride else 1)
    # Adjust region size if it does not fit given padding
    if horizontal_padding * 2 >= w or vertical_padding * 2 >= h:
        # Reduce padding to fit at least a 1x1 region
        horizontal_padding = max(0, min(horizontal_padding, (w - 1) // 2))
        vertical_padding = max(0, min(vertical_padding, (h - 1) // 2))
    max_region_w = w - 2 * horizontal_padding
    max_region_h = h - 2 * vertical_padding
    if max_region_w <= 0 or max_region_h <= 0:
        raise ValueError("Image too small for the specified padding.")
    if region_width > max_region_w:
        if verbose:
            print(f"Requested region_width {region_width} too large; clamping to {max_region_w}")
        region_width = max_region_w
    if region_height > max_region_h:
        if verbose:
            print(f"Requested region_height {region_height} too large; clamping to {max_region_h}")
        region_height = max_region_h
    # Evaluate all windows in NumPy instead of running a Python loop for every pixel window.
    integral, integral_sq = cv2.integral2(img, sdepth=cv2.CV_64F, sqdepth=cv2.CV_64F)
    xs = np.arange(horizontal_padding, w - region_width - horizontal_padding + 1, stride)
    ys = np.arange(vertical_padding, h - region_height - vertical_padding + 1, stride)
    xx, yy = np.meshgrid(xs, ys)
    x2, y2 = xx + region_width, yy + region_height
    area = region_width * region_height
    sums = integral[y2, x2] - integral[yy, x2] - integral[y2, xx] + integral[yy, xx]
    squares = integral_sq[y2, x2] - integral_sq[yy, x2] - integral_sq[y2, xx] + integral_sq[yy, xx]
    variances = np.maximum(0, squares / area - (sums / area) ** 2)
    candidates = list(zip(variances.ravel().tolist(), xx.ravel().tolist(), yy.ravel().tolist()))
    if not candidates:
        return (horizontal_padding, vertical_padding), None
    # Stable order, so every widget sees the same sequence of spots
    candidates.sort(key=lambda c: (-c[0] if busiest else c[0], c[2], c[1]))
    # Slot N is the best spot that keeps a gap from slots 0..N-1, so several widgets don't stack up
    taken = []
    best = candidates[0]
    for _ in range(slot + 1):
        found = next((c for c in candidates if not any(
            c[1] < tx2 and c[1] + region_width > tx1 and c[2] < ty2 and c[2] + region_height > ty1
            for tx1, ty1, tx2, ty2 in taken)), None)
        if found is None:
            break  # No room left: share the last spot
        best = found
        taken.append((best[1] - gap, best[2] - gap, best[1] + region_width + gap, best[2] + region_height + gap))
    return (best[1], best[2]), best[0]

def find_largest_region(image_path, screen_width=None, screen_height=None, verbose=False, stride=2, screen_mode="fill", threshold=100.0, aspect_ratio=1.0, horizontal_padding=50, vertical_padding=50):
    img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError(f"Image not found: {image_path}")
    orig_h, orig_w = img.shape
    # ...existing scaling logic...
    scale = 1.0
    if screen_width is not None and screen_height is not None:
        scale_w = screen_width / orig_w
        scale_h = screen_height / orig_h
        if screen_mode == "fill":
            scale = max(scale_w, scale_h)
        else:
            scale = min(scale_w, scale_h)
        new_w = int(orig_w * scale)
        new_h = int(orig_h * scale)
        if verbose:
            print(f"Scaling image from {orig_w}x{orig_h} to {new_w}x{new_h} (scale: {scale:.3f}, mode: {screen_mode})")
        img = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        img = center_crop(img, screen_width, screen_height)
        if verbose:
            print(f"Cropped image to {screen_width}x{screen_height}")
    else:
        if verbose:
            print(f"Using original image size: {orig_w}x{orig_h}")
    arr = img.astype(np.float64)
    h, w = arr.shape
    stride = max(1, int(stride) if stride else 1)
    threshold = max(0.0, float(threshold))
    # Adjust padding if image too small
    if horizontal_padding * 2 >= w or vertical_padding * 2 >= h:
        horizontal_padding = max(0, min(horizontal_padding, (w - 1) // 2))
        vertical_padding = max(0, min(vertical_padding, (h - 1) // 2))
    # Use OpenCV's integral for fast computation
    integral = cv2.integral(arr, sdepth=cv2.CV_64F)[1:,1:]
    integral_sq = cv2.integral(arr**2, sdepth=cv2.CV_64F)[1:,1:]
    def region_sum(ii, x1, y1, x2, y2):
        total = ii[y2, x2]
        if x1 > 0:
            total -= ii[y2, x1-1]
        if y1 > 0:
            total -= ii[y1-1, x2]
        if x1 > 0 and y1 > 0:
            total += ii[y1-1, x1-1]
        return total
    min_size = 10
    # Determine maximum feasible size respecting padding
    effective_w = w - 2 * horizontal_padding
    effective_h = h - 2 * vertical_padding
    if effective_w <= 0 or effective_h <= 0:
        return None, (0, 0), None
    # Largest square-ish dimension given aspect ratio and effective space
    if aspect_ratio >= 1.0:
        max_size = min(effective_h, int(effective_w / aspect_ratio))
    else:
        max_size = min(int(effective_h * aspect_ratio), effective_w)
    if max_size < min_size:
        min_size = 1
        max_size = max(1, max_size)
    best = None
    while min_size <= max_size:
        mid = (min_size + max_size) // 2
        if aspect_ratio >= 1.0:
            region_h = mid
            region_w = int(round(mid * aspect_ratio))
        else:
            region_w = mid
            region_h = int(round(mid / aspect_ratio if aspect_ratio != 0 else mid))
        if region_w <= 0 or region_h <= 0:
            break
        if region_w > effective_w or region_h > effective_h:
            max_size = mid - 1
            continue
        found = False
        x_start = horizontal_padding
        y_start = vertical_padding
        x_end = w - region_w - horizontal_padding
        y_end = h - region_h - vertical_padding
        for y in range(y_start, y_end + 1, stride):
            for x in range(x_start, x_end + 1, stride):
                x1, y1 = x, y
                x2, y2 = x + region_w - 1, y + region_h - 1
                if x2 >= w or y2 >= h:
                    continue
                s = region_sum(integral, x1, y1, x2, y2)
                s2 = region_sum(integral_sq, x1, y1, x2, y2)
                area = region_w * region_h
                mean = s / area
                var = (s2 / area) - (mean ** 2)
                if var <= threshold:
                    found = True
                    best = (x, y, region_w, region_h, var)
                    break
            if found:
                break
        if found:
            min_size = mid + 1
        else:
            max_size = mid - 1
    if best:
        x, y, region_w, region_h, var = best
        center_x = x + region_w // 2
        center_y = y + region_h // 2
        return (center_x, center_y), (region_w, region_h), var
    else:
        return None, (0, 0), None

def draw_region(image_path, coords, region_width=300, region_height=200, output_path='output.png', screen_width=None, screen_height=None, screen_mode="fill"):
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Image not found: {image_path}")
    orig_h, orig_w = img.shape[:2]
    if screen_width is not None and screen_height is not None:
        scale_w = screen_width / orig_w
        scale_h = screen_height / orig_h
        if screen_mode == "fill":
            scale = max(scale_w, scale_h)
        else:
            scale = min(scale_w, scale_h)
        new_w = int(orig_w * scale)
        new_h = int(orig_h * scale)
        img = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        img = center_crop(img, screen_width, screen_height)
    x, y = coords
    cv2.rectangle(img, (x, y), (x+region_width-1, y+region_height-1), (0,0,255), 3)
    cv2.imwrite(output_path, img)
    # print removed for quieter operation

def draw_largest_region(image_path, center, size, output_path='output.png', screen_width=None, screen_height=None, screen_mode="fill"):
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Image not found: {image_path}")
    orig_h, orig_w = img.shape[:2]
    if screen_width is not None and screen_height is not None:
        scale_w = screen_width / orig_w
        scale_h = screen_height / orig_h
        if screen_mode == "fill":
            scale = max(scale_w, scale_h)
        else:
            scale = min(scale_w, scale_h)
        new_w = int(orig_w * scale)
        new_h = int(orig_h * scale)
        img = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        img = center_crop(img, screen_width, screen_height)
    cx, cy = center
    region_w, region_h = size
    x1 = cx - region_w // 2
    y1 = cy - region_h // 2
    x2 = cx + region_w // 2 - 1
    y2 = cy + region_h // 2 - 1
    cv2.rectangle(img, (x1, y1), (x2, y2), (255,0,0), 3)
    cv2.imwrite(output_path, img)
    # print removed for quieter operation

@lru_cache(maxsize=2)
def load_wallpaper(image_path, screen_width=None, screen_height=None, screen_mode="fill"):
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Image not found: {image_path}")
    if screen_width is not None and screen_height is not None:
        h, w = img.shape[:2]
        scale = (max if screen_mode == "fill" else min)(screen_width / w, screen_height / h)
        img = cv2.resize(img, (max(1, round(w * scale)), max(1, round(h * scale))),
                         interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_LINEAR)
        img = center_crop(img, screen_width, screen_height)
    return img


def get_dominant_color(image_path, x, y, w, h, screen_width=None, screen_height=None, screen_mode="fill"):
    img = load_wallpaper(image_path, screen_width, screen_height, screen_mode)
    x = max(0, min(int(x), img.shape[1] - 1))
    y = max(0, min(int(y), img.shape[0] - 1))
    w = max(1, min(int(w), img.shape[1] - x))
    h = max(1, min(int(h), img.shape[0] - y))
    region = img[y:y+h, x:x+w]
    # A bounded, deterministic sample is enough for text contrast. K-means over
    # every pixel was expensive and could give a different answer on each run.
    sample = cv2.resize(region, (min(64, w), min(64, h)), interpolation=cv2.INTER_AREA)
    bgr = np.median(sample.reshape(-1, 3), axis=0)
    return [int(channel) for channel in reversed(bgr)]

def main():
    parser = argparse.ArgumentParser(description="Find least busy region in an image and output a JSON. Made for determining a suitable position for a wallpaper widget.")
    parser.add_argument("image_path", help="Path to the input image")
    parser.add_argument("--width", type=int, default=300, help="Region width")
    parser.add_argument("--height", type=int, default=200, help="Region height")
    parser.add_argument("-v", "--visual-output", action="store_true", help="Output image with rectangle")
    parser.add_argument("--screen-width", type=int, default=1920, help="Screen width for wallpaper scaling")
    parser.add_argument("--screen-height", type=int, default=1080, help="Screen height for wallpaper scaling")
    parser.add_argument("--stride", type=int, default=10, help="Step size for sliding window (higher is faster, less precise)")
    parser.add_argument("--screen-mode", choices=["fill", "fit"], default="fill", help="Wallpaper scaling mode: 'fill' (default) or 'fit'")
    parser.add_argument("--verbose", action="store_true", help="Print verbose output")
    parser.add_argument("-l", "--largest-region", action="store_true", help="Find the largest region under the variance threshold and output its center")
    parser.add_argument("-t", "--variance-threshold", type=float, default=1000.0, help="Variance threshold for largest region mode")
    parser.add_argument("--aspect-ratio", type=float, default=1.78, help="Aspect ratio (width/height) for largest region mode")
    parser.add_argument("--horizontal-padding", "-hp", type=int, default=50, help="Minimum horizontal distance from region to image edge")
    parser.add_argument("--vertical-padding", "-vp", type=int, default=50, help="Minimum vertical distance from region to image edge")
    parser.add_argument("--busiest", action="store_true", help="Find the busiest region instead of the least busy")
    parser.add_argument("--slot", type=int, default=0, help="Take the Nth best region that keeps clear of the regions before it")
    parser.add_argument("--gap", type=int, default=120, help="Space kept between the regions of different slots")
    parser.add_argument("--sample-x", type=int, help="Sample a widget at its existing position instead of searching")
    parser.add_argument("--sample-y", type=int, default=0)
    args = parser.parse_args()

    if args.sample_x is not None:
        color = get_dominant_color(args.image_path, args.sample_x, args.sample_y, args.width, args.height,
                                   args.screen_width, args.screen_height, args.screen_mode)
        print(json.dumps({"dominant_color": '#{:02x}{:02x}{:02x}'.format(*color)}))
        return

    if args.largest_region:
        center, size, var = find_largest_region(
            args.image_path,
            screen_width=args.screen_width,
            screen_height=args.screen_height,
            verbose=args.verbose,
            stride=args.stride,
            screen_mode=args.screen_mode,
            threshold=args.variance_threshold,
            aspect_ratio=args.aspect_ratio,
            horizontal_padding=args.horizontal_padding,
            vertical_padding=args.vertical_padding
        )
        if center:
            if args.visual_output:
                draw_largest_region(args.image_path, center, size, screen_width=args.screen_width, screen_height=args.screen_height, screen_mode=args.screen_mode)
            # Extract dominant color
            cx, cy = center
            region_w, region_h = size
            x1 = cx - region_w // 2
            y1 = cy - region_h // 2
            dominant_color = get_dominant_color(
                args.image_path, x1, y1, region_w, region_h,
                screen_width=args.screen_width, screen_height=args.screen_height, screen_mode=args.screen_mode
            )
            dominant_color_hex = '#{:02x}{:02x}{:02x}'.format(*dominant_color)
            print(json.dumps({
                "center_x": center[0],
                "center_y": center[1],
                "width": size[0],
                "height": size[1],
                "variance": var,
                "dominant_color": dominant_color_hex
            }))
        else:
            print(json.dumps({"error": "No region found under the threshold."}))
        return

    coords, variance = find_least_busy_region(
        args.image_path,
        region_width=args.width,
        region_height=args.height,
        screen_width=args.screen_width,
        screen_height=args.screen_height,
        verbose=args.verbose,
        stride=args.stride,
        screen_mode=args.screen_mode,
        horizontal_padding=args.horizontal_padding,
        vertical_padding=args.vertical_padding,
        busiest=args.busiest,
        slot=max(0, args.slot),
        gap=args.gap
    )
    if args.visual_output:
        draw_region(args.image_path, coords, region_width=args.width, region_height=args.height, screen_width=args.screen_width, screen_height=args.screen_height, screen_mode=args.screen_mode)
    # Output JSON with center point
    center_x = coords[0] + args.width // 2
    center_y = coords[1] + args.height // 2
    dominant_color = get_dominant_color(
        args.image_path, coords[0], coords[1], args.width, args.height,
        screen_width=args.screen_width, screen_height=args.screen_height, screen_mode=args.screen_mode
    )
    dominant_color_hex = '#{:02x}{:02x}{:02x}'.format(*dominant_color)
    print(json.dumps({
        "center_x": center_x,
        "center_y": center_y,
        "width": args.width,
        "height": args.height,
        "variance": variance,
        "dominant_color": dominant_color_hex
    }))

if __name__ == "__main__":
    main()


#!/usr/bin/env python3
"""Backend of the Folis toolbox window: file conversion, downloads, QR codes, OCR and palettes.

Every command prints JSON, one object per line, so the window can follow progress:
  {"event": "start" | "progress" | "done" | "error" | "finished", ...}
Child tools run in their own process group; SIGTERM stops them too, so cancelling never leaves
an ffmpeg or yt-dlp running. Results are written to a temporary name and renamed at the end,
and never overwrite an existing file.
"""

import argparse
import json
import mimetypes
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile

CHILD = None
PENDING = None  # Unfinished result, removed if the run is cancelled

TOOLS = ["magick", "ffmpeg", "ffprobe", "soffice", "libreoffice", "pandoc", "pdftoppm", "pdfinfo", "qpdf", "gs",
         "7z", "bsdtar", "zstd", "yt-dlp", "qrencode", "zbarimg", "tesseract", "hyprpicker", "grim", "slurp",
         "wl-copy", "wl-paste", "kdialog", "file"]

IMAGE_TARGETS = ["png", "jpg", "webp", "avif", "heic", "ico", "bmp", "tiff", "gif", "pdf"]
VIDEO_TARGETS = ["mp4", "webm", "mkv", "gif", "mp3", "opus", "flac", "m4a"]
AUDIO_TARGETS = ["mp3", "opus", "ogg", "flac", "wav", "m4a"]
DOCUMENT_TARGETS = ["pdf", "docx", "odt", "html", "md", "txt", "epub"]
PDF_TARGETS = ["png", "jpg", "txt", "docx", "pdf-merge", "pdf-compress"]
ARCHIVE_TARGETS = ["extract"]
PACK_TARGETS = ["zip", "7z", "tar.gz", "tar.zst"]

DOCUMENT_EXTS = {"doc", "docx", "odt", "rtf", "txt", "md", "markdown", "html", "htm", "epub", "ods", "xls", "xlsx",
                 "odp", "ppt", "pptx", "csv", "tex", "rst", "org"}
ARCHIVE_EXTS = {"zip", "7z", "rar", "tar", "gz", "tgz", "xz", "txz", "bz2", "tbz2", "zst", "tzst", "iso"}


def emit(**event):
    print(json.dumps(event, ensure_ascii=False), flush=True)


def stop(_signum, _frame):
    if CHILD and CHILD.poll() is None:
        try:
            os.killpg(CHILD.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if PENDING and os.path.exists(PENDING):
        if os.path.isdir(PENDING):
            shutil.rmtree(PENDING, ignore_errors=True)
        else:
            os.remove(PENDING)
    emit(event="cancelled")
    sys.exit(130)


def run(cmd, on_line=None, cwd=None, stdin=None):
    """Runs a tool in its own process group; returns (code, last lines of output)."""
    global CHILD
    CHILD = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=cwd,
                             stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                             start_new_session=True, errors="replace")
    if stdin is not None:
        CHILD.stdin.write(stdin)
        CHILD.stdin.close()
    tail = []
    for line in CHILD.stdout:
        line = line.rstrip("\n")
        tail = (tail + [line])[-60:]
        if on_line:
            on_line(line)
    code = CHILD.wait()
    CHILD = None
    return code, tail


def have(tool):
    return shutil.which(tool) is not None


def office():
    return shutil.which("soffice") or shutil.which("libreoffice")


def ext_of(path):
    name = os.path.basename(path).lower()
    for double in ("tar.gz", "tar.zst", "tar.xz", "tar.bz2"):
        if name.endswith("." + double):
            return double
    return name.rsplit(".", 1)[-1] if "." in name else ""


def kind_of(path):
    mime = ""
    if have("file"):
        try:
            mime = subprocess.run(["file", "--brief", "--mime-type", "--", path], capture_output=True, text=True,
                                  timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            mime = ""
    if not mime:
        mime = mimetypes.guess_type(path)[0] or ""
    ext = ext_of(path)
    if os.path.isdir(path):
        return "folder", "inode/directory"
    if mime == "application/pdf" or ext == "pdf":
        return "pdf", mime
    if mime.startswith("image/") or ext in ("heic", "heif", "avif"):
        return "image", mime
    if mime.startswith("video/"):
        return "video", mime
    if mime.startswith("audio/"):
        return "audio", mime
    if ext in ARCHIVE_EXTS or ext.startswith("tar.") or "zip" in mime or "x-7z" in mime or "x-tar" in mime or "rar" in mime:
        return "archive", mime
    if ext in DOCUMENT_EXTS or mime.startswith("text/") or "officedocument" in mime or "opendocument" in mime or "msword" in mime:
        return "document", mime
    return "other", mime


def duration_of(path):
    if not have("ffprobe"):
        return 0.0
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                              "default=noprint_wrappers=1:nokey=1", "--", path],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        return float(out) if out and out != "N/A" else 0.0
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0.0


def free_path(directory, stem, ext):
    """A name in `directory` that doesn't exist yet: stem.ext, stem-1.ext, …"""
    suffix = "." + ext if ext else ""
    candidate = os.path.join(directory, stem + suffix)
    n = 1
    while os.path.exists(candidate):
        candidate = os.path.join(directory, f"{stem}-{n}{suffix}")
        n += 1
    return candidate


def stem_of(path):
    name = os.path.basename(path.rstrip("/"))
    ext = ext_of(name)
    return name[: -len(ext) - 1] if ext and name.lower().endswith("." + ext) else name


def part_path(final):
    """Temporary name next to the result, keeping the extension for tools that need it."""
    global PENDING
    directory, name = os.path.split(final)
    ext = ext_of(name)
    stem = name[: -len(ext) - 1] if ext else name
    PENDING = os.path.join(directory, f".{stem}.part" + ("." + ext if ext else ""))
    return PENDING


def finish(part, final):
    global PENDING
    os.replace(part, final)
    PENDING = None
    return final


def parse_time(text):
    """'90', '1:30' or '00:01:30.5' → seconds."""
    if not text:
        return None
    seconds = 0.0
    for piece in text.strip().split(":"):
        seconds = seconds * 60 + float(piece)
    return seconds


# Commands


def cmd_caps(_args):
    print(json.dumps({tool: shutil.which(tool) for tool in TOOLS}))


def cmd_detect(args):
    result = []
    for path in args.files:
        kind, mime = kind_of(path)
        entry = {"path": path, "name": os.path.basename(path.rstrip("/")), "kind": kind, "mime": mime,
                 "ext": ext_of(path), "size": os.path.getsize(path) if os.path.isfile(path) else 0}
        if kind in ("video", "audio"):
            entry["duration"] = duration_of(path)
        result.append(entry)
    print(json.dumps(result, ensure_ascii=False))


def image_command(src, dst, opts):
    multi_frame = ext_of(src) in ("gif", "webp") and ext_of(dst) in ("gif", "webp")
    cmd = ["magick", src if multi_frame else src + "[0]", "-auto-orient"]
    if opts.resize:
        cmd += ["-resize", opts.resize]
    if opts.strip:
        cmd += ["-strip"]
    target = ext_of(dst)
    if target in ("jpg", "jpeg"):
        cmd += ["-background", "white", "-alpha", "remove", "-alpha", "off"]
    if target == "ico":
        cmd += ["-resize", "256x256>", "-define", "icon:auto-resize=256,128,64,48,32,16"]
    if opts.quality and target in ("jpg", "jpeg", "webp", "avif", "heic"):
        cmd += ["-quality", str(opts.quality)]
    return cmd + [dst]


def convert_image(src, target, out_dir, opts):
    final = free_path(out_dir, stem_of(src), target)
    part = part_path(final)
    code, tail = run(image_command(src, part, opts))
    if code != 0:
        raise RuntimeError(tail[-1] if tail else "ImageMagick failed")
    return finish(part, final)


def video_args(target, opts, duration):
    args = []
    filters = []
    if opts.height:
        filters.append(f"scale=-2:{opts.height}")
    if opts.fps:
        filters.append(f"fps={opts.fps}")
    audio_only = target in AUDIO_TARGETS or target in ("mp3", "opus", "flac", "m4a")
    if target == "gif":
        fps = opts.fps or 12
        scale = f"scale=-2:{opts.height}:flags=lanczos" if opts.height else "scale=640:-1:flags=lanczos"
        return ["-vf", f"fps={fps},{scale},split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer", "-loop", "0", "-an"]
    if audio_only:
        args += ["-vn"]
        codec = {"mp3": ["-c:a", "libmp3lame", "-q:a", "2"], "opus": ["-c:a", "libopus", "-b:a", opts.bitrate or "128k"],
                 "ogg": ["-c:a", "libvorbis", "-q:a", "5"], "flac": ["-c:a", "flac"], "wav": ["-c:a", "pcm_s16le"],
                 "m4a": ["-c:a", "aac", "-b:a", opts.bitrate or "192k"]}[target]
        if opts.bitrate and target == "mp3":
            codec = ["-c:a", "libmp3lame", "-b:a", opts.bitrate]
        return args + codec
    if filters:
        args += ["-vf", ",".join(filters)]
    crf = str(opts.crf or 23)
    if target == "webm":
        args += ["-c:v", "libvpx-vp9", "-row-mt", "1", "-deadline", "good", "-cpu-used", "4"]
        args += ["-crf", str(int(crf) + 9), "-b:v", "0"] if not opts.target_size else []
        args += ["-c:a", "libopus", "-b:a", "128k"]
    else:
        args += ["-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p"]
        args += ["-crf", crf] if not opts.target_size else []
        args += ["-c:a", "aac", "-b:a", "160k"]
        if target == "mp4":
            args += ["-movflags", "+faststart"]
    if opts.target_size and duration > 0:
        audio_kbps = 0 if opts.no_audio else 128
        video_kbps = max(100, int(opts.target_size * 8192 / duration - audio_kbps))
        args += ["-b:v", f"{video_kbps}k", "-maxrate", f"{int(video_kbps * 1.2)}k", "-bufsize", f"{video_kbps * 2}k"]
        if not opts.no_audio:
            args += ["-b:a", f"{audio_kbps}k"]
    if opts.no_audio:
        args += ["-an"]
    return args


def convert_media(src, target, out_dir, opts, index):
    duration = duration_of(src)
    start = parse_time(opts.start)
    end = parse_time(opts.end)
    if start or end:
        duration = max(0.1, (end or duration) - (start or 0))
    final = free_path(out_dir, stem_of(src), target)
    part = part_path(final)
    cmd = ["ffmpeg", "-hide_banner", "-nostdin", "-y"]
    if start:
        cmd += ["-ss", str(start)]
    if end:
        cmd += ["-to", str(end)]
    cmd += ["-i", src] + video_args(target, opts, duration) + ["-progress", "pipe:1", "-nostats", part]
    last = [-1]

    def on_line(line):
        if line.startswith("out_time_us=") or line.startswith("out_time_ms="):
            try:
                microseconds = int(line.split("=", 1)[1])
            except ValueError:
                return
            if duration > 0:
                percent = min(99, int(microseconds / 1e6 / duration * 100))
                if percent != last[0]:
                    last[0] = percent
                    emit(event="progress", index=index, file=src, percent=percent)

    code, tail = run(cmd, on_line)
    if code != 0:
        if os.path.exists(part):
            os.remove(part)
        errors = [line for line in tail if line and "=" not in line[:20]]
        raise RuntimeError(errors[-1] if errors else "ffmpeg failed")
    return finish(part, final)


def convert_document(src, target, out_dir, opts):
    source_ext = ext_of(src)
    final = free_path(out_dir, stem_of(src), target)
    office_formats = {"doc", "docx", "odt", "rtf", "ods", "xls", "xlsx", "odp", "ppt", "pptx", "csv"}
    pandoc_in = {"md", "markdown", "html", "htm", "docx", "odt", "epub", "txt", "tex", "rst", "org"}
    if target == "pdf" and office() and (source_ext in office_formats or source_ext in ("txt", "html", "htm")):
        with tempfile.TemporaryDirectory(prefix="folis-office-") as tmp:
            # A private profile, so a running LibreOffice doesn't block the conversion
            cmd = [office(), f"-env:UserInstallation=file://{tmp}/profile", "--headless", "--convert-to", "pdf",
                   "--outdir", tmp, src]
            code, tail = run(cmd)
            produced = os.path.join(tmp, stem_of(src) + ".pdf")
            if code != 0 or not os.path.exists(produced):
                raise RuntimeError(tail[-1] if tail else "LibreOffice failed")
            shutil.move(produced, final)
            return final
    if target in ("docx", "odt", "pdf") and source_ext in office_formats and office():
        with tempfile.TemporaryDirectory(prefix="folis-office-") as tmp:
            cmd = [office(), f"-env:UserInstallation=file://{tmp}/profile", "--headless", "--convert-to", target,
                   "--outdir", tmp, src]
            code, tail = run(cmd)
            produced = os.path.join(tmp, stem_of(src) + "." + target)
            if code != 0 or not os.path.exists(produced):
                raise RuntimeError(tail[-1] if tail else "LibreOffice failed")
            shutil.move(produced, final)
            return final
    if have("pandoc") and source_ext in pandoc_in:
        part = part_path(final)
        cmd = ["pandoc", src, "-o", part, "--standalone"]
        if target == "md":
            cmd = ["pandoc", src, "-t", "gfm", "-o", part]
        if target == "pdf":
            if not office() and not have("wkhtmltopdf") and not have("pdflatex"):
                raise RuntimeError("PDF needs LibreOffice or a LaTeX engine")
        code, tail = run(cmd)
        if code != 0:
            raise RuntimeError(tail[-1] if tail else "pandoc failed")
        return finish(part, final)
    raise RuntimeError(f"Can't convert .{source_ext} to .{target}: install pandoc or LibreOffice")


def convert_pdf(src, target, out_dir, opts):
    if target in ("png", "jpg"):
        folder = free_path(out_dir, stem_of(src) + "-pages", "")
        os.makedirs(folder)
        resolution = str(opts.dpi or 150)
        code, tail = run(["pdftoppm", "-r", resolution, "-png" if target == "png" else "-jpeg", src,
                          os.path.join(folder, "page")])
        if code != 0:
            raise RuntimeError(tail[-1] if tail else "pdftoppm failed")
        return folder
    if target == "txt":
        final = free_path(out_dir, stem_of(src), "txt")
        code, tail = run(["pdftotext", "-layout", src, final])
        if code != 0:
            raise RuntimeError(tail[-1] if tail else "pdftotext failed")
        return final
    if target == "docx":
        if not office():
            raise RuntimeError("PDF to DOCX needs LibreOffice")
        with tempfile.TemporaryDirectory(prefix="folis-office-") as tmp:
            cmd = [office(), f"-env:UserInstallation=file://{tmp}/profile", "--headless", "--infilter=writer_pdf_import",
                   "--convert-to", "docx", "--outdir", tmp, src]
            code, tail = run(cmd)
            produced = os.path.join(tmp, stem_of(src) + ".docx")
            if code != 0 or not os.path.exists(produced):
                raise RuntimeError(tail[-1] if tail else "LibreOffice failed")
            final = free_path(out_dir, stem_of(src), "docx")
            shutil.move(produced, final)
            return final
    if target == "pdf-compress":
        final = free_path(out_dir, stem_of(src) + "-small", "pdf")
        part = part_path(final)
        code, tail = run(["gs", "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.5", "-dPDFSETTINGS=/ebook", "-dNOPAUSE",
                          "-dQUIET", "-dBATCH", f"-sOutputFile={part}", src])
        if code != 0:
            raise RuntimeError(tail[-1] if tail else "Ghostscript failed")
        return finish(part, final)
    raise RuntimeError(f"Unknown PDF target {target}")


def merge_pdfs(files, out_dir):
    final = free_path(out_dir, stem_of(files[0]) + "-merged", "pdf")
    part = part_path(final)
    if have("qpdf"):
        code, tail = run(["qpdf", "--empty", "--pages", *files, "--", part])
    else:
        code, tail = run(["gs", "-sDEVICE=pdfwrite", "-dNOPAUSE", "-dQUIET", "-dBATCH", f"-sOutputFile={part}", *files])
    if code != 0:
        raise RuntimeError(tail[-1] if tail else "Merging failed")
    return finish(part, final)


def images_to_pdf(files, out_dir, opts):
    final = free_path(out_dir, stem_of(files[0]) + ("-images" if len(files) > 1 else ""), "pdf")
    part = part_path(final)
    cmd = ["magick", *[f + "[0]" for f in files], "-auto-orient"]
    if opts.resize:
        cmd += ["-resize", opts.resize]
    code, tail = run(cmd + [part])
    if code != 0:
        raise RuntimeError(tail[-1] if tail else "ImageMagick failed")
    return finish(part, final)


def extract_archive(src, out_dir):
    folder = free_path(out_dir, stem_of(src), "")
    os.makedirs(folder)
    if have("7z") and not ext_of(src).startswith("tar"):
        code, tail = run(["7z", "x", "-y", f"-o{folder}", src])
    else:
        code, tail = run(["bsdtar", "-xf", src, "-C", folder])
    if code != 0:
        raise RuntimeError(tail[-1] if tail else "Extraction failed")
    return folder


def pack_files(files, target, out_dir, name):
    base = name or (stem_of(files[0]) if len(files) == 1 else "archive")
    final = free_path(out_dir, base, target)
    part = part_path(final)
    parent = os.path.dirname(os.path.abspath(files[0]))
    names = [os.path.relpath(os.path.abspath(f), parent) for f in files]
    if target == "7z":
        code, tail = run(["7z", "a", "-y", part, *names], cwd=parent)
    elif target == "zip":
        if have("7z"):
            code, tail = run(["7z", "a", "-tzip", "-y", part, *names], cwd=parent)
        else:
            code, tail = run(["bsdtar", "-a", "-cf", part, *names], cwd=parent)
    else:
        code, tail = run(["bsdtar", "-a", "-cf", part, *names], cwd=parent)
    if code != 0:
        raise RuntimeError(tail[-1] if tail else "Packing failed")
    return finish(part, final)


def cmd_convert(args):
    files = [os.path.abspath(f) for f in args.files]
    target = args.to

    def out_dir_for(path):
        directory = args.out_dir or os.path.dirname(path)
        os.makedirs(directory, exist_ok=True)
        return directory

    # Conversions that take all files at once
    if target in PACK_TARGETS:
        emit(event="start", index=0, file=files[0])
        try:
            emit(event="done", index=0, file=files[0], output=pack_files(files, target, out_dir_for(files[0]), args.name))
        except Exception as error:  # Reported to the window, the run goes on
            emit(event="error", index=0, file=files[0], message=str(error))
        emit(event="finished")
        return
    if target == "pdf-merge" or (target == "pdf" and args.merge and all(kind_of(f)[0] == "image" for f in files)):
        emit(event="start", index=0, file=files[0])
        try:
            output = merge_pdfs(files, out_dir_for(files[0])) if target == "pdf-merge" else images_to_pdf(files, out_dir_for(files[0]), args)
            emit(event="done", index=0, file=files[0], output=output)
        except Exception as error:
            emit(event="error", index=0, file=files[0], message=str(error))
        emit(event="finished")
        return

    for index, src in enumerate(files):
        emit(event="start", index=index, file=src)
        try:
            kind, _mime = kind_of(src)
            allowed = {"image": IMAGE_TARGETS, "video": VIDEO_TARGETS, "audio": AUDIO_TARGETS, "pdf": PDF_TARGETS,
                       "document": DOCUMENT_TARGETS, "archive": ARCHIVE_TARGETS}.get(kind, [])
            if target not in allowed:
                raise RuntimeError(f"Can't turn {'an' if kind[0] in 'aeiou' else 'a'} {kind} into .{target}")
            out_dir = out_dir_for(src)
            if kind == "image":
                output = convert_image(src, target, out_dir, args)
            elif kind in ("video", "audio"):
                output = convert_media(src, target, out_dir, args, index)
            elif kind == "pdf":
                output = convert_pdf(src, target, out_dir, args) if target != "pdf" else src
            elif kind == "document":
                output = convert_document(src, target, out_dir, args)
            elif kind == "archive" and target == "extract":
                output = extract_archive(src, out_dir)
            else:
                raise RuntimeError(f"Can't turn {'an' if kind[0] in 'aeiou' else 'a'} {kind} into .{target}")
            emit(event="done", index=index, file=src, output=output)
        except Exception as error:
            emit(event="error", index=index, file=src, message=str(error))
    emit(event="finished")


def cmd_download(args):
    if not have("yt-dlp"):
        emit(event="error", message="yt-dlp is not installed")
        return
    out_dir = args.out_dir or os.path.join(os.path.expanduser("~"), "Videos", "Downloads")
    os.makedirs(out_dir, exist_ok=True)
    cmd = ["yt-dlp", "--newline", "--no-playlist" if not args.playlist else "--yes-playlist",
           "--progress-template", "download:PROGRESS %(progress._percent_str)s %(progress._speed_str)s %(progress._eta_str)s",
           "-o", os.path.join(out_dir, "%(title).150B [%(id)s].%(ext)s"), "--print", "after_move:filepath"]
    if args.mode == "audio":
        cmd += ["-x", "--audio-format", args.audio_format or "mp3", "--audio-quality", "0"]
    else:
        height = args.quality or "1080"
        cmd += ["-f", f"bv*[height<={height}]+ba/b[height<={height}]/b", "--merge-output-format", "mp4"]
    if args.subs:
        cmd += ["--write-subs", "--write-auto-subs", "--sub-langs", "ru.*,en.*", "--embed-subs"]
    if args.proxy:
        cmd += ["--proxy", args.proxy]
    cmd += ["--", args.url]
    emit(event="start", file=args.url)
    outputs = []

    def on_line(line):
        if line.startswith("PROGRESS"):
            parts = line.split()
            try:
                percent = float(parts[1].rstrip("%"))
            except (IndexError, ValueError):
                return
            emit(event="progress", file=args.url, percent=int(percent),
                 speed=parts[2] if len(parts) > 2 else "", eta=parts[3] if len(parts) > 3 else "")
        elif line.startswith("/") and os.path.exists(line):
            outputs.append(line)
        elif line.startswith("[download] Destination:") or line.startswith("[Merger]"):
            emit(event="status", file=args.url, message=line)

    code, tail = run(cmd, on_line)
    if code != 0:
        errors = [line for line in tail if "ERROR" in line]
        emit(event="error", file=args.url, message=(errors[-1] if errors else (tail[-1] if tail else "yt-dlp failed")))
    else:
        emit(event="done", file=args.url, output=outputs[-1] if outputs else out_dir)
    emit(event="finished")


def cmd_info(args):
    """Title and duration of a link, for the download page."""
    code, tail = run(["yt-dlp", "--no-playlist", "--skip-download", "--print", "%(title)s\t%(duration_string)s\t%(uploader)s",
                      *(["--proxy", args.proxy] if args.proxy else []), "--", args.url])
    if code != 0:
        errors = [line for line in tail if "ERROR" in line]
        emit(event="error", message=errors[-1] if errors else "yt-dlp failed")
        return
    title, duration, uploader = (tail[-1].split("\t") + ["", "", ""])[:3]
    emit(event="info", title=title, duration=duration, uploader=uploader)


def cmd_qr_encode(args):
    final = args.out or os.path.join(tempfile.gettempdir(), "folis-qr.png")
    code, tail = run(["qrencode", "-o", final, "-s", str(args.size or 10), "-m", "2", "-l", "M", "--", args.text])
    if code != 0:
        emit(event="error", message=tail[-1] if tail else "qrencode failed")
        return
    emit(event="done", output=final)


def cmd_qr_scan(args):
    code, tail = run(["zbarimg", "--quiet", "--raw", "--", args.file])
    results = [line for line in tail if line.strip()]
    if code != 0 or not results:
        emit(event="error", message="No QR code found")
        return
    emit(event="done", output="\n".join(results))


def tesseract_languages():
    try:
        out = subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    return [line.strip() for line in out.splitlines()[1:] if line.strip() and line.strip() != "osd"]


def cmd_ocr(args):
    available = tesseract_languages()
    wanted = [lang for lang in (args.lang or "eng+rus").split("+") if lang in available] or available[:1] or ["eng"]
    lang = "+".join(wanted)
    src = os.path.abspath(args.file)
    pages = [src]
    tmp = None
    if kind_of(src)[0] == "pdf":
        tmp = tempfile.mkdtemp(prefix="folis-ocr-")
        code, tail = run(["pdftoppm", "-r", "300", "-png", src, os.path.join(tmp, "page")])
        if code != 0:
            emit(event="error", message=tail[-1] if tail else "pdftoppm failed")
            return
        pages = sorted(os.path.join(tmp, f) for f in os.listdir(tmp))
    if args.pdf:
        final = free_path(os.path.dirname(src), stem_of(src) + "-searchable", "")
        if len(pages) == 1:
            code, tail = run(["tesseract", pages[0], final, "-l", lang, "pdf"])
        else:
            listing = os.path.join(tmp, "pages.txt")
            with open(listing, "w") as f:
                f.write("\n".join(pages))
            code, tail = run(["tesseract", listing, final, "-l", lang, "pdf"])
        if code != 0:
            emit(event="error", message=tail[-1] if tail else "tesseract failed")
            return
        emit(event="done", output=final + ".pdf", language=lang)
        return
    texts = []
    for index, page in enumerate(pages):
        emit(event="progress", percent=int(index / len(pages) * 100))
        result = subprocess.run(["tesseract", page, "-", "-l", lang], capture_output=True, text=True)
        texts.append(result.stdout.strip())
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    emit(event="done", text="\n\n".join(t for t in texts if t), language=lang)


def cmd_palette(args):
    count = args.colors or 8
    code, tail = run(["magick", args.file + "[0]", "-resize", "200x200", "+dither", "-colors", str(count),
                      "-depth", "8", "-format", "%c", "histogram:info:-"])
    if code != 0:
        emit(event="error", message=tail[-1] if tail else "ImageMagick failed")
        return
    # Lines look like "  1234: (r,g,b) #RRGGBB srgb(...)"; the most used colors go first
    found = [(int(m.group(1)), m.group(2).upper()) for m in
             (re.match(r"\s*(\d+):.*?(#[0-9A-Fa-f]{6})", line) for line in tail) if m]
    emit(event="done", colors=[color for _, color in sorted(found, reverse=True)][:count])


def main():
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("caps").set_defaults(func=cmd_caps)

    detect = sub.add_parser("detect")
    detect.add_argument("files", nargs="+")
    detect.set_defaults(func=cmd_detect)

    convert = sub.add_parser("convert")
    convert.add_argument("--to", required=True)
    convert.add_argument("--out-dir")
    convert.add_argument("--quality", type=int)
    convert.add_argument("--resize")
    convert.add_argument("--strip", action="store_true")
    convert.add_argument("--crf", type=int)
    convert.add_argument("--height", type=int)
    convert.add_argument("--fps", type=int)
    convert.add_argument("--start")
    convert.add_argument("--end")
    convert.add_argument("--target-size", type=float, help="megabytes")
    convert.add_argument("--no-audio", action="store_true")
    convert.add_argument("--bitrate")
    convert.add_argument("--dpi", type=int)
    convert.add_argument("--merge", action="store_true")
    convert.add_argument("--name")
    convert.add_argument("files", nargs="+")
    convert.set_defaults(func=cmd_convert)

    download = sub.add_parser("download")
    download.add_argument("url")
    download.add_argument("--mode", choices=["video", "audio"], default="video")
    download.add_argument("--quality")
    download.add_argument("--audio-format")
    download.add_argument("--subs", action="store_true")
    download.add_argument("--playlist", action="store_true")
    download.add_argument("--proxy")
    download.add_argument("--out-dir")
    download.set_defaults(func=cmd_download)

    info = sub.add_parser("info")
    info.add_argument("url")
    info.add_argument("--proxy")
    info.set_defaults(func=cmd_info)

    qr_encode = sub.add_parser("qr-encode")
    qr_encode.add_argument("text")
    qr_encode.add_argument("--out")
    qr_encode.add_argument("--size", type=int)
    qr_encode.set_defaults(func=cmd_qr_encode)

    qr_scan = sub.add_parser("qr-scan")
    qr_scan.add_argument("file")
    qr_scan.set_defaults(func=cmd_qr_scan)

    ocr = sub.add_parser("ocr")
    ocr.add_argument("file")
    ocr.add_argument("--lang")
    ocr.add_argument("--pdf", action="store_true")
    ocr.set_defaults(func=cmd_ocr)

    palette = sub.add_parser("palette")
    palette.add_argument("file")
    palette.add_argument("--colors", type=int)
    palette.set_defaults(func=cmd_palette)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

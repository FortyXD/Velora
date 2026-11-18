//! Demand-driven foreign-window previews for Alt+Tab, the taskbar and dock.
use crate::subprocess::{interruptible, ChildGroup};
use anyhow::{bail, ensure, Context, Result};
use fast_image_resize::{FilterType, ResizeAlg, ResizeOptions, Resizer};
use image::{DynamicImage, ImageFormat, ImageReader};
use md5::{Digest, Md5};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    fs,
    io::Cursor,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    process::{ExitCode, Stdio},
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, BufReader},
    process::Command,
    task::{AbortHandle, JoinSet},
    time::Instant,
};

#[derive(Clone, PartialEq)]
struct Spec {
    width: u32,
    height: u32,
    source: (u32, u32),
    live: bool,
    cursor: bool,
    generation: i64,
    refresh: i64,
}

impl Spec {
    fn read(v: &Value) -> Self {
        let number =
            |k: &str, default, min, max| v[k].as_i64().unwrap_or(default).clamp(min, max) as u32;
        Self {
            width: number("width", 280, 32, 1024),
            height: number("height", 180, 32, 768),
            source: (
                number("sourceWidth", 0, 0, 32768),
                number("sourceHeight", 0, 0, 32768),
            ),
            live: v["live"].as_bool().unwrap_or(true),
            cursor: v["cursor"].as_bool().unwrap_or(false),
            refresh: v["refresh"].as_i64().unwrap_or(0),
            generation: v["generation"].as_i64().unwrap_or(0),
        }
    }
}

type Hash = [u8; 16];
#[derive(Clone, Default)]
struct Cache {
    source: Option<(f64, f64)>,
    raw: Option<Hash>,
    pixels: Option<(u32, u32, Hash)>,
}

struct Frame {
    cache: Cache,
    image: Option<Vec<u8>>,
    size: (u32, u32),
}

fn thumbnail(bytes: Vec<u8>, spec: &Spec, mut cache: Cache, scale: f64) -> Result<Frame> {
    let raw = Md5::digest(&bytes).into();
    if cache.raw == Some(raw) {
        return Ok(Frame {
            cache,
            image: None,
            size: (0, 0),
        });
    }
    let (w, h) =
        ImageReader::with_format(Cursor::new(&bytes), ImageFormat::Png).into_dimensions()?;
    ensure!(
        w > 0 && h > 0 && u64::from(w) * u64::from(h) <= 32_000_000,
        "capture exceeds the image size limit"
    );
    let source = match cache.source {
        Some((x, y))
            if (w as f64 - x * scale).abs() <= 2. && (h as f64 - y * scale).abs() <= 2. =>
        {
            (x, y)
        }
        _ => (w as f64 / scale, h as f64 / scale),
    };
    let ratio = 1f64
        .min(spec.width as f64 / source.0)
        .min(spec.height as f64 / source.1);
    let size = (
        (source.0 * ratio).round_ties_even().max(1.) as u32,
        (source.1 * ratio).round_ties_even().max(1.) as u32,
    );
    let image = image::load_from_memory_with_format(&bytes, ImageFormat::Png)?.into_rgba8();
    let image = if (w, h) == size {
        image
    } else {
        let image = DynamicImage::ImageRgba8(image);
        let mut dest = DynamicImage::new_rgba8(size.0, size.1);
        Resizer::new().resize(
            &image,
            &mut dest,
            &ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Lanczos3)),
        )?;
        dest.into_rgba8()
    };
    let pixels = (size.0, size.1, Md5::digest(image.as_raw()).into());
    let png = if cache.pixels == Some(pixels) {
        None
    } else {
        let mut data = Vec::new();
        let mut enc = png::Encoder::new(&mut data, size.0, size.1);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        enc.set_compression(png::Compression::Fast);
        enc.write_header()?.write_image_data(image.as_raw())?;
        Some(data)
    };
    cache.source = Some(source);
    cache.raw = Some(raw);
    cache.pixels = Some(pixels);
    Ok(Frame {
        cache,
        image: png,
        size,
    })
}

async fn capture(id: &str, spec: Spec, mut cache: Cache) -> Result<Frame> {
    if cache.source.is_none() && spec.source.0 > 0 && spec.source.1 > 0 {
        cache.source = Some((spec.source.0 as f64, spec.source.1 as f64));
    }
    let scale = cache.source.map_or(0.5, |(x, y)| {
        (f64::from(spec.width + 2) / x)
            .min(f64::from(spec.height + 2) / y)
            .clamp(0.001, 1.)
    });
    let mut cmd = Command::new("grim");
    cmd.args(["-T", id, "-s", &format!("{scale:.8}"), "-l", "0"]);
    if spec.cursor {
        cmd.arg("-c");
    }
    let mut child = ChildGroup::spawn(
        cmd.arg("-")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null()),
    )?;
    let mut bytes = Vec::new();
    const LIMIT: u64 = 128 << 20;
    tokio::time::timeout(Duration::from_secs(3), async {
        child
            .0
            .stdout
            .take()
            .unwrap()
            .take(LIMIT + 1)
            .read_to_end(&mut bytes)
            .await?;
        ensure!(
            bytes.len() as u64 <= LIMIT,
            "capture exceeds the image size limit"
        );
        let status = child.0.wait().await?;
        ensure!(status.success(), "grim failed ({status})");
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("capture timed out")??;
    tokio::task::spawn_blocking(move || thumbnail(bytes, &spec, cache, scale)).await?
}

struct Window {
    spec: Spec,
    priority: i64,
    order: usize,
    serial: u64,
    revision: u64,
    files: [PathBuf; 2],
    cache: Cache,
    active: Option<AbortHandle>,
    due: Option<Instant>,
    unchanged: u32,
    failures: u32,
}

impl Drop for Window {
    fn drop(&mut self) {
        if let Some(task) = self.active.take() {
            task.abort();
        }
        for f in &self.files {
            let _ = fs::remove_file(f);
        }
    }
}

struct Broker {
    windows: BTreeMap<String, Window>,
    serial: u64,
    tokens: f64,
    refill: Instant,
    last: Option<Instant>,
}
type Captures = JoinSet<(String, u64, Instant, Result<Frame>)>;

impl Broker {
    fn set(&mut self, list: &[Value], dir: &Path) {
        let mut old = std::mem::take(&mut self.windows);
        for (order, v) in list.iter().take(64).enumerate() {
            let id = v["id"].as_str().unwrap_or("").to_ascii_lowercase();
            if id.is_empty() || id.len() > 16 || !id.bytes().all(|b| b.is_ascii_hexdigit()) {
                continue;
            }
            let spec = Spec::read(v);
            let priority = v["priority"].as_i64().unwrap_or(0);
            let previous = old.remove(&id);
            let mut w = match previous {
                Some(w) if w.spec == spec => w,
                other => {
                    self.serial += 1;
                    let files =
                        [0, 1].map(|slot| dir.join(format!("{id}-{}-{slot}.png", self.serial)));
                    let cache = Cache {
                        source: other.and_then(|w| w.cache.source),
                        ..Cache::default()
                    };
                    Window {
                        spec,
                        priority,
                        order,
                        serial: self.serial,
                        revision: 0,
                        files,
                        cache,
                        active: None,
                        due: Some(Instant::now()),
                        unchanged: 0,
                        failures: 0,
                    }
                }
            };
            w.priority = priority;
            w.order = order;
            self.windows.insert(id, w);
        }
    }

    /// Start at most two captures. Sleep until input, completion or the next eligible frame.
    fn schedule(&mut self, tasks: &mut Captures) -> Option<Instant> {
        while tasks.len() < 2 {
            let now = Instant::now();
            self.tokens = (self.tokens + (now - self.refill).as_secs_f64() * 16.).min(4.);
            self.refill = now;
            let next_due = self.windows.values().filter_map(|w| w.due).min()?;
            if next_due > now {
                return Some(next_due);
            }
            let (id, w) = self
                .windows
                .iter_mut()
                .filter(|(_, w)| w.due.is_some_and(|t| t <= now))
                .min_by_key(|(_, w)| {
                    (
                        w.revision > 0,
                        std::cmp::Reverse(if w.revision == 0 { w.priority } else { 0 }),
                        if w.revision == 0 { None } else { w.due },
                        w.order,
                    )
                })
                .unwrap();
            let mut eligible = now + Duration::from_secs_f64(((1. - self.tokens) / 16.).max(0.));
            if w.revision > 0 {
                if let Some(last) = self.last {
                    eligible = eligible.max(last + Duration::from_micros(62500));
                }
            }
            if eligible > now {
                return Some(eligible);
            }
            self.tokens -= 1.;
            self.last = Some(now);
            let (id, spec, serial, cache) = (id.clone(), w.spec.clone(), w.serial, w.cache.clone());
            w.due = None;
            w.active = Some(tasks.spawn(async move {
                let result = capture(&id, spec, cache).await;
                (id, serial, now, result)
            }));
        }
        None
    }

    fn finish(&mut self, id: String, serial: u64, started: Instant, result: Result<Frame>) {
        let Some(w) = self.windows.get_mut(&id).filter(|w| w.serial == serial) else {
            return;
        };
        w.active = None;
        let published = result.and_then(|frame| {
            let changed = frame.image.is_some();
            if let Some(png) = frame.image {
                let path = &w.files[w.revision as usize % 2];
                let mut tmp = tempfile::NamedTempFile::new_in(path.parent().unwrap())?;
                std::io::Write::write_all(&mut tmp, &png)?;
                tmp.persist(path)?;
                w.revision += 1;
                println!("{}",json!({"event":"frame","id":id,"generation":w.spec.generation,"revision":format!("{serial}-{}",w.revision),
                    "width":frame.size.0,"height":frame.size.1,"path":path}));
            }
            w.cache = frame.cache;
            Ok(changed)
        });
        let period = match published {
            Ok(changed) => {
                w.failures = 0;
                if !w.spec.live {
                    return;
                }
                w.unchanged = if changed { 0 } else { (w.unchanged + 1).min(3) };
                Duration::from_millis(125 * (1 + w.unchanged as u64))
            }
            Err(error) => {
                if w.failures == 0 {
                    println!(
                        "{}",
                        json!({"event":"error","id":id,"message":error.to_string()})
                    );
                }
                w.failures = (w.failures + 1).min(5);
                Duration::from_secs(w.failures as u64)
            }
        };
        w.due = Some(started + period);
    }
}

pub fn run() -> Result<ExitCode> {
    let runtime =
        PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR").context("missing XDG_RUNTIME_DIR")?);
    let meta = runtime.metadata()?;
    ensure!(
        meta.is_dir() && meta.uid() == unsafe { libc::getuid() } && meta.mode() & 0o077 == 0,
        "A private XDG_RUNTIME_DIR is required"
    );
    let private = tempfile::Builder::new()
        .prefix("velora-previews-")
        .tempdir_in(runtime)?;
    interruptible(
        async {
            let mut broker = Broker {
                windows: BTreeMap::new(),
                serial: 0,
                tokens: 4.,
                refill: Instant::now(),
                last: None,
            };
            let mut tasks = JoinSet::new();
            let mut input = BufReader::new(tokio::io::stdin());
            let mut msg = Vec::new();
            println!("{}", json!({"event":"ready"}));
            loop {
                let next = broker.schedule(&mut tasks);
                tokio::select! {
                    biased;
                    read = async {
                        let remaining = 65537 - msg.len();
                        (&mut input).take(remaining as u64).read_until(b'\n', &mut msg).await
                    } => {
                        if read? == 0 && msg.is_empty() { break; }
                        if msg.len()>65536 { bail!("preview message too long"); }
                        match serde_json::from_slice::<Value>(&msg) {
                            Ok(v) if v["op"]=="set" => if let Some(list)=v["windows"].as_array() {broker.set(list, private.path());},
                            Err(e) => println!("{}",json!({"event":"error","message":e.to_string()})),
                            _ => {}
                        }
                        msg.clear();
                    }
                    Some(result) = tasks.join_next(), if !tasks.is_empty() => if let Ok((id,serial,start,frame))=result {broker.finish(id,serial,start,frame);},
                    _ = async { tokio::time::sleep_until(next.unwrap()).await }, if next.is_some() => {}
                }
            }
            Ok(ExitCode::SUCCESS)
        },
        || {},
    )
}

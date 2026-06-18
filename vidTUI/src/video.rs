use crossterm::{
    cursor,
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyModifiers},
    execute,
    style::{Color, ResetColor, SetForegroundColor},
    terminal::{
        disable_raw_mode, enable_raw_mode, size as term_size,
        Clear, ClearType, EnterAlternateScreen, LeaveAlternateScreen,
    },
};
use fantoccini::ClientBuilder;
use image::DynamicImage;
use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Rect},
    style::{Style, Stylize},
    widgets::{Block, BorderType, Borders, Paragraph},
    Terminal,
};
use std::{
    io::{self, Write},
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, AtomicU16, AtomicU64, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};
use tokio::{
    sync::watch,
    time::sleep,
};

const UI_ROWS_RESERVED: u16 = 1;
const FRAME_INTERVAL_MS: u64 = 50;
const GECKODRIVER_PORT: u16 = 4444;
const JPEG_QUALITY: f64 = 0.35;
const SEEK_STEP: f64 = 10.0;

// ─── Spinner ────────────────────────────────────────────────────────

struct Spinner {
    chars: [char; 4],
    idx: usize,
}

impl Spinner {
    fn new() -> Self {
        Self { chars: ['-', '\\', '|', '/'], idx: 0 }
    }
    fn next(&mut self) -> char {
        let c = self.chars[self.idx];
        self.idx = (self.idx + 1) % self.chars.len();
        c
    }
}

// ─── Captura via Canvas JS ──────────────────────────────────────────

fn build_capture_js() -> String {
    format!(
        r#"
const w = arguments[0];
const h = arguments[1];
let video = document.querySelector('video');
if (!video) {{
    const p = document.querySelector('[data-media-player]');
    if (p && p.shadowRoot) {{
        video = p.shadowRoot.querySelector('video');
    }}
}}
if (video && video.readyState >= 2 && video.videoWidth > 0) {{
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    const ctx = c.getContext('2d');
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(video, 0, 0, w, h);
    return c.toDataURL('image/jpeg', {});
}}
return null;
"#,
        JPEG_QUALITY
    )
}

fn parse_data_url(data_url: &str) -> Option<Vec<u8>> {
    let stripped = data_url.split(',').nth(1)?;
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.decode(stripped).ok()
}

// ─── Half-block ANSI (con fix para negros) ──────────────────────────

fn to_halfblocks(img: &DynamicImage, cols: u16, rows: u16) -> String {
    let target_w = cols as u32;
    let target_h = rows as u32 * 2;

    let rgb = if img.width() == target_w && img.height() == target_h {
        img.to_rgb8()
    } else {
        img.resize_exact(target_w, target_h, image::imageops::FilterType::Triangle)
            .to_rgb8()
    };

    let mut out = String::with_capacity(cols as usize * rows as usize * 40);
    for row in 0..rows {
        let y0 = row as u32 * 2;
        let y1 = y0 + 1;
        for x in 0..cols as u32 {
            let t = rgb.get_pixel(x, y0);
            let b = rgb.get_pixel(x, y1);
            let clamp = |c: u8| if c == 0 { 1 } else { c };
            out.push_str(&format!(
                "\x1b[38;2;{};{};{}m\x1b[48;2;{};{};{}m▀",
                clamp(t[0]), clamp(t[1]), clamp(t[2]),
                clamp(b[0]), clamp(b[1]), clamp(b[2]),
            ));
        }
        out.push_str("\x1b[0m\r\n");
    }
    out
}

// ─── Small font (Kitty optimized) ─────────────────────────────────

fn try_set_small_font() {
    let term = std::env::var("TERM").unwrap_or_default();
    if term.contains("kitty") {
        let _ = write!(io::stdout(), "\x1b[22t");
        for _ in 0..10 {
            let _ = write!(io::stdout(), "\x1b[2t");
        }
        let _ = io::stdout().flush();
    } else if term.contains("xterm") || term.contains("alacritty") || term.contains("ghostty") {
        let _ = write!(io::stdout(), "\x1b]50;{}\x07", "xft:Monospace:size=7");
        for _ in 0..4 {
            let _ = write!(io::stdout(), "\x1b[2t");
        }
        let _ = io::stdout().flush();
    }
}

fn try_restore_font() {
    let _ = write!(io::stdout(), "\x1b[23t");
    let _ = io::stdout().flush();
}

// ─── Loading screen (ratatui) ──────────────────────────────────────

fn draw_loading_ratatui(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    spinner: char,
    msg: &str,
) -> io::Result<()> {
    terminal.draw(|f| {
        let area = f.size();

        let block = Block::default()
            .title(" VidTUI ")
            .title_alignment(Alignment::Center)
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(Style::new().cyan());

        let inner = block.inner(area);

        let text = format!("  {}  {}", spinner, msg);
        let text_y = inner.y + inner.height.saturating_sub(3) / 2;

        f.render_widget(block, area);

        let text_widget = Paragraph::new(text)
            .alignment(Alignment::Center)
            .white();
        f.render_widget(text_widget, Rect::new(inner.x, text_y, inner.width, 1));

        let hint = Paragraph::new("Preparing player...")
            .alignment(Alignment::Center)
            .dark_gray();
        f.render_widget(hint, Rect::new(inner.x, inner.y + inner.height.saturating_sub(2), inner.width, 1));
    })?;
    Ok(())
}

// ─── Formatear tiempo ───────────────────────────────────────────────

fn fmt_time(secs: f64) -> String {
    if secs.is_nan() || secs.is_infinite() || secs <= 0.0 {
        return "00:00".to_string();
    }
    let total = secs as u64;
    let h = total / 3600;
    let m = (total % 3600) / 60;
    let s = total % 60;
    if h > 0 {
        format!("{:02}:{:02}:{:02}", h, m, s)
    } else {
        format!("{:02}:{:02}", m, s)
    }
}

// ─── Minimal UI (play/pause + progress bar + time) ─────────────────

fn draw_ui(
    stdout: &mut io::Stdout,
    total_rows: u16,
    cols: u16,
    paused: bool,
    current_time: f64,
    duration: f64,
) -> io::Result<()> {
    let ui_y = total_rows.saturating_sub(UI_ROWS_RESERVED);
    execute!(stdout, cursor::MoveTo(0, ui_y), Clear(ClearType::FromCursorDown))?;

    let icon = if paused { ">" } else { "||" };
    let time_str = format!("{}/{}", fmt_time(current_time), fmt_time(duration));
    let prefix = format!("{} ", icon);
    let suffix = format!(" {}", time_str);

    let bar_w = (cols as usize).saturating_sub(prefix.len() + suffix.len());
    let pos = if duration > 0.0 {
        ((current_time / duration) * bar_w as f64).round() as usize
    } else {
        0
    };

    write!(stdout, "{}", prefix)?;
    execute!(stdout, SetForegroundColor(Color::Cyan))?;
    write!(stdout, "{}", "=".repeat(pos.min(bar_w)))?;
    if pos < bar_w {
        write!(stdout, "#")?;
    }
    execute!(stdout, SetForegroundColor(Color::DarkGrey))?;
    write!(stdout, "{}", "=".repeat(bar_w.saturating_sub(pos + 1)))?;
    execute!(stdout, ResetColor)?;
    write!(stdout, "{}", suffix)?;

    stdout.flush()
}

// ─── Auto-download geckodriver ─────────────────────────────────────

pub fn geckodriver_cache_path() -> PathBuf {
    dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("vidtui")
        .join(format!("geckodriver-{}", GECKODRIVER_VERSION))
        .join("geckodriver")
}

const GECKODRIVER_VERSION: &str = "0.36.0";
const GECKODRIVER_URL: &str = "https://github.com/mozilla/geckodriver/releases/download/v0.36.0/geckodriver-v0.36.0-linux64.tar.gz";

pub async fn resolve_geckodriver() -> anyhow::Result<PathBuf> {
    if Command::new("which")
        .arg("geckodriver")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return Ok(PathBuf::from("geckodriver"));
    }

    let cache_bin = geckodriver_cache_path();
    if cache_bin.exists() {
        eprintln!("[+] geckodriver found in cache: {}", cache_bin.display());
        return Ok(cache_bin);
    }

    eprintln!("[v] Downloading geckodriver v{}...", GECKODRIVER_VERSION);
    download_geckodriver(&cache_bin).await?;
    Ok(cache_bin)
}

async fn download_geckodriver(dest: &PathBuf) -> anyhow::Result<()> {
    use tokio::io::AsyncWriteExt;

    let tar_path = dest.parent().unwrap().join("geckodriver.tar.gz");
    tokio::fs::create_dir_all(dest.parent().unwrap()).await?;

    let client = reqwest::Client::new();
    let mut response = client.get(GECKODRIVER_URL).send().await?;
    let total = response.content_length().unwrap_or(0);
    let mut file = tokio::fs::File::create(&tar_path).await?;
    let mut downloaded: u64 = 0;
    let mut last_print = Instant::now();

    while let Some(chunk) = response.chunk().await? {
        file.write_all(&chunk).await?;
        downloaded += chunk.len() as u64;
        if last_print.elapsed() >= Duration::from_millis(300) {
            if total > 0 {
                eprint!("\r  {}% ({}/{}MB)", downloaded * 100 / total,
                    downloaded / 1_048_576, total / 1_048_576);
            }
            let _ = io::stderr().flush();
            last_print = Instant::now();
        }
    }
    file.flush().await?;
    eprintln!("\r  Download complete.          ");

    let tar_path_clone = tar_path.clone();
    let extract_dir = dest.parent().unwrap().to_path_buf();
    tokio::task::spawn_blocking(move || -> anyhow::Result<()> {
        let file = std::fs::File::open(&tar_path_clone)?;
        let gz = flate2::read::GzDecoder::new(file);
        let mut archive = tar::Archive::new(gz);
        archive.unpack(&extract_dir)?;
        std::fs::remove_file(&tar_path_clone)?;
        Ok(())
    }).await??;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(dest)?.permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(dest, perms)?;
    }

    eprintln!("[+] geckodriver ready: {}", dest.display());
    Ok(())
}

pub fn resolve_firefox() -> anyhow::Result<PathBuf> {
    for bin in &["firefox", "firefox-esr", "iceweasel"] {
        if Command::new("which")
            .arg(bin)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            return Ok(PathBuf::from(bin));
        }
    }
    anyhow::bail!("Firefox not found. Install with: sudo apt install firefox")
}

// ─── JavaScript to hide web player UI ──────────────────────────────

const HIDE_UI_JS: &str = r#"
(function() {
    let s = document.createElement('style');
    s.textContent = `
        media-controller, media-control-bar, [class*="control"],
        [class*="overlay"], [class*="chrome"], [id*="control"],
        .vp-controls, .vjs-control-bar, .plyr__controls { display: none !important; }
        video { pointer-events: none !important; }
    `;
    document.head.appendChild(s);
    for (let v of document.querySelectorAll('video')) { v.controls = false; }
    for (let el of document.querySelectorAll('media-controller, [data-media-player]')) {
        if (el && el.shadowRoot) {
            let st = document.createElement('style');
            st.textContent = `:host > :not(video, #video, [slot="media"], slot) { display: none !important; }`;
            el.shadowRoot.appendChild(st);
        }
    }
})();
"#;

// ─── JavaScript to unmute audio ────────────────────────────────────

const UNMUTE_JS: &str = r#"
let v = document.querySelector('video');
if (!v) {
    let p = document.querySelector('[data-media-player]');
    if (p && p.shadowRoot) v = p.shadowRoot.querySelector('video');
}
if (v) {
    v.muted = false;
    v.volume = 1.0;
    if (v.paused) v.play();
}
"#;

// ─── Play function ──────────────────────────────────────────────────

pub async fn play_video(url: &str, geckodriver_path: &PathBuf, firefox_path: &PathBuf) -> anyhow::Result<()> {
    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen, EnableMouseCapture, cursor::Hide, Clear(ClearType::All))?;
    try_set_small_font();

    let (total_cols, total_rows) = term_size()?;
    let mut spinner = Spinner::new();

    // ── Ratatui loading phase ───────────────────────────────
    let backend = CrosstermBackend::new(io::stdout());
    let mut terminal = Terminal::new(backend)?;

    let mut gecko_proc: Child = Command::new(geckodriver_path)
        .args(["--port", &GECKODRIVER_PORT.to_string()])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;

    sleep(Duration::from_millis(800)).await;

    let load = |terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, sp: &mut Spinner, msg: &str| {
        let c = sp.next();
        let _ = draw_loading_ratatui(terminal, c, msg);
    };

    load(&mut terminal, &mut spinner, "Connecting Firefox...");

    let caps = serde_json::json!({
        "moz:firefoxOptions": {
            "binary": firefox_path.to_str().unwrap(),
            "args": ["-headless"],
            "prefs": {
                "media.autoplay.default": 0,
                "media.autoplay.blocking_policy": 0,
                "media.autoplay.allow-muted": true,
                    "media.volume_scale": "1.0",
                "dom.webdriver.enabled": false,
                "useAutomationExtension": false,
                "media.hardware-video-decoding.enabled": false,
                "gfx.webrender.all": false,
                "layers.acceleration.disabled": true,
            },
            "log": { "level": "error" }
        },
        "browserName": "firefox",
    });

    let client = match ClientBuilder::rustls()
        .map_err(|e| anyhow::anyhow!("ClientBuilder error: {}", e))?
        .capabilities(serde_json::from_value(caps)?)
        .connect(&format!("http://localhost:{}", GECKODRIVER_PORT))
        .await
    {
        Ok(c) => c,
        Err(e) => {
            gecko_proc.kill().ok();
            let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture, cursor::Show);
            let _ = disable_raw_mode();
            anyhow::bail!("Could not connect to Firefox: {}. Is Firefox installed?", e);
        }
    };

    client.set_window_size(640, 480).await?;

    load(&mut terminal, &mut spinner, "Navigating to page...");
    client.goto(url).await?;

    load(&mut terminal, &mut spinner, "Waiting for player...");
    let deadline = Instant::now() + Duration::from_secs(30);
    let video_found = loop {
        let ready: i64 = client
            .execute(
                r#"
                let v = document.querySelector('video');
                if (!v) {
                    let p = document.querySelector('[data-media-player]');
                    if (p && p.shadowRoot) v = p.shadowRoot.querySelector('video');
                }
                return v ? v.readyState : -1;
                "#,
                vec![],
            )
            .await
            .ok()
            .and_then(|v| v.as_i64())
            .unwrap_or(-1);

        if ready >= 2 || Instant::now() > deadline {
            break ready >= 2;
        }
        let c = spinner.next();
        let _ = draw_loading_ratatui(&mut terminal, c, "Waiting for player...");
        sleep(Duration::from_millis(500)).await;
    };

    load(&mut terminal, &mut spinner, "Hiding player UI...");
    client.execute(HIDE_UI_JS, vec![]).await.ok();
    sleep(Duration::from_millis(200)).await;
    client.execute(HIDE_UI_JS, vec![]).await.ok();

    load(&mut terminal, &mut spinner, "Starting playback...");
    for _ in 0..3 {
        client
            .execute("document.elementFromPoint(320, 240)?.click()", vec![])
            .await
            .ok();
        sleep(Duration::from_millis(200)).await;
    }

    load(&mut terminal, &mut spinner, "Enabling audio...");
    client.execute(UNMUTE_JS, vec![]).await.ok();
    sleep(Duration::from_millis(300)).await;
    client.execute(UNMUTE_JS, vec![]).await.ok();
    client.execute(HIDE_UI_JS, vec![]).await.ok();

    drop(terminal);

    // ── Shared state ──────────────────────────────────────────
    struct VidState {
        cols: AtomicU16,
        rows: AtomicU16,
        paused: AtomicBool,
        frame_count: AtomicU64,
        current_time: AtomicU64,
        duration: AtomicU64,
    }

    let state = Arc::new(VidState {
        cols: AtomicU16::new(total_cols),
        rows: AtomicU16::new(total_rows.saturating_sub(UI_ROWS_RESERVED)),
        paused: AtomicBool::new(false),
        frame_count: AtomicU64::new(0),
        current_time: AtomicU64::new(0),
        duration: AtomicU64::new(0),
    });

    let (frame_tx, mut frame_rx) = watch::channel::<Option<Vec<u8>>>(None);
    let capture_js = build_capture_js();

    let state_cap = Arc::clone(&state);
    let client_cap = client.clone();

    tokio::spawn(async move {
        let mut fallback = !video_found;
        let mut retry_counter = 0u32;
        let mut time_timer = Instant::now();

        loop {
            let cols = state_cap.cols.load(Ordering::Relaxed);
            let rows = state_cap.rows.load(Ordering::Relaxed);
            let paused = state_cap.paused.load(Ordering::Relaxed);

            if paused {
                sleep(Duration::from_millis(50)).await;
                continue;
            }

            let cols_u = cols as u64;
            let rows2_u = (rows as u64).saturating_mul(2);
            if cols_u == 0 || rows2_u == 0 {
                sleep(Duration::from_millis(FRAME_INTERVAL_MS)).await;
                continue;
            }

            let frame_data: Option<Vec<u8>> = if fallback {
                retry_counter += 1;
                if retry_counter >= 30 {
                    let result = client_cap
                        .execute(&capture_js, vec![
                            serde_json::Value::from(cols_u),
                            serde_json::Value::from(rows2_u),
                        ])
                        .await
                        .ok()
                        .and_then(|v| v.as_str().map(|s| s.to_string()));

                    match result {
                        Some(ref d) if d.starts_with("data:") => {
                            fallback = false;
                            retry_counter = 0;
                            parse_data_url(d)
                        }
                        _ => client_cap.screenshot().await.ok(),
                    }
                } else {
                    client_cap.screenshot().await.ok()
                }
            } else {
                let result = client_cap
                    .execute(&capture_js, vec![
                        serde_json::Value::from(cols_u),
                        serde_json::Value::from(rows2_u),
                    ])
                    .await
                    .ok()
                    .and_then(|v| v.as_str().map(|s| s.to_string()));

                match result {
                    Some(ref d) if d.starts_with("data:") => parse_data_url(d),
                    _ => {
                        fallback = true;
                        client_cap.screenshot().await.ok()
                    }
                }
            };

            if let Some(bytes) = frame_data {
                let _ = frame_tx.send(Some(bytes));
                state_cap.frame_count.fetch_add(1, Ordering::Relaxed);
            }

            if time_timer.elapsed() >= Duration::from_secs(1) {
                let time_result: Option<(f64, f64)> = client_cap
                    .execute(
                        r#"
                        let v = document.querySelector('video');
                        if (!v) {
                            let p = document.querySelector('[data-media-player]');
                            if (p && p.shadowRoot) v = p.shadowRoot.querySelector('video');
                        }
                        return v ? [v.currentTime, v.duration] : [0, 0];
                        "#,
                        vec![],
                    )
                    .await
                    .ok()
                    .and_then(|v| v.as_array().map(|a| {
                        (a[0].as_f64().unwrap_or(0.0), a[1].as_f64().unwrap_or(0.0))
                    }));

                if let Some((ct, dur)) = time_result {
                    state_cap.current_time.store((ct * 10.0) as u64, Ordering::Relaxed);
                    state_cap.duration.store((dur * 10.0) as u64, Ordering::Relaxed);
                }
                time_timer = Instant::now();
            }

            sleep(Duration::from_millis(FRAME_INTERVAL_MS)).await;
        }
    });

    // ── Render loop ───────────────────────────────────────────
    let client_render = client.clone();

    let mut last_render = Instant::now();

    loop {
        if event::poll(Duration::from_millis(16))? {
            match event::read()? {
                Event::Key(k) => match k.code {
                    KeyCode::Char('q') | KeyCode::Esc => break,
                    KeyCode::Char('c') if k.modifiers.contains(KeyModifiers::CONTROL) => break,
                    KeyCode::Char(' ') => {
                        let is_paused = state.paused.fetch_xor(true, Ordering::Relaxed);
                        let js = if is_paused {
                            r#"
                                let v = document.querySelector('video');
                                if (!v) { let p = document.querySelector('[data-media-player]'); if (p && p.shadowRoot) v = p.shadowRoot.querySelector('video'); }
                                if (v && v.paused) v.play();
                            "#
                        } else {
                            r#"
                                let v = document.querySelector('video');
                                if (!v) { let p = document.querySelector('[data-media-player]'); if (p && p.shadowRoot) v = p.shadowRoot.querySelector('video'); }
                                if (v) v.pause();
                            "#
                        };
                        let _ = client_render.execute(js, vec![]).await;
                        let _ = client_render.execute(HIDE_UI_JS, vec![]).await;
                    }
                    KeyCode::Left => {
                        let js = r#"
                            let v = document.querySelector('video');
                            if (!v) { let p = document.querySelector('[data-media-player]'); if (p && p.shadowRoot) v = p.shadowRoot.querySelector('video'); }
                            if (v) v.currentTime = Math.max(0, v.currentTime - SEEK_STEP);
                        "#.replace("SEEK_STEP", &SEEK_STEP.to_string());
                        let _ = client_render.execute(&js, vec![]).await;
                        let _ = client_render.execute(HIDE_UI_JS, vec![]).await;
                    }
                    KeyCode::Right => {
                        let js = r#"
                            let v = document.querySelector('video');
                            if (!v) { let p = document.querySelector('[data-media-player]'); if (p && p.shadowRoot) v = p.shadowRoot.querySelector('video'); }
                            if (v) v.currentTime = Math.min(v.duration, v.currentTime + SEEK_STEP);
                        "#.replace("SEEK_STEP", &SEEK_STEP.to_string());
                        let _ = client_render.execute(&js, vec![]).await;
                        let _ = client_render.execute(HIDE_UI_JS, vec![]).await;
                    }
                    _ => {}
                },
                Event::Resize(nc, nr) => {
                    let nv = nr.saturating_sub(UI_ROWS_RESERVED);
                    state.cols.store(nc, Ordering::Relaxed);
                    state.rows.store(nv, Ordering::Relaxed);
                    let _ = execute!(io::stdout(), Clear(ClearType::All));
                }
                _ => {}
            }
        }

        if last_render.elapsed() >= Duration::from_millis(FRAME_INTERVAL_MS) {
            let frame_opt = {
                let guard = frame_rx.borrow_and_update();
                guard.clone()
            };

            if let Some(bytes) = frame_opt {
                if let Ok(img) = image::load_from_memory(&bytes) {
                    let cols = state.cols.load(Ordering::Relaxed);
                    let rows = state.rows.load(Ordering::Relaxed);
                    if cols > 0 && rows > 0 {
                        let ansi = to_halfblocks(&img, cols, rows);
                        let _ = execute!(io::stdout(), cursor::MoveTo(0, 0));
                        let _ = io::stdout().write_all(ansi.as_bytes());
                    }
                }
            }

            let total_cols = state.cols.load(Ordering::Relaxed);
            let paused = state.paused.load(Ordering::Relaxed);

            let ct_raw = state.current_time.load(Ordering::Relaxed);
            let dur_raw = state.duration.load(Ordering::Relaxed);

            let _ = draw_ui(
                &mut io::stdout(),
                total_rows,
                total_cols,
                paused,
                ct_raw as f64 / 10.0,
                dur_raw as f64 / 10.0,
            );
            last_render = Instant::now();
        }
    }

    client.close().await.ok();
    gecko_proc.kill().ok();
    let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture, cursor::Show);
    try_restore_font();
    let _ = disable_raw_mode();

    Ok(())
}

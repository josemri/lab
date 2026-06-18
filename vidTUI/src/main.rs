mod tmdb;
mod ui;
mod video;

use tmdb::*;
use ui::*;
use video::*;

use std::{io, time::Duration};
use std::collections::HashSet;
use tokio::sync::mpsc;

use crossterm::{
    event::{self, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};

use ratatui::{
    backend::CrosstermBackend,
    Terminal,
};

fn build_vidlink_url(movie: &Movie) -> String {
    format!("https://vidlink.pro/movie/{}", movie.id)
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // ── Resolve dependencies (geckodriver + firefox) before entering TUI ──────
    let geckodriver_path = resolve_geckodriver().await?;
    let firefox_path = resolve_firefox()?;

    // ── Movies TUI ──────────────────────────────────────────────────────────
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App::default();

    let (poster_tx, mut poster_rx) = mpsc::unbounded_channel::<(String, bool, Vec<ratatui::text::Line<'static>>)>();
    let mut downloading: HashSet<String> = HashSet::new();
    let mut sizes_ready = false;
    let (_results_tx, mut results_rx) = tokio::sync::mpsc::unbounded_channel::<Vec<Movie>>();
    let mut last_searched = String::new();

    loop {
        let current_size = terminal.size()?;
        let current = (current_size.width, current_size.height);
        if current != app.last_terminal_size && app.last_terminal_size != (0, 0) {
            app.poster_cache.clear();
            app.poster_cache_small.clear();
            downloading.clear();
            sizes_ready = false;
        }
        app.last_terminal_size = current;
        terminal.draw(|f| ui::draw(f, &mut app))?;

        if !app.results.is_empty() && app.center_size != (80, 60) {
            sizes_ready = true;
        }

        let mut got_batch = false;
        while let Ok(batch) = results_rx.try_recv() {
            app.results.extend(batch);
            got_batch = true;
        }

        if app.loading_results && !got_batch {
            match results_rx.try_recv() {
                Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => {
                    app.loading_results = false;
                }
                _ => {}
            }
        }

        while let Ok((path, is_big, lines)) = poster_rx.try_recv() {
            let key = format!("{}:{}", path, if is_big { "big" } else { "small" });
            downloading.remove(&key);
            if is_big {
                app.poster_cache.insert(path, lines);
            } else {
                app.poster_cache_small.insert(path, lines);
            }
        }

        // ── INPUT ───────────────────────────────────────────────────────────
        if event::poll(Duration::from_millis(16))? {
            if let Event::Key(key) = event::read()? {
                match key.code {

                    KeyCode::Char('p') if app.expanded => {
                        if let Some(movie) = app.results.get(app.selected) {
                            let url = build_vidlink_url(movie);

                            // Exit TUI
                            disable_raw_mode()?;
                            execute!(io::stdout(), LeaveAlternateScreen)?;
                            drop(terminal);

                            // Play video
                            if let Err(e) = play_video(&url, &geckodriver_path, &firefox_path).await {
                                eprintln!("Playback error: {}", e);
                            }

                            // Re-enter TUI
                            enable_raw_mode()?;
                            execute!(io::stdout(), EnterAlternateScreen)?;
                            terminal = Terminal::new(CrosstermBackend::new(io::stdout()))?;
                        }
                    }

                    KeyCode::Enter => {
                        if !app.results.is_empty() && app.input == last_searched {
                            app.expanded = !app.expanded;
                        } else if !app.input.is_empty() {
                            app.results.clear();
                            app.selected = 0;
                            app.expanded = false;
                            app.poster_cache.clear();
                            app.poster_cache_small.clear();
                            app.frozen_prev = None;
                            downloading.clear();
                            sizes_ready = false;
                            last_searched = app.input.clone();
                            app.loading_results = true;

                            let (new_tx, new_rx) = tokio::sync::mpsc::unbounded_channel::<Vec<Movie>>();
                            results_rx = new_rx;

                            let query = app.input.clone();
                            tokio::spawn(async move {
                                search_tmdb(&query, new_tx).await;
                            });
                        }
                    }
                    KeyCode::Esc | KeyCode::Char('q') => {
                        if app.expanded {
                            app.expanded = false;
                        } else {
                            break;
                        }
                    }
                    KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => break,
                    KeyCode::Left | KeyCode::Up => {
                        if !app.results.is_empty() && !app.expanded {
                            app.selected = if app.selected == 0 {
                                app.results.len() - 1
                            } else {
                                app.selected - 1
                            };
                        }
                    }
                    KeyCode::Right | KeyCode::Down => {
                        if !app.results.is_empty() && !app.expanded {
                            app.selected = (app.selected + 1) % app.results.len();
                        }
                    }
                    KeyCode::Char(c) => {
                        if !app.expanded {
                            app.input.push(c);
                        }
                    }
                    KeyCode::Backspace => {
                        if !app.expanded {
                            app.input.pop();
                        }
                    }
                    _ => {}
                }
            }
        }

        if app.input.is_empty() && !app.results.is_empty() {
            app.results.clear();
            app.selected = 0;
            app.poster_cache.clear();
            app.poster_cache_small.clear();
            downloading.clear();
        }

        // ── LANZAR DESCARGAS ────────────────────────────────────────────────
        if !app.results.is_empty() && sizes_ready {
            let prev = if app.selected == 0 { app.results.len() - 1 } else { app.selected - 1 };
            let next = (app.selected + 1) % app.results.len();

            for (i, is_big) in [(app.selected, true), (prev, false), (next, false)] {
                if let Some(movie) = app.results.get(i) {
                    if let Some(poster) = movie.poster_path.clone() {
                        if poster.is_empty() { continue; }

                        let key = format!("{}:{}", poster, if is_big { "big" } else { "small" });
                        let cache = if is_big { &app.poster_cache } else { &app.poster_cache_small };

                        if cache.contains_key(&poster) { continue; }
                        if downloading.contains(&key) { continue; }

                        downloading.insert(key);
                        let tx = poster_tx.clone();
                        let (w, h) = if is_big {
                            app.center_size
                        } else {
                            app.side_size
                        };
                        tokio::spawn(async move {
                            if let Some(lines) = load_image_ansi(&poster, w, h).await {
                                let _ = tx.send((poster, is_big, lines));
                            }
                        });
                    }
                }
            }
        }
    }

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    Ok(())
}

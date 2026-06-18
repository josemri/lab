use ratatui::{
    prelude::*,
    widgets::{Block, Borders, Paragraph, BorderType},
    text::Line,
};
use crate::tmdb::Movie;
use std::collections::HashMap;
use figlet_rs::FIGfont;

pub struct App {
    pub input: String,
    pub results: Vec<Movie>,
    pub selected: usize,
    pub poster_cache: HashMap<String, Vec<Line<'static>>>,
    pub poster_cache_small: HashMap<String, Vec<Line<'static>>>,
    pub center_size: (u32, u32),
    pub side_size: (u32, u32),
    pub last_terminal_size: (u16, u16),
    pub expanded: bool,
    pub loading_results: bool,
    pub frozen_prev: Option<Vec<Line<'static>>>,
}

impl Default for App {
    fn default() -> Self {
        Self {
            input: String::new(),
            results: vec![],
            selected: 0,
            poster_cache: HashMap::new(),
            poster_cache_small: HashMap::new(),
            center_size: (80, 60),
            side_size: (40, 30),
            last_terminal_size: (0, 0),
            expanded: false,
            loading_results: false,
            frozen_prev: None,
        }
    }
}

pub fn draw(f: &mut Frame, app: &mut App) {
    let area = f.size();
    let len = app.results.len();

    let main = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(0),
            Constraint::Length(3),
        ])
        .split(area);

    // ───────── BARRA DE BÚSQUEDA ─────────
    let bottom = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(40),
            Constraint::Percentage(60),
        ])
        .split(main[1]);

    let search_title = if len == 0 {
        "[?]".to_string()
    } else {
        format!("[?] ({}/{})", app.selected + 1, len)
    };
    let search_widget = Paragraph::new(format!("{}", app.input))
        .block(
            Block::default()
                .title(search_title)
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default().fg(Color::Cyan)),
        )
        .style(Style::default().fg(Color::White));
    f.render_widget(search_widget, bottom[0]);

    // ───────── HINT ─────────
    let hint = if app.expanded {
        " [Enter] close   [P] > Play   [q/esc] back "
    } else if len > 0 {
        " [Enter] expand info   [←/→] browse   [q/esc] exit "
    } else {
        " Type to search movies   [q/esc] exit "
    };
    let hint_widget = Paragraph::new(hint)
        .style(Style::default().fg(Color::DarkGray))
        .alignment(Alignment::Center);
    f.render_widget(hint_widget, bottom[1]);

    if len == 0 {
        let empty = Paragraph::new("")
            .alignment(Alignment::Center)
            .style(Style::default().fg(Color::DarkGray));
        f.render_widget(empty, main[0]);
        return;
    }

    let prev = if app.loading_results && app.selected == 0 {
        app.selected
    } else if app.selected == 0 {
        len - 1
    } else {
        app.selected - 1
    };
    let next = (app.selected + 1) % len;

    // ───────── INFO TÍTULO ─────────
    let movie = &app.results[app.selected];
    let title = movie.title.clone().unwrap_or_default();

    let font = FIGfont::standard().unwrap();
    let art_string = font.convert(&title)
        .map(|a| a.to_string())
        .unwrap_or_default();
    let art_height = art_string.lines().count() as u16 + 2;

    let top = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(art_height),
            Constraint::Min(0),
        ])
        .split(main[0]);

    let info_lines: Vec<Line> = art_string
        .lines()
        .map(|line| Line::from(Span::styled(
            line.to_string(),
            Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
        )))
        .collect();

    let info = Paragraph::new(info_lines)
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::NONE));
    f.render_widget(info, top[0]);

    // ───────── CAROUSEL ─────────
    let carousel_outer = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Length(5),
            Constraint::Min(0),
            Constraint::Length(5),
        ])
        .split(top[1]);

    let carousel = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),
            Constraint::Percentage(50),
            Constraint::Percentage(25),
        ])
        .split(carousel_outer[1]);

    let side_inner = |area: Rect, is_left: bool| -> Rect {
        if is_left {
            Rect { width: area.width.saturating_sub(3), ..area }
        } else {
            Rect { x: area.x + 3, width: area.width.saturating_sub(3), ..area }
        }
    };

    let prev_area = side_inner(carousel[0], true);
    let next_area = side_inner(carousel[2], false);

    app.center_size = (
        carousel[1].width as u32,
        (carousel[1].height as u32).saturating_sub(1) * 2,
    );
    app.side_size = (
        prev_area.width as u32,
        prev_area.height.saturating_sub(1) as u32 * 2,
    );

    let side_label = |t: &str| {
        Paragraph::new(t.to_string())
            .alignment(Alignment::Center)
            .style(Style::default().fg(Color::DarkGray))
    };

    let prev_title = app.results.get(prev).and_then(|m| m.title.as_deref()).unwrap_or("");
    let next_title = app.results.get(next).and_then(|m| m.title.as_deref()).unwrap_or("");

    let split_area = |area: Rect| -> (Rect, Rect) {
        let label = Rect { height: 1, ..area };
        let poster = Rect { y: area.y + 1, height: area.height.saturating_sub(1), ..area };
        (label, poster)
    };

    let (prev_label_area, prev_poster_area) = split_area(prev_area);
    let (next_label_area, next_poster_area) = split_area(next_area);

    f.render_widget(side_label(next_title), next_label_area);

    // ───────── POSTERS ─────────
    let prev_lines = if len > 1 {
        app.results.get(prev)
            .and_then(|m| m.poster_path.as_ref())
            .and_then(|p| app.poster_cache_small.get(p))
    } else { None };

    let center_lines = app.results.get(app.selected)
        .and_then(|m| m.poster_path.as_ref())
        .and_then(|p| app.poster_cache.get(p));

    let next_lines = if len > 1 {
        app.results.get(next)
            .and_then(|m| m.poster_path.as_ref())
            .and_then(|p| app.poster_cache_small.get(p))
    } else { None };

    let has_poster = |i: usize| {
        app.results.get(i)
            .and_then(|m| m.poster_path.as_ref())
            .map(|p| !p.is_empty())
            .unwrap_or(false)
    };

    if !app.loading_results || app.selected != 0 {
        if let Some(lines) = prev_lines {
            if !lines.is_empty() {
                app.frozen_prev = Some(lines.clone());
            }
        }
    }

    let effective_prev_lines = if app.loading_results && app.selected == 0 {
        app.frozen_prev.as_ref()
    } else {
        prev_lines
    };

    let show_prev = !(app.loading_results && app.selected == 0 && app.frozen_prev.is_none());

    if show_prev {
        f.render_widget(side_label(prev_title), prev_label_area);
        render_poster(f, prev_poster_area, effective_prev_lines, len > 1 && has_poster(prev));
    } else {
        let loading = Paragraph::new("[#]")
            .alignment(Alignment::Center)
            .style(Style::default().fg(Color::DarkGray));
        f.render_widget(loading, prev_poster_area);
    }

    render_poster(f, next_poster_area, next_lines, len > 1 && has_poster(next));

    // ───────── POSTER CENTRAL ─────────
    if app.expanded {
        render_poster_dimmed(f, carousel[1], center_lines, has_poster(app.selected), movie);
    } else {
        render_poster(f, carousel[1], center_lines, has_poster(app.selected));
    }
}

fn render_poster(
    f: &mut Frame,
    area: Rect,
    lines: Option<&Vec<Line<'static>>>,
    has_poster: bool,
) {
    let content = match lines {
        Some(l) if !l.is_empty() => l.clone(),
        _ => {
            let msg = if has_poster { "loading..." } else { "[ missing poster ]" };
            let padding = (area.height / 2).saturating_sub(1) as usize;
            let mut v = vec![Line::from(""); padding];
            v.push(Line::from(msg));
            v
        }
    };

    let widget = Paragraph::new(content)
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::NONE));
    f.render_widget(widget, area);
}

fn render_poster_dimmed(
    f: &mut Frame,
    area: Rect,
    lines: Option<&Vec<Line<'static>>>,
    has_poster: bool,
    movie: &Movie,
) {
    let darken = |c: Color| -> Color {
        match c {
            Color::Rgb(r, g, b) => Color::Rgb(
                (r as u16 * 4 / 10) as u8,
                (g as u16 * 4 / 10) as u8,
                (b as u16 * 4 / 10) as u8,
            ),
            other => other,
        }
    };

    let dimmed_content: Vec<Line> = match lines {
        Some(l) if !l.is_empty() => l.iter().map(|line| {
            Line::from(
                line.spans.iter().map(|span| {
                    let style = span.style;
                    Span::styled(
                        span.content.clone(),
                        Style::default()
                            .fg(style.fg.map(&darken).unwrap_or(Color::DarkGray))
                            .bg(style.bg.map(&darken).unwrap_or(Color::Rgb(0, 0, 0))),
                    )
                }).collect::<Vec<_>>()
            )
        }).collect(),
        _ => {
            let msg = if has_poster { "loading..." } else { "[ missing poster ]" };
            let padding = (area.height / 2).saturating_sub(1) as usize;
            let mut v = vec![Line::from(""); padding];
            v.push(Line::from(msg));
            v
        }
    };

    let poster_widget = Paragraph::new(dimmed_content)
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::NONE));
    f.render_widget(poster_widget, area);

    // ───────── OVERLAY ─────────
    let title = movie.title.clone().unwrap_or_default();
    let year = movie.release_date
        .as_ref()
        .and_then(|d| d.split('-').next())
        .unwrap_or("?")
        .to_string();
    let rating = movie.vote_average
        .map(|v| format!("{:.1}/10 *", v))
        .unwrap_or_default();
    let overview = movie.overview.clone().unwrap_or_default();

    let max_width = area.width.saturating_sub(4) as usize;
    let wrapped_overview = wrap_text(&overview, max_width);

    let mut overlay_lines: Vec<Line> = vec![
        Line::from(Span::styled(
            format!("  {}  ", title),
            Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
        )),
        Line::from(vec![
            Span::styled(format!("  {} ", year), Style::default().fg(Color::Yellow)),
        ]),
        Line::from(vec![
            Span::styled(format!("  {}", rating), Style::default().fg(Color::Green)),
        ]),
        Line::from(""),
    ];

    for wline in &wrapped_overview {
        overlay_lines.push(Line::from(Span::styled(
            format!("  {}  ", wline),
            Style::default().fg(Color::White),
        )));
    }

    let text_height = overlay_lines.len() as u16;
    let pad_top = area.height.saturating_sub(text_height) / 2;
    let mut padded: Vec<Line> = vec![Line::from(""); pad_top as usize];
    padded.extend(overlay_lines);

    // ───────── BOTÓN PLAY ─────────
    let btn_width = 17u16;
    let btn_height = 3u16;
    let btn_x = area.x + (area.width.saturating_sub(btn_width)) / 2;
    let btn_y = area.y + area.height.saturating_sub(btn_height + 2);
    let btn_area = Rect::new(btn_x, btn_y, btn_width, btn_height);

    let play_btn = Paragraph::new(Line::from(Span::styled(
        "  > Play [P]  ",
        Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
    )))
    .alignment(Alignment::Center)
    .block(
        Block::default()
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(Style::default().fg(Color::White)),
    );

    let overlay = Paragraph::new(padded)
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::NONE));
    f.render_widget(overlay, area);
    f.render_widget(play_btn, btn_area);
}

fn wrap_text(text: &str, max_width: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut current = String::new();

    for word in text.split_whitespace() {
        if current.is_empty() {
            current = word.to_string();
        } else if current.len() + 1 + word.len() <= max_width {
            current.push(' ');
            current.push_str(word);
        } else {
            lines.push(current.clone());
            current = word.to_string();
        }
    }
    if !current.is_empty() {
        lines.push(current);
    }
    lines
}

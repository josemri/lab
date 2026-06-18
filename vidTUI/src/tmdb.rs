use serde::Deserialize;
use ratatui::{
    text::{Line, Span},
    style::{Color, Style},
};

#[derive(Clone, Deserialize, Debug)]
pub struct Movie {
    pub id: u32,
    pub title: Option<String>,
    pub overview: Option<String>,
    pub poster_path: Option<String>,
    pub release_date: Option<String>,
    pub vote_average: Option<f32>,
    #[allow(dead_code)]
    pub vote_count: Option<u32>,
    #[allow(dead_code)]
    pub popularity: Option<f32>,
    #[allow(dead_code)]
    pub original_language: Option<String>,
}

#[derive(Deserialize)]
struct Resp {
    results: Vec<Movie>,
}

pub async fn search_tmdb(query: &str, tx: tokio::sync::mpsc::UnboundedSender<Vec<Movie>>) {
    let api_key = "INSERT HERE YOUR TMDB API KEY";
    let mut page = 1u32;

    loop {
        let url = format!(
            "https://api.themoviedb.org/3/search/movie?api_key={}&query={}&page={}",
            api_key,
            urlencoding::encode(query),
            page,
        );

        let batch = match reqwest::get(&url).await {
            Ok(resp) => match resp.json::<Resp>().await {
                Ok(data) => data.results,
                Err(_) => break,
            },
            Err(_) => break,
        };

        let count = batch.len();

        if tx.send(batch).is_err() {
            break;
        }

        if count < 20 {
            break;
        }

        page += 1;
        tokio::time::sleep(tokio::time::Duration::from_millis(250)).await;
    }
}

fn clamp_black(c: u8) -> u8 {
    if c == 0 { 1 } else { c }
}

pub async fn load_image_ansi(
    poster_url: &str,
    width: u32,
    height: u32,
) -> Option<Vec<Line<'static>>> {
    let url = format!("https://image.tmdb.org/t/p/w300{}", poster_url);
    let bytes = reqwest::get(&url).await.ok()?.bytes().await.ok()?;
    let img = image::load_from_memory(&bytes).ok()?;
    let resized = img.resize(width, height, image::imageops::FilterType::Triangle);
    let rgb = resized.to_rgb8();
    let (w, h) = rgb.dimensions();
    let mut lines: Vec<Line> = Vec::new();

    for y in (0..h).step_by(2) {
        let mut spans: Vec<Span> = Vec::new();
        for x in 0..w {
            let top = rgb.get_pixel(x, y);
            let bottom_y = (y + 1).min(h - 1);
            let bottom = rgb.get_pixel(x, bottom_y);
            spans.push(Span::styled(
                "▀",
                Style::default()
                    .fg(Color::Rgb(clamp_black(top[0]), clamp_black(top[1]), clamp_black(top[2])))
                    .bg(Color::Rgb(clamp_black(bottom[0]), clamp_black(bottom[1]), clamp_black(bottom[2]))),
            ));
        }
        lines.push(Line::from(spans));
    }

    Some(lines)
}

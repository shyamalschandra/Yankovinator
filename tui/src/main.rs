//! Newline-delimited JSON on stdin; ncurses-like alternate-screen dashboard
//! with color boxes and emoji progress bars per threaded worker.

use crossterm::{
    cursor::{Hide, Show},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Paragraph, Wrap},
    Frame, Terminal,
};
use serde::Deserialize;
use std::io::{self, BufRead, Write};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::thread;
use std::time::Duration;

#[derive(Debug, Deserialize, Clone)]
#[serde(tag = "t")]
enum EventMsg {
    #[serde(rename = "init")]
    Init {
        total: u32,
        workers: u32,
        label: String,
    },
    #[serde(rename = "snapshot")]
    Snapshot {
        completed: u32,
        tick: u64,
        batch_spent_secs: f64,
        batch_eta_secs: Option<f64>,
        status: String,
        messages: Vec<String>,
        workers: Vec<WorkerSnap>,
    },
    #[serde(rename = "quit")]
    Quit,
}

#[derive(Debug, Deserialize, Clone, Default)]
struct WorkerSnap {
    idle: bool,
    job_number: u32,
    line: Option<u32>,
    line_total: Option<u32>,
    spent_secs: f64,
    eta_secs: Option<f64>,
    slot_tick: u32,
}

#[derive(Clone)]
struct App {
    label: String,
    total: u32,
    completed: u32,
    tick: u64,
    batch_spent_secs: f64,
    batch_eta_secs: Option<f64>,
    status: String,
    messages: Vec<String>,
    workers: Vec<WorkerSnap>,
    quit: bool,
}

impl App {
    fn waiting() -> Self {
        Self {
            label: "Generations".into(),
            total: 1,
            completed: 0,
            tick: 0,
            batch_spent_secs: 0.0,
            batch_eta_secs: None,
            status: String::new(),
            messages: Vec::new(),
            workers: Vec::new(),
            quit: false,
        }
    }

    fn apply(&mut self, msg: EventMsg) {
        match msg {
            EventMsg::Init {
                total,
                workers,
                label,
            } => {
                self.label = label;
                self.total = total.max(1);
                self.workers = vec![WorkerSnap::default(); workers as usize];
            }
            EventMsg::Snapshot {
                completed,
                tick,
                batch_spent_secs,
                batch_eta_secs,
                status,
                messages,
                workers,
            } => {
                self.completed = completed;
                self.tick = tick;
                self.batch_spent_secs = batch_spent_secs;
                self.batch_eta_secs = batch_eta_secs;
                self.status = status;
                self.messages = messages;
                if !workers.is_empty() {
                    self.workers = workers;
                }
            }
            EventMsg::Quit => self.quit = true,
        }
    }
}

fn format_duration(secs: f64) -> String {
    let total = secs.max(0.0).round() as u64;
    if total < 1 {
        return "<1s".into();
    }
    if total < 60 {
        return format!("{total}s");
    }
    let minutes = total / 60;
    let s = total % 60;
    if minutes < 60 {
        return format!("{minutes}m{s:02}s");
    }
    let hours = minutes / 60;
    let m = minutes % 60;
    format!("{hours}h{m:02}m")
}

fn format_eta(secs: Option<f64>) -> String {
    match secs {
        None => "…".into(),
        Some(s) if s <= 0.0 => "0s".into(),
        Some(s) => format!("~{}", format_duration(s)),
    }
}

fn truncate(s: &str, max: usize) -> String {
    let t = s.trim();
    if t.chars().count() <= max {
        return t.to_string();
    }
    let mut out: String = t.chars().take(max.saturating_sub(1)).collect();
    out.push('…');
    out
}

/// Emoji block progress bar (ncurses-like filled gauge, UTF-8).
fn emoji_bar(ratio: f64, width: usize, fill: &str, empty: &str) -> String {
    if width == 0 {
        return String::new();
    }
    let r = ratio.clamp(0.0, 1.0);
    let filled = ((r * width as f64).round() as usize).min(width);
    let mut out = String::with_capacity(width * fill.len());
    for i in 0..width {
        if i < filled {
            out.push_str(fill);
        } else {
            out.push_str(empty);
        }
    }
    out
}

fn worker_ratio(worker: &WorkerSnap, global_tick: u64) -> f64 {
    if worker.idle {
        return 0.0;
    }
    if let (Some(line), Some(total)) = (worker.line, worker.line_total) {
        if total > 0 {
            return (line as f64 / total as f64).clamp(0.0, 1.0);
        }
    }
    // Indeterminate pulse while waiting on Ollama / early lines.
    let t = (worker.slot_tick as u64 + global_tick) % 24;
    let phase = (t as f64 / 24.0) * std::f64::consts::TAU;
    0.18 + 0.72 * (0.5 + 0.5 * phase.sin())
}

const WORKER_PALETTE: [(Color, &str, &str); 8] = [
    (Color::Cyan, "🟦", "⬛"),
    (Color::Green, "🟩", "⬛"),
    (Color::Yellow, "🟨", "⬛"),
    (Color::Magenta, "🟪", "⬛"),
    (Color::LightBlue, "💙", "⬛"),
    (Color::LightRed, "🟥", "⬛"),
    (Color::LightGreen, "💚", "⬛"),
    (Color::LightMagenta, "🩷", "⬛"),
];

fn worker_style(index: usize) -> (Color, &'static str, &'static str) {
    WORKER_PALETTE[index % WORKER_PALETTE.len()]
}

fn worker_box_height() -> u16 {
    4 // title border + bar line + timing line + bottom border
}

fn draw_overall(frame: &mut Frame, app: &App, area: Rect) {
    let ratio = (app.completed as f64 / app.total as f64).clamp(0.0, 1.0);
    let bar_width = area.width.saturating_sub(4).min(22).max(8) as usize;
    let bar = emoji_bar(ratio, bar_width, "🟩", "⬜");
    let title = format!(
        "☁️  Yankovinator · {} · {}/{} ({:.0}%)",
        app.label,
        app.completed,
        app.total,
        ratio * 100.0
    );
    let timing = format!(
        "elapsed {} · remain {}",
        format_duration(app.batch_spent_secs),
        format_eta(app.batch_eta_secs)
    );
    let status = if app.status.is_empty() {
        String::new()
    } else {
        truncate(&app.status, 56)
    };
    let mut lines = vec![Line::from(vec![
        Span::styled(
            format!("{bar}  {:.0}%", ratio * 100.0),
            Style::default().fg(Color::Green).add_modifier(Modifier::BOLD),
        ),
        Span::raw("  "),
        Span::styled(
            format!("⏱ {timing}"),
            Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
        ),
    ])];
    if !status.is_empty() {
        lines.push(Line::from(Span::styled(
            format!("💬 {status}"),
            Style::default().fg(Color::Gray),
        )));
    }
    let body = Paragraph::new(lines).block(
        Block::default()
            .borders(Borders::ALL)
            .border_type(BorderType::Double)
            .border_style(Style::default().fg(Color::Cyan))
            .title(Span::styled(
                title,
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            )),
    );
    frame.render_widget(body, area);
}

fn draw_messages(frame: &mut Frame, app: &App, area: Rect) {
    let lines: Vec<Line> = app
        .messages
        .iter()
        .rev()
        .take(3)
        .enumerate()
        .map(|(i, msg)| {
            let prefix = if i == 0 { "💬 " } else { "   ↳ " };
            Line::from(vec![
                Span::styled(prefix, Style::default().fg(Color::Magenta)),
                Span::styled(truncate(msg, 100), Style::default().fg(Color::White)),
            ])
        })
        .collect();
    let body = if lines.is_empty() {
        Paragraph::new(Line::from(Span::styled(
            "🧵 Waiting for worker updates…",
            Style::default().fg(Color::DarkGray),
        )))
    } else {
        Paragraph::new(lines).wrap(Wrap { trim: true })
    }
    .block(
        Block::default()
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(Style::default().fg(Color::Magenta))
            .title(Span::styled(" Feed ", Style::default().fg(Color::Magenta))),
    );
    frame.render_widget(body, area);
}

fn draw_worker_box(frame: &mut Frame, app: &App, index: usize, worker: &WorkerSnap, area: Rect) {
    let (color, fill, empty) = worker_style(index);
    let ratio = worker_ratio(worker, app.tick);
    // Leave room on the bar row for "elapsed … · remain …"
    let bar_cells = area.width.saturating_sub(36).min(14).max(5) as usize;
    let bar = emoji_bar(ratio, bar_cells, fill, empty);

    let (state_emoji, state_text, border_color) = if worker.idle {
        ("💤", "idle".to_string(), Color::DarkGray)
    } else {
        let mut text = format!("#{}", worker.job_number);
        if let (Some(l), Some(n)) = (worker.line, worker.line_total) {
            if n > 0 {
                text.push_str(&format!(" · L{l}/{n}"));
            }
        } else {
            text.push_str(" · running");
        }
        ("⚡", text, color)
    };

    let title = format!(" 🧵 W{:02} {state_emoji} {state_text} ", index + 1);
    let elapsed = format_duration(worker.spent_secs);
    let remain = format_eta(worker.eta_secs);
    let pct = format!("{:.0}%", ratio * 100.0);

    // Timing lives on the progress bar row so each worker bar shows elapsed + remaining.
    let body = Paragraph::new(vec![
        Line::from(vec![
            Span::styled(
                bar,
                Style::default().fg(border_color).add_modifier(Modifier::BOLD),
            ),
            Span::raw(" "),
            Span::styled(
                pct,
                Style::default()
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::raw("  "),
            Span::styled(
                format!("⏱ elapsed {elapsed}"),
                Style::default().fg(Color::White),
            ),
            Span::styled(" · ", Style::default().fg(Color::DarkGray)),
            Span::styled(
                format!("⌛ remain {remain}"),
                Style::default().fg(Color::LightGreen),
            ),
        ]),
        Line::from(Span::styled(
            if worker.idle {
                "waiting for next generation".to_string()
            } else if worker.line.is_some() {
                "tracking line progress".to_string()
            } else {
                "estimating from recent jobs".to_string()
            },
            Style::default().fg(Color::DarkGray),
        )),
    ])
    .alignment(Alignment::Left)
    .block(
        Block::default()
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(Style::default().fg(border_color))
            .title(Span::styled(
                title,
                Style::default()
                    .fg(border_color)
                    .add_modifier(Modifier::BOLD),
            )),
    );
    frame.render_widget(body, area);
}

fn worker_grid(area: Rect, count: usize) -> Vec<Rect> {
    if count == 0 {
        return Vec::new();
    }
    let box_h = worker_box_height();
    let cols = if area.width >= 88 && count >= 2 {
        2
    } else {
        1
    };
    let rows = count.div_ceil(cols);
    let mut out = Vec::with_capacity(count);

    let row_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints(vec![Constraint::Length(box_h); rows])
        .split(area);

    for (r, row_area) in row_layout.iter().enumerate() {
        if cols == 1 {
            let idx = r;
            if idx < count {
                out.push(*row_area);
            }
        } else {
            let col_areas = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
                .split(*row_area);
            for (c, cell) in col_areas.iter().enumerate() {
                let idx = r * cols + c;
                if idx < count {
                    // Tiny gutter between columns
                    let mut cell = *cell;
                    if c == 0 && cell.width > 1 {
                        cell.width = cell.width.saturating_sub(1);
                    } else if c == 1 && cell.x < u16::MAX {
                        cell.x = cell.x.saturating_add(1);
                        cell.width = cell.width.saturating_sub(1);
                    }
                    out.push(cell);
                }
            }
        }
    }
    out
}

fn draw(frame: &mut Frame, app: &App) {
    let root = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4), // overall box
            Constraint::Length(5), // message feed box
            Constraint::Min(worker_box_height()),
            Constraint::Length(1), // footer
        ])
        .split(frame.area());

    draw_overall(frame, app, root[0]);
    draw_messages(frame, app, root[1]);

    let worker_area = root[2];
    if app.workers.is_empty() {
        let hint = Paragraph::new(Line::from(Span::styled(
            "🧵 Spinning up threaded workers…",
            Style::default().fg(Color::Magenta),
        )))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default().fg(Color::DarkGray))
                .title(" Workers "),
        );
        frame.render_widget(hint, worker_area);
    } else {
        // Visible window of workers if terminal is short
        let max_visible = {
            let h = worker_area.height as usize;
            let box_h = worker_box_height() as usize;
            let cols = if worker_area.width >= 88 && app.workers.len() >= 2 {
                2
            } else {
                1
            };
            ((h / box_h.max(1)) * cols).max(1)
        };
        let start = if app.workers.len() > max_visible {
            // Prefer showing busy workers first
            let mut order: Vec<usize> = (0..app.workers.len()).collect();
            order.sort_by_key(|&i| app.workers[i].idle);
            order.truncate(max_visible);
            order
        } else {
            (0..app.workers.len()).collect()
        };

        let cells = worker_grid(worker_area, start.len());
        for (slot, &wid) in start.iter().enumerate() {
            if let Some(area) = cells.get(slot) {
                draw_worker_box(frame, app, wid, &app.workers[wid], *area);
            }
        }
    }

    let footer = Paragraph::new(Line::from(Span::styled(
        "╰─ yankovinator-tui · color boxes · emoji bars · resume: .yankovinator/",
        Style::default().fg(Color::DarkGray),
    )));
    frame.render_widget(footer, root[3]);
}

fn stdin_reader(tx: mpsc::Sender<EventMsg>) {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        match line {
            Ok(line) if line.trim().is_empty() => continue,
            Ok(line) => match serde_json::from_str::<EventMsg>(&line) {
                Ok(msg) => {
                    if tx.send(msg).is_err() {
                        break;
                    }
                }
                Err(e) => {
                    let _ = writeln!(io::stderr(), "yankovinator-tui: bad JSON: {e}");
                }
            },
            Err(_) => break,
        }
    }
}

fn drain_events(rx: &Receiver<EventMsg>, app: &mut App) {
    loop {
        match rx.try_recv() {
            Ok(msg) => app.apply(msg),
            Err(mpsc::TryRecvError::Empty) => break,
            Err(mpsc::TryRecvError::Disconnected) => {
                app.quit = true;
                break;
            }
        }
    }
}

fn run_dashboard(rx: Receiver<EventMsg>) -> io::Result<()> {
    let mut app = App::waiting();
    while !app.quit {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(msg) => app.apply(msg),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => app.quit = true,
        }
        if !app.workers.is_empty() {
            break;
        }
    }

    enable_raw_mode()?;
    let mut tty = io::stderr();
    execute!(tty, EnterAlternateScreen, Hide)?;
    let backend = ratatui::backend::CrosstermBackend::new(io::stderr());
    let mut terminal = Terminal::new(backend)?;

    while !app.quit {
        drain_events(&rx, &mut app);
        terminal.draw(|f| draw(f, &app))?;
        match rx.recv_timeout(Duration::from_millis(33)) {
            Ok(msg) => app.apply(msg),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => app.quit = true,
        }
    }

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen, Show)?;
    terminal.show_cursor()?;
    Ok(())
}

fn main() -> io::Result<()> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || stdin_reader(tx));
    run_dashboard(rx)
}

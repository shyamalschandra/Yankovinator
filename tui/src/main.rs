//! Newline-delimited JSON on stdin; fixed alternate-screen dashboard on stderr's TTY (stdout).

use crossterm::{
    cursor::{Hide, Show},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, Paragraph},
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

fn indeterminate_ratio(slot_tick: u32, global_tick: u64) -> f64 {
    let t = (slot_tick as u64 + global_tick) % 100;
    (t as f64 / 100.0).max(0.08)
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

fn draw(frame: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(3),
            Constraint::Length(1),
        ])
        .split(frame.area());

    let overall_ratio = app.completed as f64 / app.total as f64;
    let batch_timing = format!(
        "⏱ {}  ⌛ {}",
        format_duration(app.batch_spent_secs),
        format_eta(app.batch_eta_secs)
    );
    let title = format!(
        "☁️  📊 {}  {}/{} ({:.0}%)",
        app.label,
        app.completed,
        app.total,
        overall_ratio * 100.0
    );
    let gauge = Gauge::default()
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan))
                .title(title),
        )
        .gauge_style(Style::default().fg(Color::Green).bg(Color::DarkGray))
        .ratio(overall_ratio.min(1.0))
        .label(Span::styled(
            if app.status.is_empty() {
                batch_timing.clone()
            } else {
                format!("💬 {} · {}", app.status, batch_timing)
            },
            Style::default().fg(Color::Yellow),
        ));
    frame.render_widget(gauge, chunks[0]);

    let msg_count = app.messages.len().min(2);
    let worker_count = app.workers.len();
    let row_count = msg_count + worker_count;
    if row_count == 0 {
        let hint = Paragraph::new(Line::from(Span::styled(
            "🧵 Waiting for worker updates…",
            Style::default().fg(Color::Magenta),
        )));
        frame.render_widget(hint, chunks[1]);
    } else {
        let rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints(vec![Constraint::Length(1); row_count])
            .split(chunks[1]);

        let mut row_idx = 0;
        for msg in app.messages.iter().rev().take(2) {
            let prefix = if row_idx == 0 { "💬 " } else { "   ↳ " };
            let line = Line::from(vec![
                Span::styled(prefix, Style::default().fg(Color::Magenta)),
                Span::styled(truncate(msg, 96), Style::default().fg(Color::White)),
            ]);
            frame.render_widget(Paragraph::new(line), rows[row_idx]);
            row_idx += 1;
        }

        for (wid, worker) in app.workers.iter().enumerate() {
            let id = format!("W{:02}", wid + 1);
            let (label, ratio, color) = if worker.idle {
                ("💤 idle".to_string(), 0.0, Color::DarkGray)
            } else {
                let mut state = format!("⚡ #{}", worker.job_number);
                if let (Some(l), Some(n)) = (worker.line, worker.line_total) {
                    if n > 0 {
                        state.push_str(&format!(" L{l}/{n}"));
                    }
                }
                (
                    state,
                    indeterminate_ratio(worker.slot_tick, app.tick),
                    Color::Yellow,
                )
            };
            let timing = format!(
                "⏱ {}  ⌛ {}",
                format_duration(worker.spent_secs),
                format_eta(worker.eta_secs)
            );
            let gauge = Gauge::default()
                .gauge_style(Style::default().fg(color).bg(Color::DarkGray))
                .ratio(ratio.min(1.0))
                .label(Span::styled(
                    format!("{id} {label}  {timing}"),
                    Style::default().add_modifier(Modifier::BOLD),
                ));
            frame.render_widget(gauge, rows[row_idx]);
            row_idx += 1;
        }
    }

    let footer = Line::from(Span::styled(
        "╰─ yankovinator-tui · UTF-8 · resume: .yankovinator/",
        Style::default().fg(Color::DarkGray),
    ));
    frame.render_widget(Paragraph::new(footer), chunks[2]);
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

// Copyright (C) 2025, Shyamal Suhana Chandra
// Fixed-screen batch progress via ncurses (macOS CLI)

#include "yank_ncurses.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_MAC && !TARGET_OS_IPHONE

#include <curses.h>

static SCREEN *yank_screen = NULL;
static bool yank_active = false;
static int yank_panel_rows = 0;

bool yank_ncurses_begin(void) {
    if (yank_active) {
        return true;
    }
    if (!isatty(STDERR_FILENO)) {
        return false;
    }

    const char *term = getenv("TERM");
    if (term == NULL || term[0] == '\0') {
        term = "xterm-256color";
    }

    /* Alternate screen: no scrollback growth while the TUI runs. */
    fputs("\033[?1049h", stderr);
    fflush(stderr);

    yank_screen = newterm((char *)term, stderr, stderr);
    if (yank_screen == NULL) {
        fputs("\033[?1049l", stderr);
        fflush(stderr);
        return false;
    }
    set_term(yank_screen);

    cbreak();
    noecho();
    curs_set(0);
    keypad(stdscr, TRUE);
    scrollok(stdscr, FALSE);
    idlok(stdscr, FALSE);
    clearok(stdscr, TRUE);

    if (has_colors()) {
        start_color();
        use_default_colors();
    }

    clear();
    refresh();

    yank_active = true;
    yank_panel_rows = 0;
    return true;
}

void yank_ncurses_end(void) {
    if (!yank_active) {
        return;
    }

    if (yank_screen != NULL) {
        set_term(yank_screen);
        clear();
        refresh();
        endwin();
        delscreen(yank_screen);
        yank_screen = NULL;
    }

    fputs("\033[?1049l", stderr);
    fflush(stderr);

    yank_active = false;
    yank_panel_rows = 0;
}

void yank_ncurses_render_multiline(const char *text) {
    if (!yank_active || yank_screen == NULL || text == NULL) {
        return;
    }

    set_term(yank_screen);
    int maxRows = 0;
    int maxCols = 0;
    getmaxyx(stdscr, maxRows, maxCols);
    if (maxRows < 1) {
        maxRows = 24;
    }
    if (maxCols < 1) {
        maxCols = 80;
    }

    clear();
    int row = 0;
    const char *cursor = text;
    while (*cursor != '\0' && row < maxRows) {
        const char *lineStart = cursor;
        while (*cursor != '\0' && *cursor != '\n') {
            cursor++;
        }
        size_t lineLen = (size_t)(cursor - lineStart);
        if (lineLen > 0) {
            move(row, 0);
            clrtoeol();
            if (maxCols > 0) {
                int limit = (int)lineLen;
                if (limit > maxCols - 1) {
                    limit = maxCols - 1;
                }
                mvaddnstr(row, 0, lineStart, limit);
            }
            row++;
        } else if (cursor == lineStart && *cursor == '\n') {
            row++;
        }
        if (*cursor == '\n') {
            cursor++;
        }
    }

    yank_panel_rows = row;
    refresh();
}

#else

bool yank_ncurses_begin(void) {
    return false;
}

void yank_ncurses_end(void) {
}

void yank_ncurses_render_multiline(const char *text) {
    (void)text;
}

#endif

#ifndef yank_ncurses_h
#define yank_ncurses_h

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize ncurses on stderr (no scroll). Returns false if not a TTY or init fails.
bool yank_ncurses_begin(void);

/// Tear down ncurses and restore the terminal.
void yank_ncurses_end(void);

/// Draw newline-separated UTF-8 text from row 0; clears unused rows below the panel.
void yank_ncurses_render_multiline(const char *text);

#ifdef __cplusplus
}
#endif

#endif /* yank_ncurses_h */

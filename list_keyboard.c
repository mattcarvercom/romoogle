#include "list_keyboard.h"

#include <string.h>

// keyboard_layout_lowercase is the default mobile-style layout. The number
// toggle occupies the old shift position left of z; there is no enter key (Y
// closes the keyboard), and space is next to m.
static const char *keyboard_layout_lowercase[LIST_KEYBOARD_ROWS][LIST_KEYBOARD_COLS] = {
    {"q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "", "", "", ""},
    {"a", "s", "d", "f", "g", "h", "j", "k", "l", "", "", "", "", ""},
    {"123", "z", "x", "c", "v", "b", "n", "m", "space", "", "", "", "", ""}};

// keyboard_layout_uppercase is kept for API compatibility; the UI no longer
// exposes a shift key because search is case-insensitive.
static const char *keyboard_layout_uppercase[LIST_KEYBOARD_ROWS][LIST_KEYBOARD_COLS] = {
    {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "", "", "", ""},
    {"A", "S", "D", "F", "G", "H", "J", "K", "L", "", "", "", "", ""},
    {"123", "Z", "X", "C", "V", "B", "N", "M", "space", "", "", "", "", ""}};

// keyboard_layout_special is the number/symbol layout. abc sits where 123 was;
// there is no enter key, and space sits at the end of the symbol row.
static const char *keyboard_layout_special[LIST_KEYBOARD_ROWS][LIST_KEYBOARD_COLS] = {
    {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "", "", "", ""},
    {"-", "=", "[", "]", ";", "'", ",", ".", "/", "", "", "", "", ""},
    {"abc", "°", "•", "·", "†", "‡", "¬", "¦", "space", "", "", "", "", ""}};

// layout_for returns the table for a layout index, defaulting to lowercase for
// out-of-range values so callers always get a usable grid.
static const char *(*layout_for(int layout))[LIST_KEYBOARD_COLS]
{
    if (layout == 1)
        return keyboard_layout_uppercase;
    if (layout == 2)
        return keyboard_layout_special;
    return keyboard_layout_lowercase;
}

const char *ListKeyboard_KeyAt(int layout, int row, int col)
{
    if (row < 0 || row >= LIST_KEYBOARD_ROWS || col < 0 || col >= LIST_KEYBOARD_COLS)
        return "";
    return layout_for(layout)[row][col];
}

// count_row_length returns the number of non-empty cells in a row.
static int count_row_length(const char *(*layout)[LIST_KEYBOARD_COLS], int row)
{
    int length = 0;
    for (int i = 0; i < LIST_KEYBOARD_COLS; i++)
    {
        if (layout[row][i][0] != '\0')
            length++;
    }
    return length;
}

int ListKeyboard_RowLength(int layout, int row)
{
    if (row < 0 || row >= LIST_KEYBOARD_ROWS)
        return 0;
    return count_row_length(layout_for(layout), row);
}

// find_key_column returns the column of a named key in a row, or -1.
static int find_key_column(const char *(*layout)[LIST_KEYBOARD_COLS], int row, const char *key)
{
    for (int col = 0; col < LIST_KEYBOARD_COLS; col++)
    {
        if (strcmp(layout[row][col], key) == 0)
            return col;
    }
    return -1;
}

// calculate_column_offset returns the centering offset between two rows.
static int calculate_column_offset(const char *(*layout)[LIST_KEYBOARD_COLS], int from_row, int to_row)
{
    int from_length = count_row_length(layout, from_row);
    int to_length = count_row_length(layout, to_row);
    return (to_length - from_length) / 2;
}

// rescue snaps the cursor onto a valid, non-empty cell for its current row.
static void rescue(struct KeyboardCursor *cursor, const char *(*layout)[LIST_KEYBOARD_COLS])
{
    // clamp the row
    if (cursor->row < 0)
        cursor->row = 0;
    else if (cursor->row > LIST_KEYBOARD_ROWS - 1)
        cursor->row = LIST_KEYBOARD_ROWS - 1;

    // clamp the column
    if (cursor->col > LIST_KEYBOARD_COLS - 1)
        cursor->col = LIST_KEYBOARD_COLS - 1;

    // move left until we find a non-empty cell
    while (cursor->col >= 0 && layout[cursor->row][cursor->col][0] == '\0')
        cursor->col--;

    // if we went too far left, move right until we find a non-empty cell
    if (cursor->col < 0)
    {
        cursor->col = 0;
        while (layout[cursor->row][cursor->col][0] == '\0')
            cursor->col++;
    }
}

void ListKeyboard_Rescue(struct KeyboardCursor *cursor)
{
    rescue(cursor, layout_for(cursor->layout));
}

void ListKeyboard_Move(struct KeyboardCursor *cursor, enum ListKeyboardDir dir)
{
    const char *(*layout)[LIST_KEYBOARD_COLS] = layout_for(cursor->layout);
    const int max_row = LIST_KEYBOARD_ROWS;
    const int max_col = LIST_KEYBOARD_COLS;
    const int row0_length = count_row_length(layout, 0);
    const int row1_length = count_row_length(layout, 1);
    const int space_col = find_key_column(layout, 2, "space");

    // p (the last QWERTY key) sits above the empty cell that the J-shaped
    // space arm occupies. Moving down from p should target space, not l.
    if (dir == LIST_KEYBOARD_DOWN && cursor->row == 0 && space_col >= 0 &&
        cursor->col == row0_length - 1 && row1_length < row0_length)
    {
        cursor->row = 2;
        cursor->col = space_col;
        rescue(cursor, layout);
        return;
    }
    // Symmetric move: space up to p.
    if (dir == LIST_KEYBOARD_UP && cursor->row == 2 && space_col >= 0 &&
        cursor->col == space_col && row1_length < row0_length)
    {
        cursor->row = 0;
        cursor->col = row0_length - 1;
        rescue(cursor, layout);
        return;
    }

    if (dir == LIST_KEYBOARD_UP)
    {
        if (cursor->row > 0)
        {
            int offset = calculate_column_offset(layout, cursor->row, cursor->row - 1);
            cursor->col += offset;
            cursor->row--;
        }
        else
        {
            int offset = calculate_column_offset(layout, 0, max_row - 1);
            cursor->col += offset;
            cursor->row = max_row - 1;
        }
        rescue(cursor, layout);
    }
    else if (dir == LIST_KEYBOARD_DOWN)
    {
        if (cursor->row < max_row - 1)
        {
            int offset = calculate_column_offset(layout, cursor->row, cursor->row + 1);
            cursor->col += offset;
            cursor->row++;
        }
        else
        {
            int offset = calculate_column_offset(layout, max_row - 1, 0);
            cursor->col += offset;
            cursor->row = 0;
        }
        rescue(cursor, layout);
    }
    else if (dir == LIST_KEYBOARD_LEFT)
    {
        if (cursor->col > 0)
        {
            cursor->col--;
        }
        else
        {
            int last_col = max_col - 1;
            while (last_col >= 0 && layout[cursor->row][last_col][0] == '\0')
                last_col--;
            cursor->col = last_col;
        }
    }
    else if (dir == LIST_KEYBOARD_RIGHT)
    {
        const char *next_key = (cursor->col + 1 < max_col) ? layout[cursor->row][cursor->col + 1] : "";
        if (cursor->col + 1 >= max_col || *next_key == '\0')
            cursor->col = 0;
        else if (cursor->col < max_col - 1)
            cursor->col++;
    }
}

void ListKeyboard_CycleLayout(struct KeyboardCursor *cursor)
{
    cursor->layout = (cursor->layout + 1) % LIST_KEYBOARD_LAYOUTS;
    rescue(cursor, layout_for(cursor->layout));
}

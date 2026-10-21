// Unit tests for the pure filter-keyboard layout + cursor helpers. These have no
// SDL/display dependencies, so they run headless with the host compiler via
// `make test`.

#include "list_keyboard.h"

#include <stdio.h>
#include <string.h>

static int checks = 0;
static int failures = 0;

#define CHECK_EQ(actual, expected, msg)                                         \
    do                                                                          \
    {                                                                           \
        checks++;                                                               \
        long _a = (long)(actual);                                               \
        long _e = (long)(expected);                                             \
        if (_a != _e)                                                           \
        {                                                                       \
            failures++;                                                         \
            fprintf(stderr, "FAIL: %s (expected %ld, got %ld)\n", (msg), _e, _a); \
        }                                                                       \
    } while (0)

#define CHECK_STR(actual, expected, msg)                                        \
    do                                                                          \
    {                                                                           \
        checks++;                                                               \
        const char *_a = (actual);                                              \
        const char *_e = (expected);                                            \
        if (strcmp(_a, _e) != 0)                                                \
        {                                                                       \
            failures++;                                                         \
            fprintf(stderr, "FAIL: %s (expected \"%s\", got \"%s\")\n", (msg), _e, _a); \
        }                                                                       \
    } while (0)

static void test_key_at(void)
{
    CHECK_STR(ListKeyboard_KeyAt(0, 0, 0), "q", "keyat: lower row0 col0");
    CHECK_STR(ListKeyboard_KeyAt(0, 1, 0), "a", "keyat: lower row1 col0");
    CHECK_STR(ListKeyboard_KeyAt(0, 2, 0), "123", "keyat: 123 left of z");
    CHECK_STR(ListKeyboard_KeyAt(0, 2, 1), "z", "keyat: z right of 123");
    CHECK_STR(ListKeyboard_KeyAt(0, 1, 8), "l", "keyat: l at end of row1");
    CHECK_STR(ListKeyboard_KeyAt(0, 1, 9), "", "keyat: empty after l");
    CHECK_STR(ListKeyboard_KeyAt(0, 2, 8), "space", "keyat: space next to m");
    CHECK_STR(ListKeyboard_KeyAt(1, 0, 0), "Q", "keyat: upper row0 col0");
    CHECK_STR(ListKeyboard_KeyAt(2, 0, 0), "1", "keyat: special row0 col0");
    CHECK_STR(ListKeyboard_KeyAt(2, 2, 0), "abc", "keyat: special abc left of symbols");
    CHECK_STR(ListKeyboard_KeyAt(2, 2, 8), "space", "keyat: special space");
    // empty cells and out-of-range coordinates return ""
    CHECK_STR(ListKeyboard_KeyAt(0, 0, 10), "", "keyat: empty cell");
    CHECK_STR(ListKeyboard_KeyAt(0, 3, 0), "", "keyat: row out of range");
    CHECK_STR(ListKeyboard_KeyAt(0, -1, 0), "", "keyat: negative row");
    CHECK_STR(ListKeyboard_KeyAt(0, 0, 99), "", "keyat: col out of range");
}

static void test_row_length(void)
{
    CHECK_EQ(ListKeyboard_RowLength(0, 0), 10, "rowlen: lower row0");
    CHECK_EQ(ListKeyboard_RowLength(0, 1), 9, "rowlen: lower row1");
    CHECK_EQ(ListKeyboard_RowLength(0, 2), 9, "rowlen: lower row2");
    CHECK_EQ(ListKeyboard_RowLength(0, 3), 0, "rowlen: out of range");
}

// move applies a single step and returns the key now under the cursor.
static const char *move(struct KeyboardCursor *c, enum ListKeyboardDir dir)
{
    ListKeyboard_Move(c, dir);
    return ListKeyboard_KeyAt(c->layout, c->row, c->col);
}

static void test_left_right_wrap(void)
{
    struct KeyboardCursor c = {.row = 1, .col = 0, .layout = 0};
    // left from col0 wraps to the last non-empty cell (row1 length 9 -> col8 = "l")
    CHECK_STR(move(&c, LIST_KEYBOARD_LEFT), "l", "left: wrap to last non-empty");
    CHECK_EQ(c.col, 8, "left: wrapped column");
    // right from the last non-empty cell wraps back to col0
    CHECK_STR(move(&c, LIST_KEYBOARD_RIGHT), "a", "right: wrap to first");
    CHECK_EQ(c.col, 0, "right: wrapped column");
    // right mid-row advances by one
    CHECK_STR(move(&c, LIST_KEYBOARD_RIGHT), "s", "right: advance");
}

static void test_up_down_transitions(void)
{
    // down from (0,0) lands on row1 "a"
    struct KeyboardCursor c = {.row = 0, .col = 0, .layout = 0};
    CHECK_STR(move(&c, LIST_KEYBOARD_DOWN), "a", "down: (0,0)->a");
    CHECK_EQ(c.row, 1, "down: row advanced");

    // down from the bottom row wraps back to the top row
    c = (struct KeyboardCursor){.row = 2, .col = 0, .layout = 0};
    CHECK_STR(move(&c, LIST_KEYBOARD_DOWN), "q", "down: bottom wraps to q");
    CHECK_EQ(c.row, 0, "down: wrapped to top row");

    // up from the bottom row returns to row1 "a"
    c = (struct KeyboardCursor){.row = 2, .col = 0, .layout = 0};
    CHECK_STR(move(&c, LIST_KEYBOARD_UP), "a", "up: 123->a");
    CHECK_EQ(c.row, 1, "up: row decreased");

    // down from p targets the J-shaped space key, not l
    c = (struct KeyboardCursor){.row = 0, .col = 9, .layout = 0};
    CHECK_STR(move(&c, LIST_KEYBOARD_DOWN), "space", "down: p->space");
    CHECK_EQ(c.row, 2, "down: p reaches space row");
    // and space moves back up to p
    CHECK_STR(move(&c, LIST_KEYBOARD_UP), "p", "up: space->p");
    CHECK_EQ(c.row, 0, "up: space reaches top row");

    // up from the top row wraps to the bottom row
    c = (struct KeyboardCursor){.row = 0, .col = 0, .layout = 0};
    CHECK_STR(move(&c, LIST_KEYBOARD_UP), "123", "up: wrap to 123");
    CHECK_EQ(c.row, 2, "up: wrapped to last row");
}

// test_never_empty walks the cursor through many steps and asserts it never
// lands on an empty cell, from every layout.
static void test_never_empty(void)
{
    enum ListKeyboardDir dirs[] = {LIST_KEYBOARD_DOWN, LIST_KEYBOARD_RIGHT,
                                   LIST_KEYBOARD_UP, LIST_KEYBOARD_LEFT,
                                   LIST_KEYBOARD_DOWN, LIST_KEYBOARD_DOWN,
                                   LIST_KEYBOARD_RIGHT, LIST_KEYBOARD_RIGHT};
    for (int layout = 0; layout < LIST_KEYBOARD_LAYOUTS; layout++)
    {
        struct KeyboardCursor c = {.row = 0, .col = 0, .layout = layout};
        for (int i = 0; i < 40; i++)
        {
            ListKeyboard_Move(&c, dirs[i % 8]);
            checks++;
            const char *key = ListKeyboard_KeyAt(c.layout, c.row, c.col);
            if (key[0] == '\0')
            {
                failures++;
                fprintf(stderr, "FAIL: never-empty landed on empty (layout %d, step %d, row %d, col %d)\n",
                        layout, i, c.row, c.col);
                break;
            }
        }
    }
}

static void test_cycle_layout(void)
{
    struct KeyboardCursor c = {.row = 1, .col = 0, .layout = 0};
    ListKeyboard_CycleLayout(&c);
    CHECK_EQ(c.layout, 1, "cycle: 0->1");
    ListKeyboard_CycleLayout(&c);
    CHECK_EQ(c.layout, 2, "cycle: 1->2");
    ListKeyboard_CycleLayout(&c);
    CHECK_EQ(c.layout, 0, "cycle: 2->0 wraps");
    // after cycling, the cursor is still on a non-empty cell
    CHECK_EQ(ListKeyboard_KeyAt(c.layout, c.row, c.col)[0] != '\0', 1, "cycle: cursor valid");
}

static void test_rescue(void)
{
    // an out-of-range cursor is snapped back onto a real key
    struct KeyboardCursor c = {.row = 2, .col = 13, .layout = 0};
    ListKeyboard_Rescue(&c);
    CHECK_EQ(ListKeyboard_KeyAt(c.layout, c.row, c.col)[0] != '\0', 1, "rescue: lands on non-empty");
    CHECK_EQ(c.col <= 8, 1, "rescue: column clamped into row2 range");
    CHECK_STR(ListKeyboard_KeyAt(c.layout, c.row, c.col), "space", "rescue: lands on space");
}

int main(void)
{
    test_key_at();
    test_row_length();
    test_left_right_wrap();
    test_up_down_transitions();
    test_never_empty();
    test_cycle_layout();
    test_rescue();

    if (failures == 0)
    {
        printf("ok - all %d checks passed\n", checks);
        return 0;
    }

    fprintf(stderr, "not ok - %d/%d checks failed\n", failures, checks);
    return 1;
}

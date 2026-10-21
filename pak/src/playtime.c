// romoogle-playtime: print total play time (seconds) for a ROM path.
//
// The NextUI game tracker stores paths relative to Roms/ in
// .userdata/shared/game_logs.sqlite. For a multi-disc game launched through an
// m3u, the tracker may have recorded the individual disc paths, so a path with
// a game folder also matches that folder's prefix.
//
// Usage: romoogle-playtime <path-relative-to-Roms>
// Set ROMOOGLE_GAME_LOGS to override the database location.

#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int count_slashes(const char *s)
{
    int count = 0;
    for (; *s != '\0'; s++)
    {
        if (*s == '/')
            count++;
    }
    return count;
}

int main(int argc, char **argv)
{
    if (argc != 2)
        return 1;

    const char *relative_path = argv[1];
    const char *database = getenv("ROMOOGLE_GAME_LOGS");
    if (database == NULL || database[0] == '\0')
        database = "/mnt/SDCARD/.userdata/shared/game_logs.sqlite";

    sqlite3 *handle = NULL;
    if (sqlite3_open_v2(database, &handle, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK)
    {
        if (handle != NULL)
            sqlite3_close(handle);
        return 2;
    }

    const char *sql =
        "SELECT COALESCE(SUM(pa.play_time), 0) "
        "FROM rom r JOIN play_activity pa ON pa.rom_id = r.id "
        "WHERE r.file_path = ?1 OR r.file_path LIKE ?2";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(handle, sql, -1, &statement, NULL) != SQLITE_OK)
    {
        sqlite3_close(handle);
        return 3;
    }

    sqlite3_bind_text(statement, 1, relative_path, -1, SQLITE_TRANSIENT);

    char pattern[1024];
    pattern[0] = '\1';
    pattern[1] = '\0';
    if (count_slashes(relative_path) >= 2)
    {
        const char *last_slash = strrchr(relative_path, '/');
        size_t prefix_length = (size_t)(last_slash - relative_path) + 1;
        if (prefix_length + 2 < sizeof(pattern))
        {
            memcpy(pattern, relative_path, prefix_length);
            pattern[prefix_length] = '%';
            pattern[prefix_length + 1] = '\0';
        }
    }
    sqlite3_bind_text(statement, 2, pattern, -1, SQLITE_TRANSIENT);

    int seconds = 0;
    if (sqlite3_step(statement) == SQLITE_ROW)
        seconds = sqlite3_column_int(statement, 0);

    sqlite3_finalize(statement);
    sqlite3_close(handle);
    printf("%d\n", seconds);
    return 0;
}

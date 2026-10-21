#include "list_fuzzy.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#define FUZZY_MAX_CHARS 512

static unsigned char lower_byte(unsigned char c)
{
    return (unsigned char)tolower(c);
}

static bool is_token_char(unsigned char c)
{
    return isalnum(c) != 0;
}

// next_token lowercases and returns the next alphanumeric token, advancing *pp.
static bool next_token(const char **pp, char *out, size_t out_size)
{
    const char *p = *pp;
    while (*p != '\0' && !is_token_char((unsigned char)*p))
        p++;
    if (*p == '\0')
    {
        *pp = p;
        return false;
    }

    size_t n = 0;
    while (*p != '\0' && is_token_char((unsigned char)*p))
    {
        if (n + 1 < out_size)
            out[n++] = (char)lower_byte((unsigned char)*p);
        p++;
    }
    out[n] = '\0';
    *pp = p;
    return true;
}

bool Fuzzy_Contains(const char *haystack, const char *needle)
{
    if (needle == NULL || needle[0] == '\0')
        return true;
    if (haystack == NULL)
        return false;

    size_t n = strlen(needle);
    for (const char *p = haystack; *p != '\0'; p++)
    {
        size_t i = 0;
        while (i < n && p[i] != '\0' &&
               lower_byte((unsigned char)p[i]) == lower_byte((unsigned char)needle[i]))
            i++;
        if (i == n)
            return true;
    }
    return false;
}

bool Fuzzy_MatchesAll(const char *haystack, const char *query)
{
    if (query == NULL || query[0] == '\0')
        return true;
    if (haystack == NULL)
        return false;

    const char *p = query;
    char token[256];
    while (next_token(&p, token, sizeof(token)))
    {
        if (!Fuzzy_Contains(haystack, token))
            return false;
    }
    return true;
}

static bool starts_with_ci(const char *haystack, const char *needle)
{
    if (needle[0] == '\0')
        return true;
    for (size_t i = 0; needle[i] != '\0'; i++)
    {
        if (haystack[i] == '\0' ||
            lower_byte((unsigned char)haystack[i]) != lower_byte((unsigned char)needle[i]))
            return false;
    }
    return true;
}

int Fuzzy_Rank(const char *haystack, const char *query)
{
    if (haystack == NULL || query == NULL || query[0] == '\0')
        return 2;

    // Ignore a display tag such as "[GBA] " when judging prefixes.
    const char *title = haystack;
    if (title[0] == '[')
    {
        const char *close = strchr(title, ']');
        if (close != NULL)
        {
            title = close + 1;
            while (*title == ' ')
                title++;
        }
    }

    int total = 0;
    int query_index = 0;
    const char *qp = query;
    char query_token[256];
    while (next_token(&qp, query_token, sizeof(query_token)))
    {
        int best = 2;
        const char *tp = title;
        char title_token[256];
        bool first = true;
        while (next_token(&tp, title_token, sizeof(title_token)))
        {
            if (starts_with_ci(title_token, query_token))
            {
                best = first ? 0 : 1;
                break;
            }
            first = false;
        }
        if (best == 2 && !Fuzzy_Contains(title, query_token))
            return 2;
        // The first query token dominates, so "sup mar" prefers "Super Mario"
        // over a title where "mar" happens to be the first word.
        total += (query_index == 0) ? best * 4 : best;
        query_index++;
    }
    return total;
}

int Fuzzy_Distance(const char *a, const char *b, int max_distance)
{
    if (a == NULL || b == NULL || max_distance < 0)
        return max_distance + 1;

    int n = (int)strlen(a);
    int m = (int)strlen(b);
    if (n >= FUZZY_MAX_CHARS || m >= FUZZY_MAX_CHARS)
        return max_distance + 1;
    if (abs(n - m) > max_distance)
        return max_distance + 1;

    int prev_buf[FUZZY_MAX_CHARS];
    int curr_buf[FUZZY_MAX_CHARS];
    int prev2_buf[FUZZY_MAX_CHARS];
    int *prev = prev_buf;
    int *curr = curr_buf;
    int *prev2 = prev2_buf;

    for (int j = 0; j <= m; j++)
    {
        prev[j] = j;
        prev2[j] = j;
    }

    for (int i = 1; i <= n; i++)
    {
        curr[0] = i;
        int row_min = i;

        for (int j = 1; j <= m; j++)
        {
            int cost = lower_byte((unsigned char)a[i - 1]) != lower_byte((unsigned char)b[j - 1]);
            int value = prev[j] + 1;
            if (curr[j - 1] + 1 < value)
                value = curr[j - 1] + 1;
            if (prev[j - 1] + cost < value)
                value = prev[j - 1] + cost;

            if (i > 1 && j > 1 &&
                lower_byte((unsigned char)a[i - 1]) == lower_byte((unsigned char)b[j - 2]) &&
                lower_byte((unsigned char)a[i - 2]) == lower_byte((unsigned char)b[j - 1]))
            {
                if (prev2[j - 2] + 1 < value)
                    value = prev2[j - 2] + 1;
            }

            curr[j] = value;
            if (value < row_min)
                row_min = value;
        }

        if (row_min > max_distance)
            return max_distance + 1;

        int *tmp = prev2;
        prev2 = prev;
        prev = curr;
        curr = tmp;
    }

    return prev[m];
}

static int token_threshold(int length)
{
    if (length < 3)
        return 0;
    if (length <= 5)
        return 1;
    if (length <= 9)
        return 2;
    return 3;
}

int Fuzzy_TokenMatch(const char *title, const char *query, int forced_max)
{
    if (title == NULL || query == NULL || query[0] == '\0')
        return -1;

    int total = 0;
    const char *qp = query;
    char query_token[256];

    while (next_token(&qp, query_token, sizeof(query_token)))
    {
        int query_length = (int)strlen(query_token);
        if (query_length < 3)
        {
            // Short tokens are too noisy to fuzzy-match; require them exactly.
            if (!Fuzzy_Contains(title, query_token))
                return -1;
            continue;
        }

        int max_distance = token_threshold(query_length);
        if (forced_max > 0 && forced_max < max_distance)
            max_distance = forced_max;

        int best = max_distance + 1;
        const char *tp = title;
        char title_token[256];
        while (next_token(&tp, title_token, sizeof(title_token)))
        {
            int title_length = (int)strlen(title_token);
            if (abs(title_length - query_length) > max_distance)
                continue;

            if (strcmp(query_token, title_token) == 0)
            {
                best = 0;
                break;
            }

            int distance = Fuzzy_Distance(query_token, title_token, max_distance);
            if (distance < best)
                best = distance;
            if (best == 0)
                break;
        }

        if (best > max_distance)
            return -1;
        total += best;
    }

    return total;
}

#ifndef LIST_FUZZY_H
#define LIST_FUZZY_H

#include <stdbool.h>

// Case-insensitive literal substring.
bool Fuzzy_Contains(const char *haystack, const char *needle);

// Every whitespace-separated token in query must appear (case-insensitive)
// somewhere in haystack.
bool Fuzzy_MatchesAll(const char *haystack, const char *query);

// Relevance for a query token or token set: 0 = the first title word starts
// with it, 1 = a later word starts with it, 2 = anywhere else. Multi-token
// queries weight the first query token more heavily.
int Fuzzy_Rank(const char *haystack, const char *query);

// Bounded Damerau-Levenshtein (optimal string alignment) distance. Returns
// max_distance + 1 when the distance exceeds the bound, or on invalid input.
int Fuzzy_Distance(const char *a, const char *b, int max_distance);

// Token-level fuzzy match. Each query token must match a title token within a
// length-dependent distance (1 for 3-5 chars, 2 for 6-9, 3 for 10+).
// forced_max > 0 clamps the per-token threshold. Returns the total distance,
// or -1 when the title does not match.
int Fuzzy_TokenMatch(const char *title, const char *query, int forced_max);

#endif // LIST_FUZZY_H

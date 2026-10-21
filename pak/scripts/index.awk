BEGIN { FS = "\t"; OFS = "\t" }

# First file: full path -> display alias (or __HIDE__).
FNR == NR {
    alias[$1] = $2;
    next;
}

{
    path = $1;
    display = $2;
    filename = $3;
    tag = $4;
    sys = $5;
    system_alias = $6;
    discs = $7 + 0;
    art = $8;

    if (path in alias) {
        a = alias[path];
        if (a == "__HIDE__")
            next;
        display = a;
    }
    if (discs < 1)
        discs = 1;

    name = "[" tag "] " display;
    if (discs > 1)
        name = name " · " discs " discs";

    # Fuzzy title: drop the extension and region/revision tags, then fold.
    fuzzy = display;
    sub(/\.[^.\/]*$/, "", fuzzy);
    gsub(/\([^)]*\)/, " ", fuzzy);
    gsub(/\[[^]]*\]/, " ", fuzzy);
    fuzzy = fold(fuzzy);

    # Primary search text is the title/alias and the filename without its
    # extension. System tags, system names, folders, and paths are intentionally
    # excluded: typing "GB" must not match every [GB] row.
    title = display;
    sub(/\.[^.\/]*$/, "", title);
    rawtitle = filename;
    sub(/\.[^.\/]*$/, "", rawtitle);
    search = title " " rawtitle;
    search = fold(search);

    print path, name, search, fuzzy, discs, art;
}

# fold lowercases and turns punctuation/whitespace into single spaces, while
# folding common Latin accents so "pokemon" matches "Pokémon".
function fold(s,    t) {
    gsub(/á|à|â|ä|ã|å|ā/, "a", s);
    gsub(/é|è|ê|ë|ē/, "e", s);
    gsub(/í|ì|î|ï|ī/, "i", s);
    gsub(/ó|ò|ô|ö|õ|ø|ō/, "o", s);
    gsub(/ú|ù|û|ü|ū/, "u", s);
    gsub(/ç/, "c", s);
    gsub(/ñ/, "n", s);
    gsub(/ý|ÿ/, "y", s);
    gsub(/ß/, "ss", s);
    gsub(/æ/, "ae", s);
    gsub(/œ/, "oe", s);
    gsub(/Á|À|Â|Ä|Ã|Å|Ā/, "a", s);
    gsub(/É|È|Ê|Ë|Ē/, "e", s);
    gsub(/Í|Ì|Î|Ï|Ī/, "i", s);
    gsub(/Ó|Ò|Ô|Ö|Õ|Ø|Ō/, "o", s);
    gsub(/Ú|Ù|Û|Ü|Ū/, "u", s);
    gsub(/Ç/, "c", s);
    gsub(/Ñ/, "n", s);
    gsub(/Ý|Ÿ/, "y", s);
    gsub(/Æ/, "ae", s);
    gsub(/Œ/, "oe", s);

    s = tolower(s);
    gsub(/[][(){}.,:;!?'"\/\\|&+*^%$#@~`=_<>-]+/, " ", s);
    gsub(/[[:space:]]+/, " ", s);
    sub(/^ /, "", s);
    sub(/ $/, "", s);
    return s;
}

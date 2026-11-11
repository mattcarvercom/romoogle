BEGIN { FS = "\t"; OFS = "\t"

    # Pinyin table: <hanzi>\t<readings> (see pak/scripts/pinyin.tsv).
    if (pyfile != "") {
        while ((getline pline < pyfile) > 0) {
            sub(/\r$/, "", pline)
            if (pline == "" || substr(pline, 1, 1) == "#")
                continue
            split(pline, pf, "\t")
            if (pf[1] == "" || pf[2] == "")
                continue
            PY_TABLE[pf[1]] = pf[2]
            if (!PY_PROBED) {
                # Byte-oriented awk (busybox/mawk) sees a 3-byte hanzi as
                # length 3; char-oriented awk (gawk in a UTF-8 locale) as 1.
                PY_PROBED = 1
                PY_BYTEMODE = (length(pf[1]) == 3) ? 1 : 0
            }
        }
        close(pyfile)
    }

    # Pinyin tokens must never equal a system key or file extension: the
    # search fields must not make "gb" match a game whose title merely
    # starts with g/b (and the same for ROM extensions).
    split("", PY_DROP)
    nd = split(tolower(syskeys), pdv, /[ \t]+/)
    for (pd = 1; pd <= nd; pd++)
        if (pdv[pd] != "")
            PY_DROP[pdv[pd]] = 1
    nd = split("7z zip rar iso cue chd bin img mdf nrg pbp cso gdi cdi gb gbc gba nes fds snes smc sfc md gen sms gg n64 z64 v64 nds 3ds cia psp rvz wux wud elf dax vb ws wsc lynx a26 a52 a78 col vec ngp ngc pce sat dc gcm ccd mds", pdv, /[ \t]+/)
    for (pd = 1; pd <= nd; pd++)
        if (pdv[pd] != "")
            PY_DROP[pdv[pd]] = 1
}

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

    # Pinyin keys (initials + full pinyin, polyphones expanded) are appended
    # after fold: the C matcher needs zero changes, it just sees more ASCII
    # searchable text. No hanzi in the source means no keys. PY_SEEN is
    # shared across calls so a title that repeats in the filename (or alias
    # and filename that agree) contributes its tokens only once.
    if (PY_PROBED) {
        pyt = title
        pyr = rawtitle
        gsub(/\([^)]*\)/, " ", pyt)
        gsub(/\[[^]]*\]/, " ", pyt)
        gsub(/\([^)]*\)/, " ", pyr)
        gsub(/\[[^]]*\]/, " ", pyr)
        split("", PY_SEEN)
        pyk = pinyin_keys(pyt)
        pyk = pyk pinyin_keys(pyr)
        if (pyk != "")
            search = search pyk
        split("", PY_SEEN)
        pyk = pinyin_keys(fuzzy)
        if (pyk != "")
            fuzzy = fuzzy pyk
    }

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

# Space-separated pinyin tokens for the hanzi in s: for each polyphone
# combination an initials token and a concatenated full-pinyin token, with
# ASCII alnum carried through ("zzhx7" matches 最终幻想7). Returns "" when s
# contains no hanzi. Tokens equal to a system key or ROM extension are
# dropped, and tokens already emitted for this item (PY_SEEN, reset by the
# caller) are skipped. Combinations are capped at 16 by reducing the widest
# reading sets to their first (most common) reading.
function pinyin_keys(s,    i, n, c, t3, pn, prod, j, k, t, na, r, a, cf, ci, nf, ni, ncf, nn, tok, out, han, widest, widest_j, pass) {
    split("", PY_RDS)
    pn = 0
    han = 0
    n = length(s)
    i = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (PY_BYTEMODE) {
            t3 = substr(s, i, 3)
            if (length(t3) == 3 && (t3 in PY_TABLE)) {
                PY_RDS[++pn] = PY_TABLE[t3]
                han = 1
                i += 3
                continue
            }
        } else if (c in PY_TABLE) {
            PY_RDS[++pn] = PY_TABLE[c]
            han = 1
            i++
            continue
        }
        if (c ~ /[A-Za-z0-9]/) {
            PY_RDS[++pn] = tolower(c)
            i++
            continue
        }
        i++
    }
    if (!han)
        return ""

    while (1) {
        prod = 1
        for (j = 1; j <= pn; j++) {
            na = split(PY_RDS[j], a, ",")
            prod *= na
        }
        if (prod <= 16)
            break
        widest = 0
        for (j = 1; j <= pn; j++) {
            na = split(PY_RDS[j], a, ",")
            if (na > widest) {
                widest = na
                widest_j = j
            }
        }
        if (widest <= 1)
            break
        split(PY_RDS[widest_j], a, ",")
        PY_RDS[widest_j] = a[1]
    }

    ncf = 1
    cf[1] = ""
    ci[1] = ""
    for (j = 1; j <= pn; j++) {
        na = split(PY_RDS[j], a, ",")
        nn = 0
        for (t = 1; t <= ncf; t++) {
            for (k = 1; k <= na; k++) {
                r = a[k]
                nn++
                nf[nn] = cf[t] r
                ni[nn] = ci[t] substr(r, 1, 1)
            }
        }
        ncf = nn
        for (t = 1; t <= ncf; t++) {
            cf[t] = nf[t]
            ci[t] = ni[t]
        }
    }

    out = ""
    for (t = 1; t <= ncf; t++) {
        for (pass = 1; pass <= 2; pass++) {
            tok = (pass == 1) ? ci[t] : cf[t]
            if (tok == "" || (tok in PY_SEEN) || (tok in PY_DROP))
                continue
            PY_SEEN[tok] = 1
            out = out " " tok
        }
    }
    return out
}

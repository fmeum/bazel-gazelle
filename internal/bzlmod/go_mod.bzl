def parse_go_mod(content, path):
    # See https://go.dev/ref/mod#go-mod-file.

    # Valid directive values understood by this parser never contain tabs or
    # carriage returns, so we can simplify the parsing below by canonicalizing
    # whitespace upfront.
    content = content.replace("\t", " ").replace("\r", " ")

    state = {
        "module": None,
        "go": None,
        "require": [],
    }

    current_directive = None
    for line_no, line in enumerate(content.splitlines(), 1):
        tokens, comment = _tokenize_line(line, path, line_no)
        if not tokens:
            continue

        if not current_directive:
            if tokens[0] not in ["module", "go", "require", "replace", "exclude", "retract"]:
                fail("{}:{}: unexpected token '{}' at start of line".format(path, line_no, tokens[0]))
            if len(tokens) == 1:
                fail("{}:{}: expected another token after '{}'".format(path, line_no, tokens[0]))

            # The 'go' directive only has a single-line form and is thus parsed
            # here rather than in _parse_directive.
            if tokens[0] == "go":
                if len(tokens) == 1:
                    fail("{}:{}: expected another token after 'go'".format(path, line_no))
                if state["go"] != None:
                    fail("{}:{}: unexpected second 'go' directive".format(path, line_no))
                state["go"] = tokens[1]
                if len(tokens) > 2:
                    fail("{}:{}: unexpected token '{}' after '{}'".format(path, line_no, tokens[2], tokens[1]))

            if tokens[1] == "(":
                current_directive = tokens[0]
                if len(tokens) > 2:
                    fail("{}:{}: unexpected token '{}' after '('".format(path, line_no, tokens[2]))
                continue

            _parse_directive(state, tokens[0], tokens[1:], comment, path, line_no)

        elif tokens[0] == ")":
            current_directive = None
            if len(tokens) > 1:
                fail("{}:{}: unexpected token '{}' after ')'".format(path, line_no, tokens[1]))
            continue

        else:
            _parse_directive(state, current_directive, tokens, comment, path, line_no)

    module = state["module"]
    if not module:
        fail("Expected a module directive in go.mod file")

    go = state["go"]
    if not go:
        # "As of the Go 1.17 release, if the go directive is missing, go 1.16 is assumed."
        go = "1.16"
    major, minor = go.split(".")

    return struct(
        module = module,
        go = (int(major), int(minor)),
        require = tuple(state["require"]),
    )

def _parse_directive(state, directive, tokens, comment, path, line_no):
    if directive == "module":
        if state["module"] != None:
            fail("{}:{}: unexpected second 'module' directive".format(path, line_no))
        if len(tokens) > 1:
            fail("{}:{}: unexpected token '{}' after '{}'".format(path, line_no, tokens[1]))
        state["module"] = tokens[0]
    elif directive == "require":
        if len(tokens) != 2:
            fail("{}:{}: expected module path and version in 'require' directive".format(path, line_no))
        state["require"].append(struct(
            path = tokens[0],
            version = tokens[1],
            direct = comment != "indirect",
        ))

    # TODO: Handle exclude and replace.

def _tokenize_line(line, path, line_no):
    tokens = []
    r = line
    for _ in range(len(line)):
        r = r.strip()
        if not r:
            break

        if r[0] == "`":
            end = r.find("`", 1)
            if end == -1:
                fail("{}:{}: unterminated raw string".format(path, line_no))

            tokens.append(r[1:end])
            r = r[end + 1:]

        elif r[0] == "\"":
            value = ""
            escaped = False
            found_end = False
            for pos in range(1, len(r)):
                c = r[pos]

                if escaped:
                    value += c
                    escaped = False
                    continue

                if c == "\\":
                    escaped = True
                    continue

                if c == "\"":
                    found_end = True
                    break

                value += c

            if not found_end:
                fail("{}:{}: unterminated interpreted string".format(path, line_no))

            tokens.append(value)
            r = r[pos + 1:]

        elif r.startswith("//"):
            # A comment always ends the current line
            return tokens, r[len("//"):].strip()

        else:
            token, _, r = r.partition(" ")
            tokens.append(token)

    return tokens, None

def parse_go_sum(content):
    hashes = {}
    for line in content.splitlines():
        path, version, sum = line.split(" ")
        if not version.endswith("/go.mod"):
            hashes[(path, version)] = sum
    return hashes

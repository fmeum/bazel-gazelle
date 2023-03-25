def which(program, *, preset):
    if "/" in program or "\\" in program:
        fail("Program argument of which() may not contain a / or a \ ('%s' given)" % program)
    if not program:
        fail("Program argument of which() may not be empty")

    for ext in preset.executable_extensions:



FileInfo = provider(
    fields = {
        "executable": "A function describing the runtime behavior of this executable file.",
        "text": "The text content of the file as a string, or None if the file is not a text file.",
    },
)

_DIR_TYPE = type({})

def _normalize(path):
    segments = path.split("/")
    root = segments[0]
    new_segments = []

    for segment in segments[1:]:
        if segment == "..":
            if new_segments:
                new_segments.pop()
        elif segment and segment != ".":
            new_segments.append(segment)

    return "/".join([root] + new_segments)

# /home/fhenneke/.cache/bazel/_bazel_fhenneke/466e6feac151a1e22847383f4e503362/modextwd/gazelle~override~go_deps
# Cannot write outside of the repository directory for path /tmp/foobar
def _new(is_root, working_directory):
    def is_absolute(path):
        return is_root(path.partition("/")[0])

    if not is_absolute(working_directory):
        fail("working_directory must be absolute: " + working_directory)

    mem = {}
    all_paths = {}

    def get(path):
        entry = mem
        segments = path.__str__().split("/")
        for i, segment in enumerate(segments):
            if type(entry) != _DIR_TYPE:
                fail("Not a directory: " + "/".join(segments[:i + 1]))
            if segment not in entry:
                return None
            entry = entry[segment]
        return entry

    def set(path, value):
        dirname, _, basename = path.rpartition("/")
        if not basename:
            fail("Not a file: " + path)
        segments = dirname.split("/")
        entry = mem
        for i, segment in enumerate(segments):
            if type(entry) != _DIR_TYPE:
                fail("Not a directory: " + "/".join(segments[:i + 1]))
            entry = entry.setdefault(segment, {})
        if basename in entry and type(entry[basename]) == _DIR_TYPE:
            fail("Not a file: " + path)
        entry[basename] = value

    def make_path(path_str):
        if not is_absolute(path_str):
            path_str = working_directory + "/" + path_str
        path_str = _normalize(path_str)

        segments = path_str.split("/")
        path_str_prefix = ""
        path = None
        for segment in segments:
            path_str_prefix += segment
            path = _make_path(path_str_prefix, path)
            path_str_prefix += "/"

        return path

    def _make_path(path_str, dirname):
        if path_str in all_paths:
            return all_paths[path_str]

        def _get_child(*paths):
            child_path = "/".join(paths)
            if is_absolute(child_path):
                return make_path(child_path)
            else:
                return make_path(path_str + "/" + child_path)

        def _readdir():
            entry = get(path_str)
            if type(entry) != _DIR_TYPE:
                fail(path_str + " (Not a directory)")
            return [make_path(path_str + "/" + name) for name in entry.keys()]

        def _realpath():
            return self

        def __str__():
            return path_str

        self = struct(
            basename = path_str.rpartition("/")[2],
            dirname = dirname,
            exists = [True] if get(path_str) != None else [],
            get_child = _get_child,
            readdir = _readdir,
            realpath = _realpath,
            __str__ = __str__,
        )
        all_paths[path_str] = self
        return self

    return struct(
        get = get,
        set = set,
        make_path = make_path,
    )

fs = struct(
    new = _new,
)

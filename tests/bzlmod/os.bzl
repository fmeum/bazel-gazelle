_MockPreset = provider(
    fields = [
        "arch",
        "name",
        "is_root",
        "working_directory",
        "path_list_separator",
        "environ",
        "executable_extensions",
    ],
)

_LINUX_EXTERNAL_DIRECTORY = "/home/user/.cache/bazel/_bazel_user/0123456789abcdef0123456789abcdef/external"
_LINUX_WORKING_DIRECTORY = "/home/user/.cache/bazel/_bazel_user/0123456789abcdef0123456789abcdef/modextwd/my_module~1.2.3~my_extension"
_LINUX_WORKSPACE_DIRECTORY = "/home/user/my_workspace"

_UNIX_IS_ROOT = lambda s: s == ""

LINUX_AMD64_PRESET = _MockPreset(
    name = "Linux",
    arch = "arm64",
    environ = {
        "HOME": "/home/user",
        "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "PWD": _LINUX_WORKING_DIRECTORY,
        "USER": "user",
        "USERNAME": "user",
    },
    is_root = _UNIX_IS_ROOT,
    path_list_separator = ":",
    working_directory = _LINUX_WORKING_DIRECTORY,
    executable_extensions = [""],
)

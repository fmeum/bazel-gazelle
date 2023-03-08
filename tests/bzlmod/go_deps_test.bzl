load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//internal/bzlmod:go_deps.bzl", "go_deps_impl")
load(":test_module_extension.bzl", "module", "module_extension_test", "tag")
load(":fs.bzl", "fs")

suite_builder = module_extension_test.suite_builder(
    go_deps_impl,
    repository_rules = ["go_repository", "_go_repository_directives"],
    tag_class_defaults = {
        "config": {},
        "from_file": {},
        "module": {
            "path": "",
            "version": "",
            "sum": "",
            "build_naming_convention": "import",
            "build_file_proto_mode": "default",
        },
    },
)

def _go_deps_with_no_tags_passes(env, result):
    print(result)

suite_builder.add_test(
    _go_deps_with_no_tags_passes,
    modules = [module("foo", "1.2.3", [])],
)

suite_builder.add_failure_test(
    "go_deps_with_duplicate_module_path",
    modules = [module("foo", "1.2.3", [
        tag("module", path = "example.com/foo", version = "1.2.3"),
        tag("module", path = "example.com/foo", version = "4.5.6"),
    ])],
    failure_contains = "Duplicate Go module path 'example.com/foo' in module 'foo'",
)

go_deps_test_suite, _1_test, _2_test = suite_builder.build()

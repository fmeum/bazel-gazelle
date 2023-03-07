load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//internal/bzlmod:go_deps.bzl", "go_deps_impl")
load(":test_module_extension.bzl", "module", "module_extension_test", "tag")
load(":fs.bzl", "fs")

GO_DEPS_TEST_CONFIG = module_extension_test.make_config(
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

_go_deps_with_no_tags_passes_test = GO_DEPS_TEST_CONFIG.make_test(
    _go_deps_with_no_tags_passes,
    [module("foo", "1.2.3", [])],
)

go_deps_with_duplicate_module_tag_fails, _failing_rule_1 = GO_DEPS_TEST_CONFIG.make_failure_test(
    [module("foo", "1.2.3", [
        tag("module", path = "example.com/foo", version = "1.2.3"),
        tag("module", path = "example.com/foo", version = "4.5.6"),
    ])],
    expected_failure_msg = "Duplicate Go module path 'example.com/foo' in module 'foo'",
)

def go_deps_test_suite(name):
    unittest.suite(
        name,
        _go_deps_with_no_tags_passes_test,
    )

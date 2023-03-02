load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//internal/bzlmod:go_deps.bzl", "go_deps_impl")
load(":test_module_extension.bzl", "module", "module_extension_test")

def _go_deps_test_impl(ctx):
    env = unittest.begin(ctx)
    result = module_extension_test(
        env,
        go_deps_impl,
        modules = [module("foo", "1.2.3", dict(from_file = [struct(go_mod = "@//:go.mod")]))],
        rules_to_mock = ["go_repository", "_go_repository_directives"],
        tag_classes = ["config", "from_file", "module"],
    )
    print(result)
    return unittest.end(env)

go_deps_test = unittest.make(_go_deps_test_impl)

def go_deps_test_suite(name):
    unittest.suite(
        name,
        go_deps_test,
    )

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//internal/bzlmod:utils.bzl", "with_replaced_or_new_fields")

_BEFORE_STRUCT = struct(
    direct = True,
    path = "github.com/bazelbuild/buildtools",
    version = "v0.0.0-20220531122519-a43aed7014c8",
)

_EXPECT_REPLACED_STRUCT = struct(
    direct = True,
    path = "github.com/bazelbuild/buildtools",
    replace = "path/to/add/replace",
    version = "v1.2.2",
)

def _with_replaced_or_new_fields_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, _EXPECT_REPLACED_STRUCT, with_replaced_or_new_fields(
        _BEFORE_STRUCT,
        replace = "path/to/add/replace",
        version = "v1.2.2",
    ))
    return unittest.end(env)

with_replaced_or_new_fields_test = unittest.make(_with_replaced_or_new_fields_test_impl)

mkrec = lambda f: f(f)

mkrec_nice = lambda g: mkrec(lambda rec: g(lambda y: rec(rec)(y)))

fact = mkrec_nice(lambda rec: lambda x: 1 if x == 0 else rec(x - 1) * x)

def _recursion_test_impl(ctx):
    env = unittest.begin(ctx)
    print(fact(5))
    return unittest.end(env)

recursion_test = unittest.make(_recursion_test_impl)

def utils_test_suite(name):
    unittest.suite(
        name,
        with_replaced_or_new_fields_test,
        recursion_test,
    )

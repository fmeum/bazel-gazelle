load("@bazel_skylib//lib:unittest.bzl", "TOOLCHAIN_TYPE", "unittest")

def module(name, version = "1.2.3.4-bcr.1+alpha", tags = [], *, is_root = False):
    return struct(
        name = name,
        version = version,
        tags = tags,
        is_root = is_root,
    )

def tag(tag_class, attrs = {}):
    return struct(
        tag_class = tag_class,
        attrs = attrs,
    )

def _func_name(func):
    return str(func).removeprefix("<function ").removesuffix(">").removeprefix("_")

def _make_config(extension_impl, *, repository_rules = [], tag_classes = {}):
    repository_rules = tuple(repository_rules)
    tag_classes = dict(tag_classes)

    def _run(modules):
        if not modules:
            fail("modules must not be empty")

        module_ctx = struct(
            modules = [
                module(
                    name = m.name,
                    version = m.version,
                    tags = struct(**{
                        tag_class: [tag for tag in m.tags if tag.tag_class == tag_class]
                        for tag_class in tag_classes.keys()
                    }),
                    is_root = m.is_root,
                )
                for m in modules
            ],
        )

        mock_repo_rules = {}
        repos = {}

        for kind in repository_rules:
            def mock_repo_rule(name, **kwargs):
                if name in repos:
                    fail("Repository {name} already defined as {previous_kind} with {previous_attrs}, attempting redefinition as {current_kind} with {current_attrs}".format(
                        name = name,
                        previous_kind = repos[name].kind,
                        previous_attrs = repos[name].attrs,
                        current_kind = kind,
                        current_attrs = kwargs,
                    ))
                repos[name] = struct(
                    kind = kind,
                    attrs = kwargs,
                )

            mock_repo_rules[kind] = mock_repo_rule

        extension_impl(module_ctx, **mock_repo_rules)

        return struct(
            repos = struct(**repos),
        )

    def _make_test(asserts_func, modules):
        def _test_impl(ctx):
            env = unittest.begin(ctx)

            result = _run(modules)
            asserts_func(env, result)

            return unittest.end(env)

        return rule(
            _test_impl,
            attrs = {"_impl_name": attr.string(default = _func_name(asserts_func))},
            _skylark_testable = True,
            test = True,
            toolchains = [TOOLCHAIN_TYPE],
        )

    return struct(
        make_test = _make_test,
    )

module_extension_test = struct(
    make_config = _make_config,
)

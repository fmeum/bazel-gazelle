load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(":os.bzl", "LINUX_AMD64_PRESET")

def module(name, version, tags, *, is_root = False):
    return struct(
        name = name,
        version = version,
        tags = tags,
        is_root = is_root,
    )

def tag(_tag_class, **attrs):
    return struct(
        tag_class = _tag_class,
        attrs = attrs,
    )

def _func_name(func):
    func_name = str(func).removeprefix("<function ").removeprefix("_")
    func_name = func_name[:func_name.find(" ")]
    return func_name

def _assert_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected_failure_msg)
    return analysistest.end(env)

def _tag_with_defaults(tag_class_defaults, tag):
    return struct(**(tag_class_defaults[tag["tag_class"]] | tag["attrs"]))

def _make_module_ctx_tags(tag_class_defaults, tags):
    return struct(**{
        name: [_tag_with_defaults(tag_class_defaults, tag) for tag in tags if tag["tag_class"] == name]
        for name in tag_class_defaults.keys()
    })

def _suite_builder(extension_impl, *, repository_rules = [], tag_class_defaults = {}):
    rules_to_instantiate = []
    rules_to_export = []
    already_built = False

    def _run(modules, *, preset = LINUX_AMD64_PRESET):
        if not modules:
            fail("modules must not be empty")

        module_ctx = struct(
            modules = [
                module(
                    name = m["name"],
                    version = m["version"],
                    tags = _make_module_ctx_tags(tag_class_defaults, m["tags"]),
                    is_root = m["is_root"],
                )
                for m in modules
            ],
            os = struct(
                arch = preset.arch,
                environ = preset.environ,
                name = preset.name,
            ),
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

    def _run_one_impl(ctx):
        _run(json.decode(ctx.attr.modules))

    _run_one = rule(
        _run_one_impl,
        attrs = {
            "modules": attr.string(),
        },
    )

    def _add_test(asserts_func, *, modules):
        if already_built:
            fail("add_test() cannot be called after build()")

        def _test_impl(ctx):
            env = analysistest.begin(ctx)

            result = _run(json.decode(json.encode(modules)))
            asserts_func(env, result)

            return analysistest.end(env)

        test_name = _func_name(asserts_func)

        rules_to_instantiate.append(lambda name: testing.analysis_test(
            name + "_" + test_name,
            _test_impl,
            attrs = {"_impl_name": attr.string(default = test_name)},
        ))

    def _add_failure_test(test_name, *, modules, failure_contains):
        if already_built:
            fail("add_test() cannot be called after build()")

        def instantiate_test(name):
            prefixed_name = name + "_" + test_name
            failing_rule_name = prefixed_name + "_failing"

            _run_one(
                name = failing_rule_name,
                modules = json.encode(modules),
                tags = ["manual"],
                testonly = True,
            )

            testing.analysis_test(
                prefixed_name,
                _assert_failure_test_impl,
                attrs = {
                    "target_under_test": attr.label(
                        cfg = analysis_test_transition(
                            settings = {
                                "//command_line_option:allow_analysis_failures": True,
                            },
                        ),
                    ),
                    "expected_failure_msg": attr.string(
                        default = failure_contains,
                    ),
                    "_impl_name": attr.string(
                        default = prefixed_name,
                    ),
                },
                attr_values = {
                    "target_under_test": ":" + failing_rule_name,
                },
            )

        rules_to_instantiate.append(instantiate_test)

    def _build():
        if already_built:
            fail("build() cannot be called twice")

        def instantiate_suite(name, **kwargs):
            [
                r(
                    name = name,
                    **kwargs
                )
                for r in rules_to_instantiate
            ]

        return instantiate_suite

    return struct(
        add_test = _add_test,
        add_failure_test = _add_failure_test,
        build = _build,
    ), _run_one

module_extension_test = struct(
    suite_builder = _suite_builder,
)

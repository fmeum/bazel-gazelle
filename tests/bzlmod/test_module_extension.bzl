def module(name, version, tags, *, is_root = False):
    return struct(
        name = name,
        version = version,
        tags = tags,
        is_root = is_root,
    )

def _make_config(impl, *, repository_rules = [], tag_classes = []):
    def _make_test(test_impl, modules):
        if not modules:
            fail("modules must not be empty")

        module_ctx = struct(
            modules = [
                module(
                    name = m.name,
                    version = m.version,
                    tags = struct(**{
                        tag_class: m.tags.get(tag_class, [])
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

        impl(module_ctx, **mock_repo_rules)

        return struct(
            repos = struct(**repos),
        )

    return struct(
        make_test = _make_test,
    )

module_extension_test = struct(
    make_config = _make_config,
)

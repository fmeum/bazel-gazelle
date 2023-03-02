def module(name, version, tags, *, is_root = False):
    return struct(
        name = name,
        version = version,
        tags = tags,
        is_root = is_root,
    )

def module_extension_test(env, impl, *, modules, rules_to_mock = [], tag_classes = []):
    if not modules:
        fail("modules must not be empty")

    module_ctx = struct(
        modules = [
            module(
                name = m.name,
                version = m.version,
                tags = struct(**{
                    tag_class: m.tags.get(tag_class, [])
                    for tag_class in tag_classes
                }),
                is_root = m.is_root,
            )
            for m in modules
        ],
    )

    mock_repo_rules = {}
    repos = {}
    seen_repos = {}

    for kind in rules_to_mock:
        def mock_repo_rule(name, **kwargs):
            if name in seen_repos:
                fail("repo %s already exists" % name)
            repos.setdefault(kind, []).append(struct(
                name = name,
                **kwargs
            ))
            seen_repos[name] = None

        mock_repo_rules[kind] = mock_repo_rule

    impl(module_ctx, **mock_repo_rules)

    return struct(
        repos = struct(**repos),
    )

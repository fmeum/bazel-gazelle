load("//internal:common.bzl", "executable_extension")
load("//internal:go_repository.bzl", "go_repository")
load(":non_module_deps.bzl", "fetch_non_module_deps")
load(":semver.bzl", "semver")

def _repo_name(importpath):
    path_segments = importpath.split("/")
    segments = reversed(path_segments[0].split(".")) + path_segments[1:]
    candidate_name = "_".join(segments).replace("-", "_")
    return "".join([c.lower() if c.isalnum() else "_" for c in candidate_name.elems()])

def _go_repository_directives_impl(ctx):
    directives = [
        "# gazelle:repository go_repository name={name} {directives}".format(
            name = name,
            directives = " ".join(directives),
        )
        for name, directives in ctx.attr.directives.items()
    ]
    ctx.file("WORKSPACE", "\n".join(directives))
    ctx.file("BUILD.bazel")

_go_repository_directives = repository_rule(
    implementation = _go_repository_directives_impl,
    attrs = {
        "directives": attr.string_list_dict(mandatory = True),
    },
)

def _noop(s):
    pass

def _resolve_label(module_ctx, label_cache, label):
    label_cache[label] = module_ctx.path(label)

def _go_deps_impl(module_ctx):
    fetch_non_module_deps()

    # Resolve all labels first to prevent restarts after actual work has been
    # done.
    label_cache = {}
    bzlmod_helper = Label("@bazel_gazelle_go_repository_tools//:bin/bzlmod{}".format(executable_extension(module_ctx)))
    _resolve_label(module_ctx, label_cache, bzlmod_helper)
    for module in module_ctx.modules:
        for mod_from_file in module.tags.from_file:
            _resolve_label(module_ctx, label_cache, mod_from_file.go_mod)

    module_resolutions = {}
    root_versions = {}

    outdated_direct_dep_printer = print
    for module in module_ctx.modules:
        # Parse the go_dep.config tag of the root module only.
        for mod_config in module.tags.config:
            # bazel_module.is_root is only available as of Bazel 5.3.0.
            if not getattr(module, "is_root", False):
                continue
            check_direct_deps = mod_config.check_direct_dependencies
            if check_direct_deps == "off":
                outdated_direct_dep_printer = _noop
            elif check_direct_deps == "warning":
                outdated_direct_dep_printer = print
            elif check_direct_deps == "error":
                outdated_direct_dep_printer = fail

        additional_go_modules = []
        for mod_from_file in module.tags.from_file:
            result = module_ctx.execute(
                arguments = [
                    label_cache[bzlmod_helper],
                    "-go_mod=%s" % label_cache[mod_from_file.go_mod],
                ],
            )
            if result != 0:
                fail("Failed to parse %s: %s" % (mod_from_file.go_mod, result.stderr))
            additional_go_modules += [
                struct(
                    importpath = go_mod_dict.get("importpath"),
                    version = go_mod_dict.get("version"),
                    sum = go_mod_dict.get("sum"),
                )
                for go_mod_dict in json.decode(result.stdout)
            ]

        # Parse the go_dep.module tags of all transitive dependencies and apply
        # Minimum Version Selection to resolve importpaths to Go module versions
        # and sums.
        #
        # Note: This applies Minimum Version Selection on the resolved
        # dependency graphs of all transitive Bazel module dependencies, which
        # is not what `go mod` does. But since this algorithm ends up using only
        # Go module versions that have been explicitly declared somewhere in the
        # full graph, we can assume that at that place all its required
        # transitive dependencies have also been declared - we may end up
        # resolving them to higher versions, but only compatible ones.
        importpaths = {}
        for module_tag in module.tags.module + additional_go_modules:
            if module_tag.importpath in importpaths:
                fail("Duplicate importpath '%s' in module '%s'" % (module_tag.importpath, module.name))
            importpaths[module_tag.importpath] = None
            raw_version = module_tag.version
            if raw_version.startswith("v"):
                raw_version = raw_version[1:]
            if getattr(module, "is_root", False):
                root_versions[module_tag.importpath] = raw_version
            version = semver.to_comparable(raw_version)
            current_resolution = module_resolutions.get(module_tag.importpath, default = None)
            if not current_resolution or version > current_resolution.version:
                module_resolutions[module_tag.importpath] = struct(
                    module = module.name,
                    repo_name = _repo_name(module_tag.importpath),
                    version = version,
                    raw_version = raw_version,
                    sum = module_tag.sum,
                    build_naming_convention = module_tag.build_naming_convention,
                )
        is_root_module = False

    for importpath, root_version in root_versions.items():
        if semver.to_comparable(root_version) < module_resolutions[importpath].version:
            outdated_direct_dep_printer(
                "For Go module '{importpath}', the root module requires module version v{root_version}, but got v{resolved_version} in the resolved dependency graph.".format(
                    importpath = importpath,
                    root_version = root_version,
                    resolved_version = module_resolutions[importpath].raw_version,
                )
            )

    [
        go_repository(
            name = module.repo_name,
            importpath = importpath,
            sum = module.sum,
            version = "v" + module.raw_version,
            build_naming_convention = module.build_naming_convention,
        )
        for importpath, module in module_resolutions.items()
    ]

    # With transitive dependencies, Gazelle would no longer just have to pass a
    # single top-level WORKSPACE/MODULE.bazel file, but those of all modules
    # that use the go_dep tag. Instead, emit a synthetic WORKSPACE file with
    # Gazelle directives for all of those modules here.
    directives = {
        module.repo_name: [
            "importpath=" + importpath,
            "build_naming_convention=" + module.build_naming_convention,
        ]
        for importpath, module in module_resolutions.items()
    }
    _go_repository_directives(
        name = "_bazel_gazelle_go_repository_directives",
        directives = directives,
    )

_config_tag = tag_class(
    attrs = {
        "check_direct_dependencies": attr.string(
            values = ["off", "warning", "error"],
        ),
    },
)

_from_file_tag = tag_class(
    attrs = {
        "go_mod": attr.label(mandatory = True),
    },
)

_module_tag = tag_class(
    attrs = {
        "importpath": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "sum": attr.string(),
        "build_naming_convention": attr.string(default = "import_alias"),
    },
)

go_deps = module_extension(
    _go_deps_impl,
    tag_classes = {
        "config": _config_tag,
        "from_file": _from_file_tag,
        "module": _module_tag,
    },
)

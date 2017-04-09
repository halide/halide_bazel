""" Halide rules for Bazel"""

_COPTS_DEFAULT = [
  "$(STACK_FRAME_UNLIMITED)",
  "-fno-rtti",
  "-fvisibility-inlines-hidden",
  "-std=c++11",
]

_LINKOPTS_DEFAULT = [
  "-ldl",
  "-lm",
  "-lpthread",
  "-lz",
]

# "darwin" -> host is OSX x86-64
_HOST_DEFAULTS_DARWIN = {
  "copts": _COPTS_DEFAULT,
  "linkopts": _LINKOPTS_DEFAULT,
  "http_archive_info": [
    "https://github.com/halide/Halide/releases/download/release_2016_10_25/halide-mac-64-trunk-aa5d5514f179bf0ffe1a2dead0c0eb7300b4069a.tgz",
    "7cc502ebeabd1890f9ab12c186e59745c9f524ce74b325931103ef7a1136ca2a",
  ]
}

# "piii" -> host is Linux x86-32
_HOST_DEFAULTS_PIII = {
  "copts": _COPTS_DEFAULT,
  "linkopts": _LINKOPTS_DEFAULT,
  "http_archive_info": [
    # TODO: we default to gcc4.8 on Linux; is this the best choice?
    "https://github.com/halide/Halide/releases/download/release_2016_10_25/halide-linux-32-gcc48-trunk-aa5d5514f179bf0ffe1a2dead0c0eb7300b4069a.tgz",
    "ab0545ebd8fff816676522fbfc434956ecd43b6fc1d46c4847ca9009223106e4",
  ]
}

# "k8" -> host is Linux x86-64
_HOST_DEFAULTS_K8 = {
  "copts": _COPTS_DEFAULT,
  "linkopts": _LINKOPTS_DEFAULT,
  "http_archive_info": [
    # TODO: we default to gcc4.8 on Linux; is this the best choice?
    "https://github.com/halide/Halide/releases/download/release_2016_10_25/halide-linux-64-gcc48-trunk-aa5d5514f179bf0ffe1a2dead0c0eb7300b4069a.tgz",
    "f2c47f9ec4bcad0d8195e12653048ee49dbce0e828e0273242562813197a6c4b",
  ]
}

# "x64_windows_msvc" -> host is Windows x86-64
_HOST_DEFAULTS_WIN64 = {
  "copts": _COPTS_DEFAULT,
  "linkopts": [],
  "http_archive_info": [
    "https://github.com/halide/Halide/releases/download/release_2016_10_25/halide-win-64-trunk-aa5d5514f179bf0ffe1a2dead0c0eb7300b4069a.zip",
    "17910e65edd9c7a3df74db73b11bc3bca021186f81beab82c245529839e45e98",
  ]
}

# FreeBSD, etc: sorry, not supported as compile host (yet).
_HOST_DEFAULTS = {
    "darwin": _HOST_DEFAULTS_DARWIN,
    "piii": _HOST_DEFAULTS_PIII,
    "k8": _HOST_DEFAULTS_K8,
    "x64_windows_msvc": _HOST_DEFAULTS_WIN64,
}

def _get_cpu_value(repository_ctx):
  """Compute the cpu_value based on the OS name."""
  os_name = repository_ctx.os.name.lower()
  if os_name.startswith("mac os"):
    return "darwin"
  if os_name.find("freebsd") != -1:
    return "freebsd"
  if os_name.find("windows") != -1:
    return "x64_windows_msvc"
  # Use uname to figure out whether we are on x86_32 or x86_64
  result = repository_ctx.execute(["uname", "-m"])
  return "piii" if result.stdout.strip() == "i386" else "k8"

def _halide_configure_impl(repository_ctx):
  cpu_value = _get_cpu_value(repository_ctx)
  host_defaults = _HOST_DEFAULTS.get(cpu_value, None)
  if not host_defaults:
    fail("Unsupported host '%s'." % cpu_value)

  distrib_root = "distrib"

  repository_ctx.template(
    "BUILD",
    Label("//:BUILD.halide_distrib.tpl"),
    {},
    False)

  host_copts = host_defaults["copts"]
  host_linkopts = host_defaults["linkopts"]
  repository_ctx.template(
    "halide_library.bzl",
    Label("//:halide_library.bzl.tpl"),
    {
      "%{host_copts}": repr(host_copts),
      "%{host_linkopts}": repr(host_linkopts),
      "%{default_halide_target_features}": repr(repository_ctx.attr.default_halide_target_features),
    },
    False)

  if repository_ctx.attr.http_archive_info != {} and repository_ctx.attr.local_repository_path != "":
    fail("You may not specify both http_archive_info and local_repository_path.")

  # Local repository? Just make a symlink to the path and we're done.
  if repository_ctx.attr.local_repository_path:
    repository_ctx.symlink(repository_ctx.attr.local_repository_path, distrib_root)
  else:
    # HTTP Archive? Choose the right one based on the host. If the user
    # supplied a dictionary of options, look there exclusively; if not, fall
    # back on the defaults we have hardcoded (generally, the most recent
    # stable Halide releases).
    if repository_ctx.attr.http_archive_info != {}:
      # Using list() here is a hack: the values from repository_ctx.attr.http_archive_info
      # will be ArrayList (which Skylark doesn't like in Bazel 0.2.2), but using
      # the list() function will convert into something that it does like.
      http_archive_info = list(repository_ctx.attr.http_archive_info.get(cpu_value, None))
      if not http_archive_info:
        fail("http_archive_info did not provide a value for host=%s." % cpu_value)
    else:
      http_archive_info = host_defaults["http_archive_info"]

    if len(http_archive_info) != 2:
      fail("http_archive_info must have exactly two entries.")

    url = http_archive_info[0]
    sha256 = http_archive_info[1]

    # This is a hack: as of Bazel 0.2.2, repository_ctx.download_and_extract()
    # will not create the necessary directories (i.e., "distrib/" in this case), 
    # but repository_ctx.file() will... so emit a useless file just to force
    # the directory to be created.
    repository_ctx.file("%s/empty.txt" % distrib_root, "", False)

    output = distrib_root
    strip_prefix = "halide"
    type = ""
    repository_ctx.download_and_extract(url, output, sha256, type, strip_prefix)


_halide_configure = repository_rule(
    implementation=_halide_configure_impl,
    attrs={
        "local_repository_path": attr.string(),
        "http_archive_info": attr.string_list_dict(),
        "default_halide_target_features": attr.string_list()
    },
    local=True)


def halide_configure(local_repository_path = "",
                     http_archive_info = {},
                     default_halide_target_features = []):
  http_archive_info_local = {}
  for host_target, info in http_archive_info.items():
    url = info.get("url", "")
    sha256 = info.get("sha256", "")
    if not url:
      fail("url must be specified for %s" % host_target)
    http_archive_info_local[host_target] = [url, sha256]
  _halide_configure(name="halide_distrib",
    local_repository_path = local_repository_path,
    http_archive_info = http_archive_info_local,
    default_halide_target_features = default_halide_target_features)

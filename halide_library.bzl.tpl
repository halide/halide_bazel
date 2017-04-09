_HOST_COPTS = %{host_copts}
_HOST_LINKOPTS = %{host_linkopts}
_DEFAULT_HALIDE_TARGET_FEATURES = %{default_halide_target_features}

# (halide-target-base, cpu, android-cpu, ios-cpu)
_HALIDE_TARGET_CONFIG_INFO = [
    # Android
    ("arm-32-android", None, "armeabi-v7a", None),
    ("arm-64-android", None, "arm64-v8a", None),
    ("x86-32-android", None, "x86", None),
    ("x86-64-android", None, "x86_64", None),
    # iOS
    ("arm-32-ios", None, None, "armv7"),
    ("arm-64-ios", None, None, "arm64"),
    # OSX
    ("x86-32-osx", None, None, "x86_32"),
    ("x86-64-osx", None, None, "x86_64"),
    # Linux
    ("arm-64-linux", "arm", None, None),
    ("powerpc-64-linux", "ppc", None, None),
    ("x86-64-linux", "k8", None, None),
    ("x86-32-linux", "piii", None, None),
    # Windows
    ("x86-64-windows", "x64_windows_msvc", None, None),
    # TODO: add conditions appropriate for other targets/cpus: Windows, etc.
]


def _config_setting_name(halide_target):
  """Take a Halide target string and converts to a unique name suitable for
     a Bazel config_setting."""
  tokens = halide_target.split("-")
  if len(tokens) != 3:
    fail("Unexpected halide_target form: %s" % halide_target)
  halide_arch = tokens[0]
  halide_bits = tokens[1]
  halide_os = tokens[2]
  return "config_%s_%s_%s" % (halide_arch, halide_bits, halide_os)


def internal_halide_config_settings():
  """Define the config_settings used internally by these build rules."""
  for halide_target, cpu, android_cpu, ios_cpu in _HALIDE_TARGET_CONFIG_INFO:
    if android_cpu == None:
      # "armeabi" is the default value for --android_cpu and isn't considered legal
      # here, so we use the value to assume we aren't building for Android.
      android_cpu = "armeabi"
    if ios_cpu == None:
      # The default value for --ios_cpu is "x86_64", i.e. for the 64b OS X simulator.
      # Assuming that the i386 version of the simulator will be used along side
      # arm32 apps, we consider this value to mean the flag was unspecified; this
      # won't work for 32 bit simulator builds for A6 or older phones.
      ios_cpu = "x86_64"
    if cpu != None:
      values={
          "cpu": cpu,
          "android_cpu": android_cpu,
          "ios_cpu": ios_cpu,
      }
    else:
      values={
          "android_cpu": android_cpu,
          "ios_cpu": ios_cpu,
      }
    native.config_setting(
        name=_config_setting_name(halide_target),
        values=values,
        visibility=["//visibility:public"])

def _halide_generator_binary(name, srcs, generator_deps):
  native.cc_binary(name=name,
                   srcs=srcs,
                   copts=_HOST_COPTS,
                   linkopts=_HOST_LINKOPTS,
                   deps=[
                       "@halide_distrib//:internal_halide_generator_glue",
                   ] + generator_deps,
                   visibility=["//visibility:private"])


def _halide_generator_outputs_dict(filename, outputs):
  _GENERATOR_OUTPUT_EXTENSIONS = {
      "o": "o",
      "h": "h",
      "assembly": "s",
      "bitcode": "bc",
      "stmt": "stmt",
      "html": "html",
      "cpp": "cpp",
  }
  ret = {}
  for output in outputs:
    if output in _GENERATOR_OUTPUT_EXTENSIONS:
      ret[output] = "%s.%s" % (filename,
                               _GENERATOR_OUTPUT_EXTENSIONS[output])
    else:
      fail("Unknown tag in outputs: " + output)
  return ret


def _has_dupes(some_list):
  clean = list(set(some_list))
  return sorted(some_list) != sorted(clean)


def _halide_generator_output_impl(ctx):
  if _has_dupes(ctx.attr.halide_target_features):
    fail("Duplicate values in halide_target_features: " + str(
        ctx.attr.halide_target_features))

  # Don't complain if features are listed in both halide_target_features
  # and default_halide_target_features.
  features = [f for f in ctx.attr.halide_target_features]
  for f in _DEFAULT_HALIDE_TARGET_FEATURES:
    if not f in features:
      features.append(f)

  if _has_dupes(ctx.attr.outputs):
    fail("Duplicate values in outputs: " + str(ctx.attr.outputs))

  halide_target_base = ctx.attr.halide_target if ctx.attr.halide_target else "host"
  halide_target = "-".join([halide_target_base] + sorted(features))
  generator_env = {}

  building_for_windows = ctx.fragments.cpp.cpu == "x64_windows_msvc"
  if building_for_windows:
    # Add Release to generator path so it can find Halide.dll.
    generator_env["PATH"] = "external/halide_distrib/distrib/Release"

  outputs_types = ctx.attr.outputs[:]
  copy_obj_to_o = False
  outputs = []
  if building_for_windows and "o" in outputs_types:
    # On Windows the generator outputs .obj instead of .o files so we need to
    # modify the outputs to indicate an .obj is output instead of a .o.
    outputs_types.remove("o")
    outputs += [ctx.new_file("%s.obj" % (ctx.attr.filename))]
    copy_obj_to_o = True

  outputs += [ctx.new_file(f)
             for f in _halide_generator_outputs_dict(ctx.attr.filename,
                                                     outputs_types).values()]

  output_dir = outputs[0].dirname 
  arguments = ["-o", output_dir]
  if ctx.attr.filename:
    arguments += ["-n", ctx.attr.filename]
  if ctx.attr.halide_function_name:
    arguments += ["-f", ctx.attr.halide_function_name]
  if ctx.attr.halide_generator_name:
    arguments += ["-g", ctx.attr.halide_generator_name]
  if len(ctx.attr.outputs) > 0:
    arguments += ["-e", ",".join(ctx.attr.outputs)]
  arguments += ["target=%s" % halide_target]
  if ctx.attr.halide_generator_args:
    arguments += [ctx.attr.halide_generator_args]

  ctx.action(executable=ctx.executable.generator_binary,
             arguments=arguments,
             outputs=outputs,
             mnemonic="ExecuteHalideGenerator",
             env=generator_env,
             progress_message="Executing generator %s for %s..." %
             (ctx.attr.halide_generator_name, halide_target))

  if copy_obj_to_o:
    # Copy the .obj to a .o. The .obj extension is not accepted by
    # Bazel as a valid library src so we need to create a .o to make
    # Bazel happy.
    obj_file = ctx.new_file("%s.obj" % (ctx.attr.filename))
    o_file = ctx.new_file("%s.o" % (ctx.attr.filename))
    ctx.action(command="cp %s %s" % (obj_file.path, o_file.path),
               inputs = [obj_file],
               outputs = [o_file])


_halide_generator_output = rule(
    implementation=_halide_generator_output_impl,
    attrs={
        "generator_binary": attr.label(executable=True,
                                       allow_files=True,
                                       mandatory=True,
                                       cfg="host"),
        "filename": attr.string(),
        "halide_target": attr.string(),
        "halide_function_name": attr.string(),
        "halide_generator_name": attr.string(),
        "halide_generator_args": attr.string(),
        "halide_target_features": attr.string_list(),
        "outputs": attr.string_list(),
    },
    fragments=["cpp"],
    outputs=_halide_generator_outputs_dict,
    output_to_genfiles=True)


# TODO:
# -- this doesn't provide a clean way to add architecture-specific
# features (e.g., add AVX but only to x86-64 and x86-32 targets);
# you must unconditionally add them via halide_target_features for now.
def halide_library(name,
                   srcs,
                   hdrs=[],
                   filter_deps=[],
                   generator_deps=[],
                   visibility=None,
                   function_name=None,
                   generator_name=None,
                   generator_args=None,
                   halide_target_features=[],
                   extra_outputs=[]):

  generator_binary = "%s_generator_binary" % name
  _halide_generator_binary(generator_binary, srcs, generator_deps)

  # Emit a rule to generate for all the interesting targets, but add
  # them via a select() that will choose only the correct one for the
  # current build target. Note that each of these has an extern "C" with the
  # same name ("function_name") but a different file name (suffixed with the
  # Halide target). (Note that each sub_rule will produce a .o but no .h;
  # we'll emit a master .h afterwards.)
  conditional_srcs = {}
  for halide_target, _, _, _ in _HALIDE_TARGET_CONFIG_INFO:
    setting_name = _config_setting_name(halide_target)
    sub_name = "%s_%s" % (name, setting_name)
    generator_output = "%s_generator_output" % sub_name
    _halide_generator_output(name=generator_output,
                             generator_binary=":%s" % generator_binary,
                             filename=sub_name,
                             halide_target=halide_target,
                             halide_function_name=function_name,
                             halide_generator_name=generator_name,
                             halide_generator_args=generator_args,
                             halide_target_features=halide_target_features,
                             outputs=["o"] + extra_outputs,
                             visibility=["//visibility:private"])
    conditional_srcs["@halide_distrib//:%s" % setting_name] = [":%s" % generator_output]

  # Now emit a single .h with the expected name (but no .o file); this is
  # what our client file will #include.
  header_output = "%s_header" % name
  _halide_generator_output(name=header_output,
                           generator_binary=":%s" % generator_binary,
                           filename=name,
                           halide_target="host",
                           halide_function_name=function_name,
                           halide_generator_name=generator_name,
                           halide_generator_args=generator_args,
                           halide_target_features=halide_target_features,
                           outputs=["h"],
                           visibility=["//visibility:private"])

  # Batch up the .h and all the .o files into a cc_library (with the appropriate
  # select() in place to make things work well).
  native.cc_library(
      name=name,
      srcs=select(conditional_srcs) + [":%s" % header_output],
      deps=["@halide_distrib//:halide_runtime"] + filter_deps,
      # TODO: these linkopts will probably need to be conditionalized
      # for various platforms; they are correct for OSX and Linux.
      linkopts= select({
        "@halide_distrib//:config_x86_64_windows": [],
        "//conditions:default": [
          "-ldl",
          "-lm",
          "-lpthread",
          "-lz",
      ]}),
      hdrs=["%s.h" % name],
      visibility=visibility)

package(
  default_visibility=["//visibility:public"]
)

load(":halide_library.bzl", "internal_halide_config_settings")
internal_halide_config_settings()

# Some useful utilities for dealing with Images in Halide at runtime.
# (Generators should never need to use this library.)
cc_library(
  name = "halide_image",
  hdrs = glob(["distrib/tools/halide_image*.h"]),
  includes = ["distrib/tools"]
)

# Header-only library to let clients to use Halide::Buffer at runtime.
# (Generators should never need to use this library.)
cc_library(
  name = "halide_buffer",
  hdrs = glob(["distrib/include/HalideBuffer*.h"]),
  includes = ["distrib/include"]
)

# You should rarely need to add an explicit dep on this library
# (the halide_library() rule will add it for you), but there are
# unusual circumstances where it is necessary.
cc_library(
  name="halide_runtime",
  hdrs = glob(["distrib/include/HalideRuntime*.h"]),
  includes = ["distrib/include"]
)

cc_library(
  name="lib_halide_static",
  srcs = ["distrib/lib/libHalide.a"],
  hdrs = ["distrib/include/Halide.h"],
  includes = ["distrib/include"],
)

# This library is visibility:public, because any package that uses the 
# halide_library() rule will implicitly need access to it; that said, it is 
# intended only for the private, internal use of the halide_library() rule. 
# Please don't depend on it directly; doing so will likely break your code at 
# some point in the future.
cc_library(
  name="internal_halide_generator_glue",
  srcs = ["distrib/tools/GenGen.cpp"],
  deps = [":lib_halide_static"],
)

load("@halide_distrib//:halide_library.bzl", "halide_library")

halide_library(
  name="example", 
  srcs=["example_generator.cpp"]
)

cc_binary(
    name = "main",
    srcs = ["main.cpp"],
    deps = [
      ":example",
      "@halide_distrib//:halide_image"
    ],
)

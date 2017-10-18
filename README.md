** Note to reader: these build rules are deprecated and no longer maintained; Halide itself now includes Bazel build rules that are being maintained. We recommend migrating from these rules to the ones in Halide if you are using Bazel; see README_bazel.md in the Halide source tree.**

# Experimenal Bazel Halide Build Rules

## Overview

These build rules are used for building Halide Generators with [Bazel](http://bazel.io).

The *Generator* is the fundamental compilable unit of Halide used in [Bazel](http://bazel.io).
(Halide itself provides for other ahead-of-time compilation modes, as well as
just-in-time compilation, but these aren't supported in this rule set, and won't
be discussed here.)

*Generator* has [documentation](http://halide-lang.org/docs/_generator_8h.html),
[tutorials](http://halide-lang.org/tutorials/tutorial_lesson_15_generators.html)
and [examples](https://github.com/halide/Halide/tree/master/test/generator), so
we won't go into too much detail here, other than to recap: a *Generator* is a
C++ class in which you define a Halide pipeline and schedule, as well as
well-defined input and output parameters; it can be compiled into a library of
executable code (referred to as a *Filter*) that efficiently runs the Halide
pipeline.

Note that this rule requires the compiler host to be one of: 

*   OSX x86-64 
*   Linux x86-64 
*   Linux x86-32

It is anticipated that additional hosts (e.g. Windows x86-64) will be supported
at some point in the future.

## Setup

To use the Halide rules, add the following to your `WORKSPACE` file to add the
external repositories for the Halide toolchain:

```python
git_repository(
   name = "halide_bazel",
   remote = "https://github.com/halide/halide_bazel",
   tag = "v0.1.1"  # Or whichever version you want
)
load("@halide_bazel//:halide_configure.bzl", "halide_configure")
halide_configure()
```

## Build Rules

```python
halide_library(name, srcs, hdrs, filter_deps, generator_deps, visibility, 
               function_name, generator_name, generator_args, 
               halide_target_features, extra_outputs)
```

*   **name** *(Name; required)* The name of the build rule.
*   **srcs** *(List of labels; required)* source file(s) to compile into the
    Generator executable.
*   **hdrs** *(List of labels; optional)* additional .h files that will be
    exposed to dependents of this rule.
*   **generator_deps** *(List of labels; optional)* optional list of extra
    dependencies needed to compile and/or link the Generator itself. (These
    dependencies are *not* included in the filter produced by
    `halide_library()`, nor in any executable that depends on it.)
*   **filter_deps** *(List of labels; optional)* optional list of extra
    dependencies needed by the Filter. (Generally speaking, you only need these
    if you use Halide's `define_extern` directive.)
*   **visibility** *(List of labels; optional)* Bazel visibility of result.
*   **function_name** *(String; optional)* The name of the generated C function
    for the filter. If omitted, defaults to the Bazel rule name.
*   **generator_name** *(String; optional)* The registered name of the Halide
    Generator (i.e., the name passed as the first argument to RegisterGenerator
    in the Generator source file). If empty (or omitted), the srcs must define
    exactly one Halide Generator, which will be used. (If the srcs define
    multiple Generators, a compile error will result.)
*   **generator_args** *(String; optional)* Arguments to pass to the Generator,
    used to define the compile-time values of GeneratorParams defined by the
    Generator. If any undefined GeneratorParam names (or illegal GeneratorParam
    values) are specified, a compile error will result.
*   **debug_codegen_level** *(Integer; optional)* Value to use for
    HL_DEBUG_CODEGEN when building the Generator; usually useful only for
    advanced Halide debugging. Defaults to zero. This attribute should never be
    specified in code checked in to google3.
*   **trace_level** *(Integer; optional)* Value to use for HL_TRACE when
    building the Generator; usually useful only for advanced Halide debugging.
    Defaults to zero. This attribute should never be specified in code checked
    in to google3.
*   **halide_target_features** *(List of strings; optional)* A list of extra
    Halide Features to enable in the code. This can be any feature listed in
    [feature_name_map]
    (https://github.com/halide/Halide/blob/master/src/Target.cpp). The most
    useful are generally:
    *   "debug" (generate code with extra debugging)
    *   "cuda", "opengl", or "opencl" (generate code for a GPU target)
    *   "profile" (generate code with Halide's sampling profiler included)
    *   "user_context" (the generated Filter function to take an arbitrary void*
        pointer as the first parameter)
*   **extra_outputs** *(List of strings; optional)* A list of extra Halide
    outputs to generate at build time; this is exclusively intended for
    debugging (e.g. to examine Halide code generation) and currently supports:
    *   "assembly" (generate assembly listings for the generated functions)
    *   "bitcode" (emit the LLVM bitcode for generation functions)
    *   "stmt" (generate Halide .stmt files for generated functions)
    *   "html" (like "stmt", but generated with HTML-formatted wrapping)

## Example

Suppose you have the following directory structure:

```
[workspace]/
    BUILD
    WORKSPACE
    example_generator.cpp
    main.cpp
```

`WORKSPACE`:

```python
git_repository(
  name = "halide_bazel",
  remote = "https://github.com/halide/halide_bazel",
  tag = "v0.1.1"
)
load("@halide_bazel//:halide_configure.bzl", "halide_configure")
halide_configure()
```

`BUILD`:

```python
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
```

`example_generator.cpp`:

```c++
#include "Halide.h"

namespace {

// Trivial generator that scales a 2D floating-point image
// by a constant factor.
class Example : public Halide::Generator<Example> {
 public:
  GeneratorParam<bool> vectorize_{"vectorize", true};
  GeneratorParam<bool> parallelize_{"parallelize", true};

  ImageParam input_{Float(32), 2, "input"};
  Param<float> scale_{"scale"};

  Func build() {
    Var x, y;

    Func output;
    output(x, y) = input_(x, y) * scale_;

    if (vectorize_) {
      output.vectorize(x, natural_vector_size<float>());
    }
    if (parallelize_) {
      output.parallel(y);
    }

    return output;
  }
};

Halide::RegisterGenerator<Example> register_example{"example"};

}  // namespace
```

`main.cpp`:


```C++
#include <cmath>
#include <cstdio>

#include "halide_image.h"
#include "example.h"  // Generated by Bazel via halide_library() rule

int main(int argc, char **argv) {
    constexpr int kEdge = 30;
    constexpr float kMax = kEdge * kEdge;

    Halide::Tools::Image<float> input(kEdge, kEdge);
    for (int x = 0; x < kEdge; ++x) {
        for (int y = 0; y < kEdge; ++y) {
            input(x, y) = static_cast<float>(x + y) / kMax;
        }
    }

    const float kScale = 0.5f;
    Halide::Tools::Image<float> output(kEdge, kEdge);
    int result = example(input, kScale, output);
    if (result != 0) {
      fprintf(stderr, "Failure: %d\n", result);
      return -1;
    }

    for (int x = 0; x < kEdge; ++x) {
        for (int y = 0; y < kEdge; ++y) {
            const float expected = input(x, y) * kScale;
            constexpr float kEpsilon = 0.00001f;
            if (fabs(expected - output(x, y)) > kEpsilon) {
              fprintf(stderr, "Expected %f, Got %f\n", expected, output(x, y));
              return -1;
            }
        }
    }

    printf("Success!\n");
    return 0;
}
```

Build and run:

```
$ bazel run :main
INFO: Found 1 target...
Target //:main up-to-date:
  bazel-bin/main
INFO: Elapsed time: 0.253s, Critical Path: 0.14s
INFO: Running command line: bazel-bin/main
Success!
```

## Cookbook

### What if my Generator requires other libraries?

Use generator_deps. For the example above:

`example_generator.cpp`:

```c++
#include "Halide.h"
#include "library_used_by_example.h"

...
```

`BUILD`:

```python
halide_library(
  name="example", 
  srcs=["example_generator.cpp"],
  generator_deps=["//path/to:library_used_by_example"]
)
```

### What if the Filter produced by my Generator requires other libraries?

Unless you are using Halide's define_extern() feature, it probably doesn't.
But in that case, use filter_deps:

`example_generator.cpp`:

```c++
#include "Halide.h"
class Example : public Halide::Generator<Example> {
  Func build() {
    ...
    Func external_function;
    external_function.define_extern("ExternCNameOfFunction", ...);
    ...
  }
};
...
```

`BUILD`:

```python
halide_library(
  name="example", 
  srcs=["example_generator.cpp"],
  filter_deps=["//path/to:library_with_ExternCNameOfFunction"]
)
```

### What if I want to produce multiple variants of a Filter from the same Generator?

You can customize the Filter produced by a Generator by filling in
generator_args, which sets the GeneratorParams before producing the Filter.
For instance, say we wanted to produce both vectorized and non-vectorized
versions of Example:

`BUILD`:

```python
halide_library(
  name="example", 
  srcs=["example_generator.cpp"],
  # Since the default value for "vectorize" is "true", we don't
  # need to set it explicitly, but we can if we want
  generator_args=["vectorize=true"],
)

halide_library(
  name="example_unvectorized", 
  srcs=["example_generator.cpp"],
  # Set the value of GeneratorParams here:
  generator_args=["vectorize=false"],
)

halide_library(
  name="example_unvectorized_nonparallel", 
  srcs=["example_generator.cpp"],
  # If you want to set multiple GeneratorParams, separate them with a space:
  generator_args=["vectorize=false parallel=false"],
)
```

This can be used in a data-driven way as well; if the Generator had an integer
GeneratorParam specifying (say) bit-depth, you could do something like:

`BUILD`:

```python
[halide_library(
  name="example_%d" % bit_depth,
  srcs=["example_generator.cpp"],
  generator_args=["bit_depth=%d" % bit_depth]) for bit_depth in [8, 16, 32]]
```


### What if I have multiple Generators in the same source file?

You can optionally specify generator_name to choose the Generator being built
(if there is only one Generator present, you can omit it):

`example_generator.cpp`:

```c++
#include "Halide.h"

class Example : public Halide::Generator<Example> {
...
};
Halide::RegisterGenerator<Example> register_example{"example"};

class AnotherExample : public Halide::Generator<AnotherExample> {
...
};
Halide::RegisterGenerator<AnotherExample> register_example{"another_example"};

```

`BUILD`:

```python
halide_library(
  name="example", 
  srcs=["example_generator.cpp"],
  generator_name=["example"],
)

# Note that the Bazel rule name need not match the generator_name
# (though this is usually considered the best practice)
halide_library(
  name="some_other_example", 
  srcs=["example_generator.cpp"],
  generator_name=["another_example"],
)
```

## SIMD Support

At present, this rule doesn't default to enabling SIMD support on some architectures;
most notably, it doesn't enable SSE4.1/AVX/etc. on Intel architectures. 
You can explicitly opt-in on a per-rule basis by adding halide_target_features, e.g.

```python
halide_library(name = "my_rule", srcs = "my_src.cpp", halide_target_features = [ "sse41", "avx" ])
```

Alternately, you can add defaults for the entire workspace:

```python
halide_configure(default_halide_target_features = [ "sse41", "avx" ])
```

## Configure Rules

```python
halide_configure(default_halide_target_features, http_archive_info, local_repository_path)
```

Both local_repository_path and http_archive_info are optional arguments; if you
specify neither, the rule will attempt to choose the most recent stable version
of Halide for the host architecture and use that.

*   **default_halide_target_features** *(List of strings; optional)* If present,
    this is a least of Halide::Target Features that should be added to *every*
    halide_library() instance.
*   **http_archive_info** *(Dict, optional)* If present, this should be a
    dictionary that maps each possible host architecture to a url and (optional)
    sha256. This allows you to specify a particular release of Halide for 
    building, rather than relying on the version chosen by halide_configure(), 
    which will vary over time. This dict should be of the form:
```python
    { 
        "darwin": { 
            "url": "https://path-to-darwin-halide-distrib.tgz", 
            "sha256": "optional-sha256-of-darwin-halide-distrib"
        }, 
        "k8": { 
            "url": "https://path-to-k8-halide-distrib.tgz", 
            "sha256": "optional-sha256-of-k8-halide-distrib"
        }, 
        "piii": { 
            "url": "https://path-to-piii-halide-distrib.tgz", 
            "sha256": "optional-sha256-of-piii-halide-distrib"
        }, 
    }
```
*   **local_repository_path** *(String, optional)* If present, this should point
    to the "distrib" folder of a locally-built instance of Halide. Most users
    will not ever want to use this option; it is useful primarily for situations
    in which you need to experiment with changes to the Halide library itself.

# Bazel Halide Build Rules

## Overview

These build rules are used for building Halide Generators with Bazel.

The *Generator* is the fundamental compilable unit of Halide used in Bazel.
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
    mandelbrot_generator.cpp
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
  name="mandelbrot", 
  srcs=["mandelbrot_generator.cpp"]
)

cc_binary(
    name = "main",
    srcs = ["main.cpp"],
    deps = [
      ":mandelbrot",
      "@halide_distrib//:halide_image"
    ],
)
```

`mandelbrot_generator.cpp`:

```c++
#include "Halide.h"

using namespace Halide;

namespace {

class Complex {
    Tuple t;

public:
    Complex(Expr real, Expr imag) : t(real, imag) {}
    Complex(Tuple tup) : t(tup) {}
    Complex(FuncRefExpr f) : t(Tuple(f)) {}
    Complex(FuncRefVar f) : t(Tuple(f)) {}
    Expr real() const { return t[0]; }
    Expr imag() const { return t[1]; }

    operator Tuple() const { return t; }
};

Complex operator+(const Complex &a, const Complex &b) {
    return Complex(a.real() + b.real(), a.imag() + b.imag());
}

Complex operator*(const Complex &a, const Complex &b) {
    return Complex(a.real() * b.real() - a.imag() * b.imag(),
                   a.real() * b.imag() + a.imag() * b.real());
}

Complex conjugate(const Complex &a) { return Complex(a.real(), -a.imag()); }

Expr magnitude(Complex a) { return (a * conjugate(a)).real(); }

class Mandelbrot : public Generator<Mandelbrot> {
public:
    Param<float> x_min{"x_min"};
    Param<float> x_max{"x_max"};
    Param<float> y_min{"y_min"};
    Param<float> y_max{"y_max"};
    Param<float> c_real{"c_real"};
    Param<float> c_imag{"c_imag"};
    Param<int> iters{"iters"};
    Param<int> w{"w"};
    Param<int> h{"h"};

    Func build() {
        Var x, y, z;

        Complex initial(lerp(x_min, x_max, cast<float>(x) / w),
                        lerp(y_min, y_max, cast<float>(y) / h));
        Complex c(c_real, c_imag);

        Func mandelbrot;
        mandelbrot(x, y, z) = initial;
        RDom t(1, iters);
        Complex current = mandelbrot(x, y, t - 1);
        mandelbrot(x, y, t) = current * current + c;

        // How many iterations until something escapes a circle of radius 2?
        Tuple escape = argmin(magnitude(mandelbrot(x, y, t)) < 4);

        // If it never escapes, use the value 0
        Func count;
        count(x, y) = select(escape[1], 0, escape[0]);

        Var xi, yi, xo, yo;
        mandelbrot.compute_at(count, xo);

        count.tile(x, y, xo, yo, xi, yi, 8, 8).parallel(yo).vectorize(xi, 4).unroll(xi).unroll(yi, 2);

        return count;
    }
};

RegisterGenerator<Mandelbrot> register_mandelbrot{"mandelbrot"};

}  // namespace
```

`main.cpp`:


```C++
#include <cmath>
#include <cstdio>

#include "halide_image.h"
#include "mandelbrot.h"  // Generated by halide_library() rule

int main(int argc, char **argv) {
    Halide::Tools::Image<int> output(100, 30);
    const char *code = " .:-~*={}&%#@";
    const int iters = strlen(code) - 1;

    // Compute a Julia set
    float t = 100.0f, fx = cos(t / 10.0f), fy = sin(t / 10.0f);
    int result = mandelbrot(-2.0f, 2.0f, -1.4f, 1.4f, fx, fy, iters, output.width(), output.height(),
               output);
    if (result != 0) {
      fprintf(stderr, "Failure: %d\n", result);
      return -1;
    }

    char buf[4096];
    char *buf_ptr = buf;
    for (int y = 0; y < output.height(); y++) {
        for (int x = 0; x < output.width(); x++) {
            *buf_ptr++ = code[output(x, y)];
        }
        *buf_ptr++ = '\n';
    }
    *buf_ptr++ = 0;
    printf("%s", buf);
    fflush(stdout);

    printf("Success!\n");
    return 0;
}
```

## SIMD Support

At present, this rule doesn't default to enabling SIMD support on some architectures;
most notable, it doesn't enable SSE4.1/AVX/etc. on Intel architectures. 
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
    building, rather than relying on the version that is chosen by
    halide_configure() and will vary over time. This dict should be of the form:
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

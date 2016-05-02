#include "Halide.h"

namespace {

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

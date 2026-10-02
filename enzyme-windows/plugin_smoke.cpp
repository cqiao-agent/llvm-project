#include <enzyme/enzyme>
#include <cmath>
#include <cstdio>

#ifndef ENZYME_VERSION_MAJOR
#error The Enzyme Clang frontend plugin did not inject its version macros.
#endif

extern "C" double __enzyme_autodiff(void *, ...);
double cube(double x) { return x * x * x; }

int main() {
    const double inputs[] = {-2.5, 0.0, 1.0, 3.25};
    int checks = 0;
    for (double x : inputs) {
        double forward = enzyme::get<0>(enzyme::autodiff<enzyme::Forward>(
            cube, enzyme::Duplicated{x, 1.0}));
        double reverse = __enzyme_autodiff(reinterpret_cast<void *>(cube), x);
        double expected = 3.0 * x * x;
        if (!std::isfinite(forward) || !std::isfinite(reverse) ||
            std::abs(forward - expected) > 1e-10 ||
            std::abs(reverse - expected) > 1e-10) return 1;
        checks += 2;
    }
    std::printf("{\"checks\":%d,\"failures\":0,\"virtual_headers\":true,\"frontend_macros\":true}\n", checks);
    return 0;
}

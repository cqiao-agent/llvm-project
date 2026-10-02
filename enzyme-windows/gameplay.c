// A tiny differentiable gameplay kernel, compiled to IR before running Enzyme.
#include <math.h>

extern int enzyme_dup;
extern int enzyme_const;
extern double __enzyme_autodiff(void *, ...);
extern double __enzyme_fwddiff(void *, ...);
#define EXPORT __declspec(dllexport)

EXPORT double square(double x) { return x * x; }
EXPORT double grad_square(double x) {
    return __enzyme_autodiff((void *)square, x);
}
EXPORT double forward_square(double x) {
    return __enzyme_fwddiff((void *)square, enzyme_dup, x, 1.0);
}

// state = [health, position, accumulated score].
// The loop count is supplied at runtime. The health threshold may change
// branches during a rollout; derivatives follow the executed branch.
EXPORT double gameplay_loss(double *state, double attack, int steps) {
    for (int i = 0; i < steps; ++i) {
        state[0] -= attack * 0.05;
        state[1] += sin(attack * 0.01) * 0.1;
        if (state[0] > 50.0)
            state[2] += state[1] * 0.02;
        else
            state[2] += state[1] * 0.04;
    }
    double residual = state[0] - 40.0;
    return residual * residual + state[1] * state[1] * 0.1 + state[2];
}

// dstate must initially be zero. On return it contains d(loss)/d(initial_state).
// The return value is d(loss)/d(attack). state is mutable scratch storage.
EXPORT double gameplay_grad(double *state, double *dstate, double attack, int steps) {
    return __enzyme_autodiff((void *)gameplay_loss,
                            enzyme_dup, state, dstate,
                            attack, enzyme_const, steps);
}

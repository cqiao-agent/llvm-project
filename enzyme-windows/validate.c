#include <math.h>
#include <stdio.h>
#include <string.h>

__declspec(dllimport) double square(double);
__declspec(dllimport) double grad_square(double);
__declspec(dllimport) double forward_square(double);
__declspec(dllimport) double gameplay_loss(double *, double, int);
__declspec(dllimport) double gameplay_grad(double *, double *, double, int);

static int checks = 0, failures = 0;
static double worst_scaled_error = 0.0;

static void check(const char *label, double actual, double expected, double tolerance) {
    double scaled = fabs(actual - expected) / (1.0 + fabs(expected));
    ++checks;
    if (scaled > worst_scaled_error) worst_scaled_error = scaled;
    if (!isfinite(actual) || !isfinite(expected) || scaled > tolerance) {
        ++failures;
        fprintf(stderr, "FAIL %s: actual=%.17g expected=%.17g\n", label, actual, expected);
    }
}

static double loss_copy(const double *initial, double attack, int steps) {
    double scratch[3];
    memcpy(scratch, initial, sizeof scratch);
    return gameplay_loss(scratch, attack, steps);
}

int main(void) {
    const double xs[] = {-3.0, 0.0, 2.0, 4.25};
    for (int i = 0; i < 4; ++i) {
        check("square", square(xs[i]), xs[i] * xs[i], 1e-12);
        check("reverse square", grad_square(xs[i]), 2.0 * xs[i], 1e-12);
        check("forward square", forward_square(xs[i]), 2.0 * xs[i], 1e-12);
    }
    const double states[][3] = {{100.0, 2.0, 1.0}, {45.0, -1.0, 0.0}, {55.13, 0.5, 3.0}};
    const int step_counts[] = {0, 1, 20, 64};
    const double attack = 8.3, h = 1e-5;
    for (int s = 0; s < 3; ++s) {
        for (int t = 0; t < 4; ++t) {
            int steps = step_counts[t];
            double scratch[3], dstate[3] = {0.0, 0.0, 0.0};
            memcpy(scratch, states[s], sizeof scratch);
            double da = gameplay_grad(scratch, dstate, attack, steps);
            double finite_da = (loss_copy(states[s], attack + h, steps) -
                                loss_copy(states[s], attack - h, steps)) / (2.0 * h);
            check("attack gradient", da, finite_da, 2e-6);
            for (int k = 0; k < 3; ++k) {
                double plus[3], minus[3];
                memcpy(plus, states[s], sizeof plus);
                memcpy(minus, states[s], sizeof minus);
                plus[k] += h;
                minus[k] -= h;
                double finite_ds = (loss_copy(plus, attack, steps) -
                                    loss_copy(minus, attack, steps)) / (2.0 * h);
                check("initial-state gradient", dstate[k], finite_ds, 2e-6);
            }
        }
    }
    // Confirm that the computed gradient improves this smooth local objective.
    double scratch[3], dstate[3] = {0.0, 0.0, 0.0};
    memcpy(scratch, states[0], sizeof scratch);
    double da = gameplay_grad(scratch, dstate, attack, 20);
    double before = loss_copy(states[0], attack, 20);
    double after = loss_copy(states[0], attack - 0.05 * da, 20);
    ++checks;
    if (!(after < before)) ++failures;
    printf("{\"checks\":%d,\"failures\":%d,\"max_scaled_error\":%.12g,"
           "\"loss_before\":%.12g,\"loss_after\":%.12g}\n",
           checks, failures, worst_scaled_error, before, after);
    return failures ? 1 : 0;
}

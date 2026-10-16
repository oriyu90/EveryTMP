// SPDX-License-Identifier: MIT
// Minimal, READ-ONLY AppleSMC client for EveryTMP.
//
// Only temperature reads are exposed; there is intentionally no write path
// (fan control and other SMC writes require a privileged helper and are
// out of scope for this app). All calls are synchronous and fast
// (a few milliseconds); call them from a background queue, never assuming
// success — every failure is reported with a non-zero return code and the
// caller must degrade gracefully (show "--°C", never crash).
#ifndef EVERY_TMP_CSMC_SHIM_H
#define EVERY_TMP_CSMC_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Open the AppleSMC connection. Idempotent; returns 0 on success.
int everytmp_smc_open(void);

/// Close the AppleSMC connection. Safe to call when not open.
void everytmp_smc_close(void);

/// Read one 4-character SMC key as degrees Celsius.
/// Returns 0 on success and stores the value in *outCelsius.
/// Any non-zero return means "unreadable" (missing key, unknown data type,
/// implausible value such as a parked-sensor sentinel, or no connection).
/// `key` must point to exactly 4 ASCII bytes (not NUL-terminated).
int everytmp_smc_read_temp(const char key[4], double *outCelsius);

#ifdef __cplusplus
}
#endif

#endif /* EVERY_TMP_CSMC_SHIM_H */

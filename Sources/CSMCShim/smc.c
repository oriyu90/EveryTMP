// SPDX-License-Identifier: MIT
// Read-only AppleSMC access for EveryTMP.
//
// The SMCKeyData layout and selector numbers below follow the long-standing
// de-facto SMC user-client interface used by open-source tools such as
// smcFanControl, Hot, MacMonitor and MacFanControl (all MIT-licensed).
// This file implements READS ONLY (key-info + read-bytes); there is no
// write-bytes path anywhere in this app.

#include "CSMCShim.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <string.h>

#define EVERY_SMC_KERNEL_INDEX 2
#define EVERY_SMC_CMD_READ_KEYINFO 9
#define EVERY_SMC_CMD_READ_BYTES 5

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    UInt16 release;
} EverySMCVer;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} EverySMCPLimit;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} EverySMCKeyInfo;

typedef struct {
    UInt32 key;
    EverySMCVer vers;
    EverySMCPLimit pLimit;
    EverySMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    char bytes[32];
} EverySMCData;

static io_connect_t gConn = IO_OBJECT_NULL;

int everytmp_smc_open(void) {
    if (gConn != IO_OBJECT_NULL) {
        return 0;
    }
    mach_port_t masterPort = MACH_PORT_NULL;
    if (IOMainPort(MACH_PORT_NULL, &masterPort) != kIOReturnSuccess) {
        return -1;
    }
    CFMutableDictionaryRef matching = IOServiceMatching("AppleSMC");
    if (matching == NULL) {
        return -2;
    }
    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(masterPort, matching, &iter) != kIOReturnSuccess) {
        return -3;
    }
    io_service_t device = IOIteratorNext(iter);
    IOObjectRelease(iter);
    if (device == IO_OBJECT_NULL) {
        return -4; // No AppleSMC service (e.g. not a Mac with SMC).
    }
    kern_return_t kr = IOServiceOpen(device, mach_task_self(), 0, &gConn);
    IOObjectRelease(device);
    if (kr != kIOReturnSuccess) {
        gConn = IO_OBJECT_NULL;
        return -5;
    }
    return 0;
}

void everytmp_smc_close(void) {
    if (gConn != IO_OBJECT_NULL) {
        IOServiceClose(gConn);
        gConn = IO_OBJECT_NULL;
    }
}

static kern_return_t everySMCCall(EverySMCData *inData, EverySMCData *outData) {
    size_t inSize = sizeof(EverySMCData);
    size_t outSize = sizeof(EverySMCData);
    return IOConnectCallStructMethod(
        gConn, EVERY_SMC_KERNEL_INDEX, inData, inSize, outData, &outSize);
}

int everytmp_smc_read_temp(const char key[4], double *outCelsius) {
    if (gConn == IO_OBJECT_NULL || key == NULL || outCelsius == NULL) {
        return -1;
    }
    const UInt32 code = ((UInt32)(UInt8)key[0] << 24)
        | ((UInt32)(UInt8)key[1] << 16)
        | ((UInt32)(UInt8)key[2] << 8)
        | (UInt32)((UInt8)key[3]);

    EverySMCData input;
    EverySMCData output;

    // Step 1: ask the SMC for the key's data size and type.
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = code;
    input.data8 = EVERY_SMC_CMD_READ_KEYINFO;
    if (everySMCCall(&input, &output) != kIOReturnSuccess) {
        return -2;
    }
    const UInt32 dataSize = output.keyInfo.dataSize;
    const UInt32 dataType = output.keyInfo.dataType;
    if (dataSize == 0 || dataSize > 32) {
        return -3;
    }

    // Step 2: read the raw bytes.
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = code;
    input.keyInfo.dataSize = dataSize;
    input.data8 = EVERY_SMC_CMD_READ_BYTES;
    if (everySMCCall(&input, &output) != kIOReturnSuccess) {
        return -4;
    }

    // Step 3: decode by data type. SMC integers are big-endian.
    const char t0 = (char)(dataType >> 24);
    const char t1 = (char)(dataType >> 16);
    const char t2 = (char)(dataType >> 8);
    const char t3 = (char)dataType;
    const UInt8 b0 = (UInt8)output.bytes[0];
    const UInt8 b1 = (UInt8)output.bytes[1];

    double value = 0.0;
    if (t0 == 's' && t1 == 'p' && t2 == '7' && t3 == '8') {
        // sp78: signed 8.8 fixed point — the type Apple Silicon
        // temperature keys (TCMz, TRDX, …) report.
        if (dataSize < 2) {
            return -5;
        }
        const int16_t raw = (int16_t)((UInt16)(((UInt16)b0 << 8) | b1));
        value = (double)raw / 256.0;
    } else if (t0 == 'f' && t1 == 'l' && t2 == 't' && t3 == ' ') {
        // flt: IEEE-754 float in native byte order. This is the type all
        // Apple Silicon temperature keys (TCMz, TRDX, …) report — verified
        // live on M2 (MacMonitor vs mactop) and on M3 Ultra (this project).
        // Do NOT byte-swap: swapping yields plausible-looking but wrong
        // values (e.g. a real 64.9 °C misdecoded as 0.4 °C).
        if (dataSize < 4) {
            return -5;
        }
        float f = 0.0f;
        memcpy(&f, output.bytes, sizeof(f));
        value = (double)f;
    } else if (t0 == 'f' && t1 == 'p' && t2 == 'e' && t3 == '2') {
        // fpe2: big-endian unsigned 14.2 fixed point (Intel-era temps).
        if (dataSize < 2) {
            return -5;
        }
        const UInt16 raw = (UInt16)(((UInt16)b0 << 8) | b1);
        value = (double)raw / 4.0;
    } else {
        return -6; // Unknown data type: refuse to guess.
    }

    // Step 4: plausibility gate. A powered die sensor at or below 10 °C is
    // a parked/off sensor — idle clusters report sentinels (~4.6 °C,
    // ~6.7 °C) or clamp at exactly 10.00 °C (verified on M3 Ultra) — and
    // anything above 125 °C is outside every Apple Silicon operating
    // envelope. Reject both instead of displaying them.
    if (!(value > 10.0 && value <= 125.0)) {
        return -7;
    }
    *outCelsius = value;
    return 0;
}

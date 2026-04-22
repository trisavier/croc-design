// // Copyright (c) 2024 ETH Zurich and University of Bologna.
// // Licensed under the Apache License, Version 2.0, see LICENSE for details.
// // SPDX-License-Identifier: Apache-2.0
// //
// // Authors:
// // - Philippe Sauter <phsauter@iis.ee.ethz.ch>

// #include "uart.h"
// #include "print.h"
// #include "config.h"

// int main() {
//     uart_init();
//     printf("Hello World from Croc!\n");
//     uart_write_flush();
//     return 0;
// }

// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// I2C Hello Example
// Sends the string "HELLO" over I2C to a slave device.
// Debug output is printed via UART.
// I2C bus activity is captured by the testbench I2C slave monitor.

#include "uart.h"
#include "print.h"
#include "i2c.h"
#include "util.h"
#include "config.h"

// I2C slave address (7-bit) - typical EEPROM or I2C device
#define I2C_SLAVE_ADDR   0x50

// Prescaler for 100kHz SCL at 20MHz system clock
// SCL = sys_clk / (5 * (prescale + 1)) = 20MHz / (5 * 40) = 100kHz
#define I2C_PRESCALE_VAL 39

int main() {
    int ret;

    // Initialize UART for debug output
    uart_init();
    printf("=== I2C HELLO Example ===\n");

    // -------------------------------------------------------
    // Step 1: Initialize and verify I2C peripheral registers
    // -------------------------------------------------------
    printf("Init I2C...\n");
    i2c_init(I2C_PRESCALE_VAL);

    // Read back prescaler register to verify
    uint32_t prescale_rb = *reg32(I2C_BASE_ADDR, I2C_PRESCALE_OFFSET);
    printf("Prescaler: 0x%x\n", (unsigned int)prescale_rb);
    if (prescale_rb != I2C_PRESCALE_VAL) {
        printf("FAIL: prescaler\n");
        uart_write_flush();
        return 1;
    }

    // Read back control register
    uint32_t ctrl_rb = *reg32(I2C_BASE_ADDR, I2C_CTRL_OFFSET);
    printf("Control: 0x%x\n", (unsigned int)ctrl_rb);
    if (!(ctrl_rb & I2C_CTRL_EN)) {
        printf("FAIL: not enabled\n");
        uart_write_flush();
        return 1;
    }

    // Read status register - should be idle
    uint32_t status = *reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET);
    printf("Status: 0x%x\n", (unsigned int)status);

    printf("I2C ready\n");

    // -------------------------------------------------------
    // Step 2: Send "HELLO" as multi-byte I2C write
    // -------------------------------------------------------
    // The testbench I2C slave monitor will log:
    //   [I2C] START condition detected
    //   [I2C] Address: 0x50, R/W: 0 (WRITE)
    //   [I2C] Slave ACK (address phase)
    //   [I2C] Data byte 0: 0x48 ('H')
    //   [I2C] Data byte 1: 0x45 ('E')
    //   [I2C] Data byte 2: 0x4C ('L')
    //   [I2C] Data byte 3: 0x4C ('L')
    //   [I2C] Data byte 4: 0x4F ('O')
    //   [I2C] STOP condition detected

    const uint8_t hello[] = {'H', 'E', 'L', 'L', 'O'};

    printf("Sending HELLO...\n");
    ret = i2c_write(I2C_SLAVE_ADDR, hello, 5);

    if (ret == 0) {
        printf("Write OK (ACK)\n");
    } else if (ret == -1) {
        printf("Write NACK (no slave)\n");
    } else {
        printf("Write ERR: %x\n", (unsigned int)ret);
    }

    // Read status after write
    status = *reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET);
    printf("Post-write status: 0x%x\n", (unsigned int)status);

    // -------------------------------------------------------
    // Step 3: Cleanup
    // -------------------------------------------------------
    i2c_disable();

    // Verify disabled
    ctrl_rb = *reg32(I2C_BASE_ADDR, I2C_CTRL_OFFSET);
    printf("Ctrl after disable: 0x%x\n", (unsigned int)ctrl_rb);

    printf("=== DONE ===\n");
    uart_write_flush();
    return 0;
}

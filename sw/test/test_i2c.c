// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// I2C Basic Test
// Tests I2C peripheral initialization and register access.

#include "i2c.h"
#include "util.h"
#include "print.h"
#include "uart.h"

#define I2C_TEST_PRESCALE   39    // 100kHz SCL at 20MHz sys_clk
#define I2C_TEST_SLAVE_ADDR 0x50  // Typical EEPROM address

int main(void) {
    int ret;
    uint8_t data;

    uart_init();
    printf("I2C Test Start\n");

    // Test 1: Initialize I2C
    printf("  Init I2C...\n");
    i2c_init(I2C_TEST_PRESCALE);

    // Verify prescaler was set correctly
    uint32_t prescale_val = *reg32(I2C_BASE_ADDR, I2C_PRESCALE_OFFSET);
    if (prescale_val != I2C_TEST_PRESCALE) {
        printf("  FAIL: prescaler mismatch\n");
        return 1;
    }
    printf("  Prescaler OK\n");

    // Verify control register
    uint32_t ctrl_val = *reg32(I2C_BASE_ADDR, I2C_CTRL_OFFSET);
    if (!(ctrl_val & I2C_CTRL_EN)) {
        printf("  FAIL: I2C not enabled\n");
        return 1;
    }
    printf("  Control OK\n");

    // Test 2: Write to TX register and read back
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = 0xA5;
    uint32_t tx_val = *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET);
    if ((tx_val & 0xFF) != 0xA5) {
        printf("  FAIL: TX data mismatch\n");
        return 1;
    }
    printf("  TX reg OK\n");

    // Test 3: Read status register (should show idle)
    uint32_t status_val = *reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET);
    if (status_val & I2C_STATUS_TIP) {
        printf("  FAIL: unexpected TIP\n");
        return 1;
    }
    printf("  Status OK\n");

    // Test 4: Try to write to a slave (will NACK if no slave connected)
    printf("  Write byte...\n");
    ret = i2c_write_byte(I2C_TEST_SLAVE_ADDR, 0x42);
    if (ret == 0) {
        printf("  Write ACK (slave found)\n");
    } else if (ret == -1) {
        printf("  Write NACK (no slave, expected in sim)\n");
    } else {
        printf("  Write error (arb lost)\n");
    }

    // Test 5: Try to read from a slave
    printf("  Read byte...\n");
    ret = i2c_read_byte(I2C_TEST_SLAVE_ADDR, &data);
    if (ret == 0) {
        printf("  Read OK\n");
    } else if (ret == -1) {
        printf("  Read NACK (no slave, expected in sim)\n");
    } else {
        printf("  Read error (arb lost)\n");
    }

    // Disable I2C
    i2c_disable();

    printf("I2C Test Done\n");
    uart_write_flush();
    return 0;
}

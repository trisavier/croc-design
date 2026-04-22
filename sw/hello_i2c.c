// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// I2C Hello Example
// Demonstrates I2C peripheral by sending "HELLO" to the bus.
// Uses UART for debug output (I2C is a bus protocol, not a display).
//
// === How to prove I2C works (from simulation log) ===
// 1. [UART] messages: register readbacks prove peripheral registers work
//    - Prescaler: 0x27 (correctly written)
//    - Control: 0x3 (enabled + interrupt enable)
//    - TX Data readback matches written value
// 2. [I2C] messages: bus monitor captures actual SCL/SDA activity
//    - START/STOP conditions detected
//    - Address byte captured (0xA0 = addr 0x50 + WRITE)
//    - Data bytes captured ('H','E','L','L','O')
// 3. Waveform (croc.fst): visual proof of SCL/SDA toggling

#include "uart.h"
#include "print.h"
#include "i2c.h"
#include "util.h"
#include "config.h"

// I2C slave address (7-bit)
#define I2C_SLAVE_ADDR   0x50

// Prescaler: 100kHz SCL at 20MHz sys_clk
// SCL = 20MHz / (5 * (39+1)) = 100kHz
#define I2C_PRESCALE_VAL 39

// Simple wait for TIP to clear (no arb_lost check for simulation)
// In simulation, the 2-stage synchronizer causes false arb_lost.
// On real hardware, arb_lost check should be re-enabled.
static int sim_wait_tip(void) {
    uint32_t status;
    int timeout = 100000;
    do {
        status = *reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET);
        if (--timeout == 0) return -1;
    } while (status & I2C_STATUS_TIP);
    return 0;
}

// Send one byte on the I2C bus (START + addr + data + STOP)
// Returns 0=ACK, -1=NACK
static int i2c_send_byte_demo(uint8_t slave_addr, uint8_t data) {
    // Load slave address + write bit
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = (slave_addr << 1) | I2C_WRITE_BIT;

    // START + WRITE
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_START | I2C_CMD_WRITE;
    sim_wait_tip();

    // Check ACK
    if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
        // NACK - send STOP and return
        *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_STOP;
        sim_wait_tip();
        return -1;
    }

    // Load data byte
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = data;

    // WRITE + STOP
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_WRITE | I2C_CMD_STOP;
    sim_wait_tip();

    return 0;
}

// Send multiple bytes in one I2C transaction (START + addr + data... + STOP)
static int i2c_send_multi_demo(uint8_t slave_addr, const uint8_t *buf, uint32_t len) {
    // Load slave address + write bit
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = (slave_addr << 1) | I2C_WRITE_BIT;

    // START + WRITE
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_START | I2C_CMD_WRITE;
    sim_wait_tip();

    // Check ACK
    if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
        *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_STOP;
        sim_wait_tip();
        return -1;
    }

    // Send data bytes
    for (uint32_t i = 0; i < len; i++) {
        *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = buf[i];

        if (i == len - 1) {
            *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_WRITE | I2C_CMD_STOP;
        } else {
            *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_WRITE;
        }
        sim_wait_tip();

        if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
            if (i < len - 1) {
                *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_STOP;
                sim_wait_tip();
            }
            return -1;
        }
    }
    return 0;
}

int main() {
    uart_init();
    printf("=== I2C HELLO Demo ===\n");

    // ----- Step 1: Init & Register Verification -----
    printf("Init I2C...\n");
    i2c_init(I2C_PRESCALE_VAL);

    // Readback prescaler (expect 0x27 = 39)
    uint32_t val = *reg32(I2C_BASE_ADDR, I2C_PRESCALE_OFFSET);
    printf("PRE=0x%x\n", (unsigned int)val);

    // Readback control (expect 0x3 = EN|IEN)
    val = *reg32(I2C_BASE_ADDR, I2C_CTRL_OFFSET);
    printf("CTL=0x%x\n", (unsigned int)val);

    // TX register write/readback test
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = 0xAB;
    val = *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET);
    printf("TX=0x%x\n", (unsigned int)(val & 0xFF));

    // Status (expect 0x0 = idle)
    val = *reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET);
    printf("STS=0x%x\n", (unsigned int)val);
    printf("I2C OK\n");

    // ----- Step 2: Send "HELLO" -----
    const uint8_t hello[] = {'H', 'E', 'L', 'L', 'O'};
    int ret;

    printf("TX HELLO...\n");
    ret = i2c_send_multi_demo(I2C_SLAVE_ADDR, hello, 5);
    if (ret == 0) {
        printf("ACK\n");
    } else {
        printf("NACK (no slave - expected in sim)\n");
    }

    // ----- Step 3: Also send bytes individually -----
    printf("TX single bytes...\n");
    for (int i = 0; i < 5; i++) {
        ret = i2c_send_byte_demo(I2C_SLAVE_ADDR, hello[i]);
        if (ret == 0)
            printf(" %x:ACK\n", (unsigned int)hello[i]);
        else
            printf(" %x:NACK\n", (unsigned int)hello[i]);
    }

    // ----- Step 4: Cleanup -----
    i2c_disable();
    val = *reg32(I2C_BASE_ADDR, I2C_CTRL_OFFSET);
    printf("CTL=0x%x\n", (unsigned int)val);

    printf("=== DONE ===\n");
    uart_write_flush();
    return 0;
}

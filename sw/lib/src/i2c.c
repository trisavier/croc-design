// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// I2C Master Driver Implementation

#include "i2c.h"
#include "util.h"

void i2c_init(uint16_t prescale) {
    // Disable core first
    *reg32(I2C_BASE_ADDR, I2C_CTRL_OFFSET) = 0;

    // Set prescaler
    *reg32(I2C_BASE_ADDR, I2C_PRESCALE_OFFSET) = prescale;

    // Enable core with interrupts enabled
    *reg32(I2C_BASE_ADDR, I2C_CTRL_OFFSET) = I2C_CTRL_EN | I2C_CTRL_IEN;
}

int i2c_wait_tip(void) {
    uint32_t status;
    do {
        status = *reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET);
        // Check for arbitration lost
        if (status & I2C_STATUS_AL) {
            // Clear AL flag by writing 1
            *reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) = I2C_STATUS_AL;
            return -1;
        }
    } while (status & I2C_STATUS_TIP);
    return 0;
}

int i2c_write_byte(uint8_t slave_addr, uint8_t data) {
    int ret;

    // Load slave address with write bit
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = (slave_addr << 1) | I2C_WRITE_BIT;

    // Generate START + WRITE command
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_START | I2C_CMD_WRITE;

    // Wait for transfer to complete
    ret = i2c_wait_tip();
    if (ret < 0) return -2;

    // Check for NACK
    if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
        // Slave NACKed - send STOP
        *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_STOP;
        i2c_wait_tip();
        return -1;
    }

    // Load data byte
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = data;

    // WRITE + STOP command
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_WRITE | I2C_CMD_STOP;

    // Wait for transfer to complete
    ret = i2c_wait_tip();
    if (ret < 0) return -2;

    // Check for NACK
    if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
        return -1;
    }

    return 0;
}

int i2c_read_byte(uint8_t slave_addr, uint8_t *data) {
    int ret;

    // Load slave address with read bit
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = (slave_addr << 1) | I2C_READ_BIT;

    // Generate START + WRITE command (address phase)
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_START | I2C_CMD_WRITE;

    // Wait for address phase to complete
    ret = i2c_wait_tip();
    if (ret < 0) return -2;

    // Check for NACK (slave not responding)
    if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
        *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_STOP;
        i2c_wait_tip();
        return -1;
    }

    // READ with NACK (last byte) + STOP
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_READ | I2C_CMD_NACK | I2C_CMD_STOP;

    // Wait for read to complete
    ret = i2c_wait_tip();
    if (ret < 0) return -2;

    // Read received data
    *data = (uint8_t)*reg32(I2C_BASE_ADDR, I2C_RX_DATA_OFFSET);

    return 0;
}

int i2c_write(uint8_t slave_addr, const uint8_t *buf, uint32_t len) {
    int ret;

    if (len == 0) return 0;

    // Load slave address with write bit
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = (slave_addr << 1) | I2C_WRITE_BIT;

    // Generate START + WRITE command
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_START | I2C_CMD_WRITE;

    ret = i2c_wait_tip();
    if (ret < 0) return -2;

    if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
        *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_STOP;
        i2c_wait_tip();
        return -1;
    }

    // Write data bytes
    for (uint32_t i = 0; i < len; i++) {
        *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = buf[i];

        if (i == len - 1) {
            // Last byte: WRITE + STOP
            *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_WRITE | I2C_CMD_STOP;
        } else {
            // Intermediate byte: WRITE only
            *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_WRITE;
        }

        ret = i2c_wait_tip();
        if (ret < 0) return -2;

        if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
            if (i < len - 1) {
                *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_STOP;
                i2c_wait_tip();
            }
            return -1;
        }
    }

    return 0;
}

int i2c_read(uint8_t slave_addr, uint8_t *buf, uint32_t len) {
    int ret;

    if (len == 0) return 0;

    // Load slave address with read bit
    *reg32(I2C_BASE_ADDR, I2C_TX_DATA_OFFSET) = (slave_addr << 1) | I2C_READ_BIT;

    // Generate START + WRITE command (address phase)
    *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_START | I2C_CMD_WRITE;

    ret = i2c_wait_tip();
    if (ret < 0) return -2;

    if (*reg32(I2C_BASE_ADDR, I2C_STATUS_OFFSET) & I2C_STATUS_RXACK) {
        *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_STOP;
        i2c_wait_tip();
        return -1;
    }

    // Read data bytes
    for (uint32_t i = 0; i < len; i++) {
        if (i == len - 1) {
            // Last byte: READ + NACK + STOP
            *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_READ | I2C_CMD_NACK | I2C_CMD_STOP;
        } else {
            // Intermediate byte: READ with ACK
            *reg32(I2C_BASE_ADDR, I2C_CMD_OFFSET) = I2C_CMD_READ;
        }

        ret = i2c_wait_tip();
        if (ret < 0) return -2;

        buf[i] = (uint8_t)*reg32(I2C_BASE_ADDR, I2C_RX_DATA_OFFSET);
    }

    return 0;
}

void i2c_disable(void) {
    *reg32(I2C_BASE_ADDR, I2C_CTRL_OFFSET) = 0;
}

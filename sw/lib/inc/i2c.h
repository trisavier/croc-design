// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// I2C Master Driver Header

#pragma once

#include <stdint.h>
#include "config.h"

// Register offsets from I2C_BASE_ADDR
#define I2C_PRESCALE_OFFSET 0x00
#define I2C_CTRL_OFFSET     0x04
#define I2C_TX_DATA_OFFSET  0x08
#define I2C_RX_DATA_OFFSET  0x0C
#define I2C_CMD_OFFSET      0x10
#define I2C_STATUS_OFFSET   0x14

// Control register bits
#define I2C_CTRL_EN         (1 << 0)  // I2C core enable
#define I2C_CTRL_IEN        (1 << 1)  // Interrupt enable

// Command register bits
#define I2C_CMD_START       (1 << 0)  // Generate START condition
#define I2C_CMD_STOP        (1 << 1)  // Generate STOP condition
#define I2C_CMD_READ        (1 << 2)  // Read from slave
#define I2C_CMD_WRITE       (1 << 3)  // Write to slave
#define I2C_CMD_NACK        (1 << 4)  // Send NACK after read (vs ACK)

// Status register bits
#define I2C_STATUS_TIP      (1 << 0)  // Transfer in progress
#define I2C_STATUS_IF       (1 << 1)  // Interrupt flag
#define I2C_STATUS_RXACK    (1 << 2)  // Received ACK from slave (0=ACK, 1=NACK)
#define I2C_STATUS_AL       (1 << 3)  // Arbitration lost
#define I2C_STATUS_BUSY     (1 << 4)  // I2C bus busy

// I2C address direction bits
#define I2C_WRITE_BIT       0x00
#define I2C_READ_BIT        0x01

/**
 * Initialize I2C peripheral with given prescaler value.
 * SCL frequency = sys_clk / (5 * (prescale + 1))
 *
 * For 20MHz system clock:
 *   prescale = 39  -> 100kHz (Standard Mode)
 *   prescale = 9   -> 400kHz (Fast Mode)
 */
void i2c_init(uint16_t prescale);

/**
 * Wait for current I2C transfer to complete.
 * Returns 0 on success, -1 on arbitration lost.
 */
int i2c_wait_tip(void);

/**
 * Write a single byte to an I2C slave device.
 * @param slave_addr 7-bit slave address
 * @param data byte to write
 * @return 0 on ACK, -1 on NACK, -2 on arbitration lost
 */
int i2c_write_byte(uint8_t slave_addr, uint8_t data);

/**
 * Read a single byte from an I2C slave device.
 * @param slave_addr 7-bit slave address
 * @param data pointer to store read byte
 * @return 0 on success, -1 on NACK, -2 on arbitration lost
 */
int i2c_read_byte(uint8_t slave_addr, uint8_t *data);

/**
 * Write multiple bytes to an I2C slave device.
 * @param slave_addr 7-bit slave address
 * @param buf pointer to data buffer
 * @param len number of bytes to write
 * @return 0 on success, negative on error
 */
int i2c_write(uint8_t slave_addr, const uint8_t *buf, uint32_t len);

/**
 * Read multiple bytes from an I2C slave device.
 * @param slave_addr 7-bit slave address
 * @param buf pointer to receive buffer
 * @param len number of bytes to read
 * @return 0 on success, negative on error
 */
int i2c_read(uint8_t slave_addr, uint8_t *buf, uint32_t len);

/**
 * Disable the I2C peripheral.
 */
void i2c_disable(void);

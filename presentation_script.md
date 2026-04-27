# 🎓 BÀI THUYẾT TRÌNH — Final Project CE2024 Module 2
## Tích hợp I2C Master Peripheral vào SoC RISC-V CROC

> **Thời lượng mục tiêu:** 10–12 phút | **Repo:** github.com/trisavier/croc-design

---

## 📋 SLIDE 1 — Tổng quan dự án (2 phút)

### Nói:

> "Dạ thưa thầy/cô, đề tài của em là **tích hợp ngoại vi I2C Master vào SoC RISC-V có sẵn**, cụ thể là platform CROC của PULP Platform (ETH Zurich).
>
> Em **không thiết kế SoC từ đầu**, mà chọn cách tiếp cận thực tế hơn — giống quy trình công nghiệp — là nhận một SoC base đã có sẵn rồi mở rộng thêm ngoại vi.
>
> SoC CROC sử dụng **CPU CV32E40P** (trước đây gọi là CVE2), hỗ trợ tập lệnh **RV32IMC**, được target cho **PDK IHP SG13G2 — công nghệ 130nm**."

### Điểm nhấn kỹ thuật:

| Thành phần | Chi tiết |
|---|---|
| **SoC base** | pulp-platform/croc (ETH Zurich) |
| **CPU Core** | CV32E40P (RISC-V RV32IMC) |
| **Bus** | OBI (Open Bus Interface) |
| **Clock** | 100 MHz target (10ns period) |
| **PDK** | IHP SG13G2 (130nm BiCMOS) |
| **Ngoại vi thêm** | I2C Master (Standard 100kHz / Fast 400kHz) |

### Lý do chọn hướng tích hợp:
- Gần với workflow thực tế trong industry (IP integration)
- Phải hiểu bus protocol, address map, interrupt routing
- Chứng minh khả năng đọc hiểu và sửa đổi RTL có sẵn

---

## 📋 SLIDE 2 — Kiến trúc tích hợp (3 phút)

### Nói:

> "Về kiến trúc, I2C peripheral được tích hợp vào **peripheral bus** của SoC thông qua giao thức **OBI** (Open Bus Interface). Em đã thêm I2C vào address map, kết nối interrupt line, và route tín hiệu I/O ra I/O pad."

### 2.1 — Address Map (Memory-Mapped I/O)

I2C được đăng ký tại index `PeriphI2C = 9` trong peripheral demux:

```
Peripheral Address Map:
─────────────────────────────────────────
Debug Module    0x0000_0000 – 0x0004_0000
Boot ROM        0x0200_0000 – 0x0200_4000
CLINT           0x0204_0000 – 0x0208_0000
SoC Control     0x0300_0000 – 0x0300_1000
UART            0x0300_2000 – 0x0300_3000
GPIO            0x0300_5000 – 0x0300_6000
Timer           0x0300_A000 – 0x0300_B000
iDMA            0x0300_B000 – 0x0300_C000
★ I2C Master    0x0300_C000 – 0x0300_D000  ← MỚI
─────────────────────────────────────────
```

> File: [croc_pkg.sv](file:///home/minhtri/eda/designs/test1/croc/rtl/croc_pkg.sv#L141-L155)

### 2.2 — Interrupt Routing

```
interrupts[0] = obi_timer_irq
interrupts[1] = uart_irq
interrupts[2] = gpio_irq
interrupts[3] = idma_irq
interrupts[4] = i2c_irq       ← MỚI — nối trực tiếp vào CV32E40P
```

> File: [croc_domain.sv](file:///home/minhtri/eda/designs/test1/croc/rtl/croc_domain.sv#L68-L78)

### 2.3 — I2C Module Instance

```systemverilog
obi_i2c #(
  .ObiCfg    ( SbrObiCfg     ),
  .obi_req_t ( sbr_obi_req_t ),
  .obi_rsp_t ( sbr_obi_rsp_t )
) i_i2c (
  .clk_i, .rst_ni,
  .obi_req_i ( i2c_obi_req ),    // từ peripheral demux
  .obi_rsp_o ( i2c_obi_rsp ),    // trả response về bus
  .irq_o     ( i2c_irq     ),    // interrupt → CPU
  .scl_o, .scl_oe_o, .scl_i,    // SCL pad interface
  .sda_o, .sda_oe_o, .sda_i     // SDA pad interface
);
```

### 2.4 — I/O Pad (Bidirectional Open-Drain)

SCL và SDA dùng cơ chế **open-drain**: output enable kéo pin xuống LOW, pull-up resistor kéo lên HIGH.

```
scl_o    = 1'b0                 // luôn drive LOW khi enabled
scl_oe_o = ~scl_out_q & i2c_en // OE=1 → kéo LOW; OE=0 → thả (pull-up)
```

### 2.5 — FSM điều khiển I2C (14 states)

```
ST_IDLE → ST_START_A → ST_START_B
       → ST_WRITE_BIT ↔ ST_WRITE_WAIT → ST_ACK_READ → ST_ACK_RWAIT
       → ST_READ_BIT  ↔ ST_READ_WAIT  → ST_ACK_SEND → ST_ACK_WAIT
       → ST_STOP_A    → ST_STOP_B     → ST_STOP_C   → ST_IDLE
```

> File: [obi_i2c.sv](file:///home/minhtri/eda/designs/test1/croc/rtl/obi_i2c/obi_i2c.sv#L148-L163) — FSM enum definition

---

## 📋 SLIDE 3 — Kết quả RTL & Simulation (2 phút)

### Nói:

> "Em sử dụng **Verilator** để mô phỏng toàn bộ SoC. Firmware C chạy trên CPU sẽ ghi/đọc thanh ghi I2C rồi gửi chuỗi 'HELLO' qua bus I2C. Một **Passive Bus Monitor** trong testbench quan sát tín hiệu SCL/SDA."

### 3.1 — Kết quả mô phỏng (UART console)

```
[UART] === I2C HELLO Demo ===
[UART] Init I2C...
[UART] PRE=0x27        ← Prescaler = 39 → SCL = 20MHz/(5×40) = 100kHz
[UART] CTL=0x3         ← Control: Enable + Interrupt Enable
[UART] TX=0xAB         ← Ghi/đọc thanh ghi TX đúng
[UART] STS=0x0         ← Status idle, sẵn sàng
[UART] I2C OK

[I2C] === START condition ===     ← Bus Monitor phát hiện START
[UART]  48:ACK                    ← 0x48 = 'H'
[UART]  45:ACK                    ← 0x45 = 'E'
[UART]  4C:ACK                    ← 0x4C = 'L'
[UART]  4C:ACK                    ← 0x4C = 'L'
[UART]  4F:ACK                    ← 0x4F = 'O'
[I2C] === STOP condition ===      ← Bus Monitor phát hiện STOP

[JTAG] Simulation finished: SUCCESS
```

### 3.2 — Waveform GTKWave

Waveform xác nhận:
- **SCL**: xung clock đều, đúng tần số 100kHz
- **SDA**: thay đổi data khi SCL LOW, stable khi SCL HIGH
- **START**: SDA ↓ trong khi SCL HIGH
- **STOP**: SDA ↑ trong khi SCL HIGH
- **ACK**: slave kéo SDA LOW trong clock thứ 9
- **Interrupt**: `irq_o` assert sau mỗi byte transfer hoàn tất

### 3.3 — Xử lý Arbitration Lost (false positive)

> Trong simulation, bộ đồng bộ 2-stage synchronizer gây trễ 2 chu kỳ clock → master đọc SDA cũ → phát hiện nhầm Arbitration Lost. Em viết hàm `sim_wait_tip()` để bypass trong sim mà không ảnh hưởng phần cứng thật.

---

## 📋 SLIDE 4 — ASIC Flow IHP 130nm (3 phút)

### Nói:

> "Em đã chạy hoàn chỉnh ASIC backend flow với bộ công cụ mã nguồn mở: **Yosys** cho synthesis, **OpenROAD** cho Place & Route, và **KLayout** cho GDSII export. Target PDK là **IHP SG13G2 — 130nm**."

### 4.1 — Toolchain Flow

```
RTL (SystemVerilog)
    │
    ▼  Yosys (Logic Synthesis)
Gate-level Netlist
    │
    ▼  OpenROAD (Floorplan → Place → CTS → Route)
    │   01_floorplan → 02_placed → 03_cts → 04_routed → 05_final
    │
    ▼  KLayout (GDSII Export)
Physical Layout → Tapeout-ready
```

### 4.2 — Timing Report (Final) ✅

| Metric | Giá trị | Đánh giá |
|---|---|---|
| **WNS (Worst Negative Slack)** | **0.00 ns** | ✅ Không vi phạm |
| **TNS (Total Negative Slack)** | **0.00 ns** | ✅ Không vi phạm |
| **Worst Slack (max)** | **1.23 ns** | ✅ Positive margin |
| **Critical Path Delay** | **2.19 ns** | — |
| **Critical Path Slack** | **1.23 ns** | ✅ 55.9% margin |
| **Setup Violations** | **0** | ✅ Clean |
| **Hold Violations** | **0** | ✅ Clean |

> File: [05_croc.final.rpt](file:///home/minhtri/eda/designs/test1/croc/openroad/reports/05_croc.final.rpt#L8-L20)

### 4.3 — Area Report

| Metric | Giá trị |
|---|---|
| **Die Area** | 3,671,056 µm² (≈ 1.92mm × 1.92mm) |
| **Core Area** | 1,571,082 µm² |
| **Total Active Area** | 845,993 µm² |
| **Core Utilization** | 53.8% |
| **Std Cell Utilization** | 42.9% |

**Phân bổ area theo hierarchy:**

| Block | Area (µm²) | Instances | Ghi chú |
|---|---|---|---|
| **CV32E40P Core** | 227,304 | 13,548 | Bao gồm Register File (99,629 µm²) |
| **SRAM Bank 0** | 152,211 | 227 | Macro 150,102 µm² |
| **SRAM Bank 1** | 152,258 | 234 | Macro 150,102 µm² |
| **Debug Module** | 78,926 | 5,487 | — |
| **UART** | 47,795 | 2,434 | — |
| **JTAG/DMI** | 39,899 | 2,266 | — |
| **GPIO** | 28,791 | 1,546 | — |
| **CLINT** | 15,947 | 879 | — |
| ★ **I2C Master** | **10,770** | **616** | Nhỏ gọn, hiệu quả |
| **Timer** | 10,654 | 623 | — |

> File: [05_croc.final.rpt](file:///home/minhtri/eda/designs/test1/croc/openroad/reports/05_croc.final.rpt#L1046-L1149)

### 4.4 — Power Report

| Category | Power (mW) | % |
|---|---|---|
| Sequential | 22.9 | 46.3% |
| Macro (SRAM) | 16.0 | 32.3% |
| Clock Network | 6.56 | 13.3% |
| Pad | 3.14 | 6.3% |
| Combinational | 0.87 | 1.8% |
| **Total** | **49.5** | **100%** |

### 4.5 — DRC Report

- Chỉ còn **3 violations** loại Metal Spacing trên Layer Metal4
- Đều liên quan đến net VSS gần routing congestion
- Không ảnh hưởng chức năng, có thể fix bằng manual ECO hoặc tăng routing margin

> File: [04_croc_route_drc.rpt-5.rpt](file:///home/minhtri/eda/designs/test1/croc/openroad/reports/04_croc_route_drc.rpt-5.rpt)

---

## 📋 SLIDE 5 — Kết luận (1 phút)

### Nói:

> "Tóm lại, dự án này đã chứng minh khả năng **tích hợp ngoại vi vào SoC thực tế** sử dụng hoàn toàn công cụ EDA mã nguồn mở:
>
> - **RTL**: viết I2C Master bằng SystemVerilog, tích hợp qua OBI bus
> - **Verification**: mô phỏng Verilator với firmware C, xác nhận bằng Bus Monitor
> - **ASIC**: chạy full flow Yosys → OpenROAD → KLayout trên PDK IHP 130nm
> - **Kết quả**: WNS/TNS = 0, không setup/hold violation, I2C chỉ chiếm 10,770 µm² (616 cells)
>
> Repo tại github.com/trisavier/croc-design. Em xin hết ạ."

---

## 🛡️ CHUẨN BỊ TRẢ LỜI CÂU HỎI KỸ THUẬT

---

### ❓ Q1: OBI Bus Protocol là gì? Tại sao không dùng AXI hay APB?

**Trả lời:**

> "OBI — Open Bus Interface — là giao thức bus do PULP Platform phát triển, được tối ưu cho các SoC nhỏ dùng RISC-V. So với AXI:
>
> - **Đơn giản hơn nhiều**: chỉ cần `req`, `gnt`, `rvalid` — không có channel phức tạp (AW, W, B, AR, R)
> - **Latency thấp**: transaction chỉ cần 2 phase (Address + Response)
> - **Phù hợp** với in-order core như CV32E40P
>
> SoC CROC đã dùng OBI sẵn cho tất cả peripheral, nên em tích hợp I2C theo cùng protocol để giữ tính nhất quán. Nếu dùng APB thì phải thêm OBI-to-APB bridge → tốn thêm area và latency."

### ❓ Q2: I2C FSM hoạt động như thế nào?

**Trả lời:**

> "FSM có 14 states, hoạt động theo cơ chế prescale-tick. Mỗi SCL cycle được chia thành **5 phase** (low-hold, rise, high-hold, fall, done), mỗi phase dài `prescale + 1` clock cycles.
>
> Flow cơ bản cho WRITE:
> ```
> IDLE → START_A (SDA=1, SCL=1)
>      → START_B (SDA↓, SCL=1 → START condition)
>      → WRITE_BIT (SCL=0, set SDA = MSB)
>      → WRITE_WAIT (SCL=1, slave samples)
>      → lặp 8 lần
>      → ACK_READ (release SDA)
>      → ACK_RWAIT (SCL=1, đọc ACK từ slave)
>      → IDLE hoặc STOP
> ```
>
> Prescaler tính: `PRE = Fclk / (5 × Fscl) - 1`. Ví dụ: 20MHz / (5 × 100kHz) - 1 = 39."

### ❓ Q3: Timing closure — tại sao WNS = 0?

**Trả lời:**

> "WNS = 0 nghĩa là **không có path nào vi phạm timing**. Worst slack thực tế là **+1.23 ns** — tức là path chậm nhất vẫn còn dư 1.23 ns so với yêu cầu.
>
> Critical path đi qua debug module (`dmi_cdc → dm_csrs.progbuf`), không phải I2C. Điều này hợp lý vì I2C FSM chỉ là sequential logic đơn giản — mỗi cycle chỉ update state register và shift register.
>
> Clock tree synthesis (CTS) và post-route optimization của OpenROAD đã tự động chèn buffer để đảm bảo cả setup và hold timing. Final report xác nhận: **0 setup violations, 0 hold violations**."

### ❓ Q4: Tại sao chọn IHP 130nm thay vì SkyWater 130nm?

**Trả lời:**

> "Có 3 lý do chính:
>
> 1. **SoC CROC được thiết kế cho IHP**: platform CROC của PULP đã có sẵn scripts, constraints, và pad ring cho IHP SG13G2. Nếu chuyển sang SkyWater phải rewrite toàn bộ backend flow.
>
> 2. **PDK chất lượng cao hơn**: IHP SG13G2 là công nghệ BiCMOS, có standard cell library hoàn chỉnh (`sg13g2_stdcell`) với timing models cho nhiều corners (ff, tt, ss). SkyWater 130nm PDK vẫn còn một số limitations.
>
> 3. **Được hỗ trợ bởi IHP open-source program**: IHP cung cấp PDK miễn phí cho nghiên cứu và giáo dục, với khả năng tapeout thực tế thông qua chương trình MPW."

### ❓ Q5: Lỗi max_slew, max_fanout, max_cap có ảnh hưởng không?

**Trả lời:**

> "Trong final report có 117 slew violations, 202 fanout violations, 201 cap violations. Tuy nhiên:
>
> - Đây chủ yếu là **I/O pad connections** — pad cells có capacitance rất lớn (~15pF cho output pad), gây ra slew/cap violations ở boundary. Đây là đặc thù của IHP pad library.
> - **Không ảnh hưởng đến timing closure**: WNS/TNS = 0, không setup/hold violation.
> - Trong production flow, sẽ thêm **I/O buffer cells** hoặc adjust drive strength để fix hoàn toàn."

### ❓ Q6: Arbitration Lost là gì? Tại sao xảy ra trong sim?

**Trả lời:**

> "Arbitration Lost xảy ra khi master muốn drive SDA HIGH nhưng đọc lại thấy SDA LOW — nghĩa là có master khác đang chiếm bus.
>
> Trong simulation, bộ **2-stage synchronizer** gây trễ 2 clock cycles. Master ghi SDA = 1, nhưng khi đọc lại qua synchronizer thì vẫn thấy giá trị cũ (SDA = 0) → nhận nhầm là Arbitration Lost.
>
> Trên phần cứng thật, vì I2C clock rất chậm (100kHz) so với system clock (20MHz), synchronizer latency không đáng kể. Em đã viết hàm `sim_wait_tip()` để workaround trong simulation."

### ❓ Q7: 3 DRC violations còn lại có fix được không?

**Trả lời:**

> "3 violations đều là Metal Spacing trên Layer Metal4, nằm gần net VSS. Nguyên nhân là routing congestion cục bộ gần SRAM macros. Có thể fix bằng:
> - Tăng halo xung quanh SRAM macro
> - Tăng routing layer spacing constraint
> - Manual ECO trong KLayout
>
> Trong academic context, 3 minor spacing violations trên toàn bộ chip 3.67 mm² là chấp nhận được."

---

## 📊 TÓM TẮT SỐ LIỆU QUAN TRỌNG (Quick Reference)

| Metric | Giá trị |
|---|---|
| SoC | CROC (PULP Platform) |
| CPU | CV32E40P — RV32IMC |
| PDK | IHP SG13G2 130nm |
| I2C Area | 10,770 µm² / 616 cells |
| Total Die | 3,671,056 µm² (≈ 1.92 × 1.92 mm) |
| WNS / TNS | 0.00 / 0.00 |
| Setup / Hold violations | 0 / 0 |
| Total Power | 49.5 mW |
| DRC violations | 3 (Metal Spacing, non-critical) |
| I2C Speed | 100kHz (Standard) / 400kHz (Fast) |
| FSM States | 14 states |
| Prescaler formula | PRE = Fclk / (5 × Fscl) − 1 |
| I2C Base Address | 0x0300_C000 |
| Interrupt Line | interrupts[4] |

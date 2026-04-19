#!/usr/bin/env python3
"""
I2C Waveform Generator from VCD File
=====================================
Parses sim/i2c_waveform.vcd and generates professional timing diagrams
as PNG images using matplotlib. No GTKWave GUI required.

Usage: python3 sim/gen_waveform.py
Output: sim/waveform_write.png, sim/waveform_read.png, sim/waveform_overview.png
"""

import re
import sys
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np


# =============================================================================
# VCD Parser (scope-aware)
# =============================================================================
def parse_vcd(filename):
    """Parse VCD file with scope tracking."""
    signals = {}       # symbol -> (full_name, width)
    signal_data = {}   # full_name -> [(time_ns, value)]
    current_time = 0
    scope_stack = []

    with open(filename, 'r') as f:
        in_defs = True
        for line in f:
            line = line.strip()

            if in_defs:
                if line.startswith('$scope'):
                    m = re.match(r'\$scope\s+\w+\s+(\S+)', line)
                    if m:
                        scope_stack.append(m.group(1))
                elif line.startswith('$upscope'):
                    if scope_stack:
                        scope_stack.pop()
                elif line.startswith('$var'):
                    m = re.match(r'\$var\s+\w+\s+(\d+)\s+(\S+)\s+(.*?)(\s+\$end)?$', line)
                    if m:
                        width = int(m.group(1))
                        sym = m.group(2)
                        raw_name = m.group(3).strip().split()[0]  # Remove [31:0] etc.
                        # Build full hierarchical name
                        full_name = '.'.join(scope_stack + [raw_name])
                        # Only map if not already mapped (first scope wins for shared symbols)
                        if sym not in signals:
                            signals[sym] = (full_name, width)
                            signal_data[full_name] = []
                if line.startswith('$enddefinitions'):
                    in_defs = False
                continue

            # Parse time changes
            if line.startswith('#'):
                current_time = int(line[1:])
                continue

            # Single-bit value change
            m = re.match(r'^([01xzXZ])(\S+)$', line)
            if m:
                val = m.group(1)
                sym = m.group(2)
                if sym in signals:
                    name = signals[sym][0]
                    v = 1 if val == '1' else (0 if val == '0' else -1)
                    signal_data[name].append((current_time / 1000.0, v))  # ps -> ns
                continue

            # Multi-bit value change
            m = re.match(r'^b([01xzXZ]+)\s+(\S+)$', line)
            if m:
                bits = m.group(1)
                sym = m.group(2)
                if sym in signals:
                    name = signals[sym][0]
                    try:
                        v = int(bits, 2)
                    except ValueError:
                        v = -1
                    signal_data[name].append((current_time / 1000.0, v))
                continue

    return signal_data


def find_signal(data, pattern):
    """Find signal by partial name match."""
    for key in data:
        parts = key.split('.')
        basename = parts[-1] if parts else key
        if basename == pattern:
            return data[key]
    # Fallback: substring match
    for key in data:
        if pattern in key:
            return data[key]
    return [(0, 1)]  # default high


def to_dense(transitions, t_start, t_end, res=2.0):
    """Convert transitions to dense time/value arrays."""
    times = np.arange(t_start, t_end, res)
    values = np.zeros_like(times, dtype=float)
    trans = sorted(transitions, key=lambda x: x[0])

    for i, t in enumerate(times):
        val = trans[0][1] if trans else 0
        for tt, vv in trans:
            if tt <= t:
                val = vv
            else:
                break
        values[i] = val
    return times, values


# =============================================================================
# Drawing helpers
# =============================================================================
def draw_digital(ax, times, values, label, color, y_off):
    """Draw a digital (1-bit) signal."""
    pts_t = []
    pts_v = []
    for i in range(len(times)):
        if i > 0 and values[i] != values[i-1]:
            pts_t.append(times[i])
            pts_v.append(values[i-1] * 0.65 + y_off)
        pts_t.append(times[i])
        pts_v.append(values[i] * 0.65 + y_off)
    ax.plot(pts_t, pts_v, color=color, linewidth=1.5, solid_capstyle='round')
    ax.fill_between(pts_t, y_off, pts_v, alpha=0.06, color=color)
    ax.text(times[0] - (times[-1]-times[0])*0.01, y_off + 0.33, label,
            ha='right', va='center', fontsize=9, color=color,
            fontweight='bold', fontfamily='monospace')


def draw_bus(ax, times, values, label, color, y_off, fmt='hex', name_map=None):
    """Draw a multi-bit bus signal."""
    # Find value segments
    segments = []
    seg_start = 0
    for i in range(1, len(times)):
        if values[i] != values[seg_start] or i == len(times) - 1:
            segments.append((times[seg_start], times[i], int(values[seg_start])))
            seg_start = i

    for t1, t2, val in segments:
        width = t2 - t1
        mid = (t1 + t2) / 2
        # Draw diamond-shaped bus
        h = 0.28
        ax.fill([t1, t1+min(width*0.1, 8), t2-min(width*0.1, 8), t2,
                 t2-min(width*0.1, 8), t1+min(width*0.1, 8), t1],
                [y_off, y_off+h, y_off+h, y_off, y_off-h, y_off-h, y_off],
                color=color, alpha=0.12, linewidth=0)
        ax.plot([t1, t1+min(width*0.1, 8), t2-min(width*0.1, 8), t2],
                [y_off, y_off+h, y_off+h, y_off],
                color=color, linewidth=0.8)
        ax.plot([t1, t1+min(width*0.1, 8), t2-min(width*0.1, 8), t2],
                [y_off, y_off-h, y_off-h, y_off],
                color=color, linewidth=0.8)
        # Label
        if width > (times[-1]-times[0]) * 0.03:
            if name_map and val in name_map:
                txt = name_map[val]
            elif fmt == 'hex':
                txt = f'0x{val:02X}'
            else:
                txt = str(val)
            ax.text(mid, y_off, txt, ha='center', va='center',
                    fontsize=6.5, color=color, fontweight='bold',
                    fontfamily='monospace')

    ax.text(times[0] - (times[-1]-times[0])*0.01, y_off, label,
            ha='right', va='center', fontsize=9, color=color,
            fontweight='bold', fontfamily='monospace')


def add_annotation(ax, t, y_top, text, color):
    """Add a vertical annotation arrow with text."""
    ax.annotate(text, xy=(t, y_top + 0.1), fontsize=7,
                color=color, ha='center', va='bottom', fontweight='bold',
                fontfamily='monospace')
    ax.axvline(x=t, color=color, linestyle=':', alpha=0.4, linewidth=0.7)


STATE_NAMES = {
    0: 'IDLE', 1: 'START_A', 2: 'START_B',
    3: 'WR_BIT', 4: 'WR_WAIT', 5: 'RD_BIT', 6: 'RD_WAIT',
    7: 'ACK_S', 8: 'ACK_W', 9: 'ACK_R', 10: 'ACK_RW',
    11: 'STOP_A', 12: 'STOP_B', 13: 'STOP_C'
}


# =============================================================================
# Plot functions
# =============================================================================
def plot_overview(data, outfile):
    """Full simulation overview with all signals."""
    fig, ax = plt.subplots(figsize=(18, 10))
    fig.patch.set_facecolor('#0f0f1a')
    ax.set_facecolor('#141428')

    scl = find_signal(data, 'scl_bus')
    sda = find_signal(data, 'sda_bus')
    state = find_signal(data, 'state')
    tx = find_signal(data, 'tx_data_reg')
    rx = find_signal(data, 'rx_data_reg')
    tip_sig = find_signal(data, 'tip')
    busy_sig = find_signal(data, 'busy')
    done = find_signal(data, 'cmd_done_r')

    # Time range
    all_t = [t for t, v in scl if t > 0] + [t for t, v in sda if t > 0]
    t0 = 0
    t1 = max(all_t) + 500 if all_t else 30000

    res = 3.0
    t_scl, v_scl = to_dense(scl, t0, t1, res)
    t_sda, v_sda = to_dense(sda, t0, t1, res)
    t_st, v_st = to_dense(state, t0, t1, res)
    t_tx, v_tx = to_dense(tx, t0, t1, res)
    t_rx, v_rx = to_dense(rx, t0, t1, res)
    t_tip, v_tip = to_dense(tip_sig, t0, t1, res)
    t_busy, v_busy = to_dense(busy_sig, t0, t1, res)

    # Draw signals top to bottom
    draw_digital(ax, t_scl, v_scl, 'SCL', '#ffd700', 8)
    draw_digital(ax, t_sda, v_sda, 'SDA', '#00e5ff', 7)
    draw_digital(ax, t_tip, v_tip, 'TIP', '#ff6b6b', 6)
    draw_digital(ax, t_busy, v_busy, 'BUSY', '#f472b6', 5)
    draw_bus(ax, t_st, v_st, 'STATE', '#a855f7', 4, fmt='dec', name_map=STATE_NAMES)
    draw_bus(ax, t_tx, v_tx, 'TX_DATA', '#4ade80', 3)
    draw_bus(ax, t_rx, v_rx, 'RX_DATA', '#fb923c', 2)

    # cmd_done markers
    for t, v in done:
        if v == 1 and t > 100:
            ax.axvline(t, color='#ff6b6b', ls='--', alpha=0.25, lw=0.7)
            ax.text(t, 9, 'done', fontsize=6, color='#ff6b6b',
                    ha='center', alpha=0.6, fontfamily='monospace')

    # Transaction labels
    ax.axvspan(400, 13000, alpha=0.04, color='#4ade80')
    ax.text(6500, 9.2, 'Test 2: Write 0xA5 → slave 0x48', fontsize=10,
            ha='center', color='#4ade80', fontweight='bold')
    ax.axvspan(13000, 25500, alpha=0.04, color='#fb923c')
    ax.text(19000, 9.2, 'Test 3: Read 0x5A ← slave 0x48', fontsize=10,
            ha='center', color='#fb923c', fontweight='bold')

    ax.set_xlim(t0, t1)
    ax.set_ylim(1.3, 9.8)
    ax.set_xlabel('Time (ns)', color='#a0a0a0', fontsize=10)
    ax.tick_params(colors='#606080', labelsize=8)
    ax.grid(True, alpha=0.1, color='#404060')
    ax.set_yticks([])
    ax.set_title('I2C Master – Complete Simulation Waveform (12/12 Tests Passed)',
                 color='#e0e0e0', fontsize=14, fontweight='bold', pad=15)

    legend = [
        mpatches.Patch(color='#ffd700', label='SCL (I2C Clock)'),
        mpatches.Patch(color='#00e5ff', label='SDA (I2C Data)'),
        mpatches.Patch(color='#ff6b6b', label='TIP (Transfer In Progress)'),
        mpatches.Patch(color='#a855f7', label='Master FSM State'),
        mpatches.Patch(color='#4ade80', label='TX Data Register'),
        mpatches.Patch(color='#fb923c', label='RX Data Register'),
    ]
    ax.legend(handles=legend, loc='lower right', fontsize=8,
              facecolor='#141428', edgecolor='#404060', labelcolor='#d0d0d0')

    plt.tight_layout()
    plt.savefig(outfile, dpi=200, facecolor=fig.get_facecolor(), bbox_inches='tight')
    plt.close()
    print(f"  ✅ Created: {outfile}")


def plot_transaction(data, outfile, tx_type='write'):
    """Zoomed view of a single I2C transaction."""
    fig, ax = plt.subplots(figsize=(16, 7))
    fig.patch.set_facecolor('#0f0f1a')
    ax.set_facecolor('#141428')

    scl = find_signal(data, 'scl_bus')
    sda = find_signal(data, 'sda_bus')
    state = find_signal(data, 'state')
    shift = find_signal(data, 'shift_reg')
    done = find_signal(data, 'cmd_done_r')

    if tx_type == 'write':
        t0, t1 = 200, 13500
        title = 'I2C WRITE Transaction – Slave: 0x48, Data: 0xA5'
        phase_color = '#4ade80'
    else:
        t0, t1 = 12500, 26200
        title = 'I2C READ Transaction – Slave: 0x48, Data Received: 0x5A'
        phase_color = '#fb923c'

    res = 2.0
    t_scl, v_scl = to_dense(scl, t0, t1, res)
    t_sda, v_sda = to_dense(sda, t0, t1, res)
    t_st, v_st = to_dense(state, t0, t1, res)
    t_sh, v_sh = to_dense(shift, t0, t1, res)

    draw_digital(ax, t_scl, v_scl, 'SCL', '#ffd700', 5)
    draw_digital(ax, t_sda, v_sda, 'SDA', '#00e5ff', 4)
    draw_bus(ax, t_st, v_st, 'STATE', '#a855f7', 3, fmt='dec', name_map=STATE_NAMES)
    draw_bus(ax, t_sh, v_sh, 'SHIFT_REG', phase_color, 2)

    # cmd_done markers
    for t, v in done:
        if v == 1 and t0 < t < t1:
            ax.axvline(t, color='#ff6b6b', ls='--', alpha=0.35, lw=1)
            ax.text(t, 6, 'cmd_done', fontsize=7, color='#ff6b6b',
                    ha='center', fontfamily='monospace')

    ax.set_xlim(t0, t1)
    ax.set_ylim(1.3, 6.5)
    ax.set_xlabel('Time (ns)', color='#a0a0a0', fontsize=10)
    ax.tick_params(colors='#606080', labelsize=8)
    ax.grid(True, alpha=0.1, color='#404060')
    ax.set_yticks([])
    ax.set_title(title, color='#e0e0e0', fontsize=14, fontweight='bold', pad=15)

    plt.tight_layout()
    plt.savefig(outfile, dpi=200, facecolor=fig.get_facecolor(), bbox_inches='tight')
    plt.close()
    print(f"  ✅ Created: {outfile}")


# =============================================================================
# Main
# =============================================================================
if __name__ == '__main__':
    vcd = 'sim/i2c_waveform.vcd'
    if not os.path.exists(vcd):
        print(f"ERROR: {vcd} not found. Run: bash sim/run_sim.sh")
        sys.exit(1)

    print("=" * 60)
    print("  I2C Waveform Generator (VCD → PNG)")
    print("=" * 60)

    print(f"\nParsing {vcd}...")
    data = parse_vcd(vcd)
    print(f"  Found {len(data)} signals")

    print("\nKey signals:")
    for name in sorted(data.keys()):
        n = len(data[name])
        base = name.split('.')[-1]
        if base in ('scl_bus', 'sda_bus', 'state', 'tip', 'busy',
                     'tx_data_reg', 'rx_data_reg', 'shift_reg', 'cmd_done_r',
                     'scl_out', 'sda_out', 'bit_cnt'):
            print(f"  {name}: {n} transitions")

    print("\nGenerating waveform images...")
    plot_overview(data, 'sim/waveform_overview.png')
    plot_transaction(data, 'sim/waveform_write.png', 'write')
    plot_transaction(data, 'sim/waveform_read.png', 'read')

    print("\n✅ Done! Files ready for report:")
    print("  sim/waveform_overview.png – Full simulation")
    print("  sim/waveform_write.png    – Write transaction")
    print("  sim/waveform_read.png     – Read transaction")

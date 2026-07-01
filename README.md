# UART Implementation on Sipeed Tang Nano 9K

This repository builds on the UART implementation for the Sipeed Tang Nano 9K FPGA by Lushay Labs. The code from the initial commit matches the tutorial at:  
https://learn.lushaylabs.com/tang-nano-9k-debugging/#transmitting-data

A number of features have been added on top of the tutorial baseline, described below.

---

## Hardware

| | |
|---|---|
| **Board** | Sipeed Tang Nano 9K (Gowin GW1NR-9C) |
| **Clock** | 27 MHz onboard oscillator |
| **USB bridge** | BL702 — handles both JTAG programming and UART communication over a single USB-C connection |
| **Baud rate** | 115,200 |

The BL702 enumerates as two serial devices on the host. The higher-numbered `/dev/tty.*` device (macOS) is the UART port used for communication.

---

## Features added

### 1. Stop bit framing error detection

The tutorial's `RX_STATE_STOP_BIT` state does not actually verify the stop bit. It waits a full UART frame (`DELAY_FRAMES` clock cycles) and unconditionally asserts `byteReady`, regardless of the line state — even if the byte was malformed due to noise, clock drift, or a genuine transmission error.

This implementation adds proper stop bit verification. `uart_rx` is sampled at the midpoint of the stop bit frame, using the same stable-centre approach used for all data bits. Based on what is read:

- If `uart_rx == 1` (correct): `byteReady` is asserted and the byte is available for use.
- If `uart_rx == 0` (incorrect): `frameError` is asserted instead and `byteReady` is **not** set, preventing downstream logic from silently consuming a corrupt byte.

`frameError` and `byteReady` are mutually exclusive — a byte is either valid or flagged as an error, never both. `frameError` is cleared automatically when a new start bit is detected.

---

### 2. Echo: received bytes mirrored back over TX

Each valid received byte is transmitted back over UART, enabling a connected host to verify round-trip communication. This required solving a timing problem that only appears with multi-byte messages.

#### First attempt: rising edge detection on `byteReady`

The initial approach triggered a TX cycle on the rising edge of `byteReady`. This worked correctly for single isolated bytes but failed silently for back-to-back multi-byte messages.

The failure mode: receiving and transmitting a byte each take exactly 10 bit periods (one full UART frame), and both run simultaneously. When the second byte finishes being received, the `byteReady` edge fires while TX is still busy sending the first byte. A one-cycle-delayed copy of `byteReady` (`byteReadyPrev`) is used to detect the rising edge — but over the course of transmitting the first byte, `byteReadyPrev` catches up to `byteReady`. By the time TX returns to idle, both signals are high, the rising edge is no longer visible, and the second byte is silently dropped. The pattern repeats, so only every other byte is echoed.

```
RX:          [  h  ][  e  ][  l  ][  l  ]
byteReady:        ↑      ↑      ↑      ↑     (brief pulse at end of each byte)
TX (broken):       [  h  ]       [  l  ]
                         ↑ TX busy when e's edge fires → e dropped
                                        ↑ TX busy when 2nd l's edge fires → dropped
Output: h, l   (every other byte)
```

#### Fix: `byteConsumed` flag

Rather than reacting directly to the edge, the rising edge of `byteReady` resets a `byteConsumed` flag to `0`. The TX state machine then starts a transmission whenever `byteReady == 1` and `byteConsumed == 0`, immediately setting `byteConsumed = 1` to prevent re-transmitting the same byte. This decouples _detecting that a new byte arrived_ from _TX being available to send it_: even if the edge fires while TX is busy, `byteConsumed` has been reset and TX will pick up the byte as soon as it returns to idle.

```
RX:        [  h  ][  e  ][  l  ][  l  ]
byteReady:       ↑      ↑      ↑      ↑
TX (fixed):       [  h  ][  e  ][  l  ][  l  ]
Output: h, e, l, l   (all bytes echoed in order)
```

> **Limitation**: this is a single-byte buffer. If a new byte were to be fully received before TX picks up the previous one, `dataIn` would be overwritten and the earlier byte lost. A FIFO queue would be required for robust arbitrary-rate streaming.

---

### 3. Parity bit (configurable odd/even)

Both RX and TX now include a parity bit between the 8 data bits and the stop bit, adding basic single-bit error detection on top of the framing check from feature 1.

Parity polarity is set via the `PARITY_ODD` module parameter (`0` = even parity, `1` = odd parity), defaulting to even. Being a parameter rather than a hardcoded value, it can be overridden by whichever module instantiates `uart` without touching `uart.v` itself.

- **RX**: a new `RX_STATE_PARITY_BIT` state sits between `RX_STATE_READ` and `RX_STATE_STOP_BIT`. It samples `uart_rx` at the bit's midpoint (the same stable-centre timing used for data bits) and computes `parityError <= ^{dataIn, uart_rx} ^ PARITY_ODD` — XOR-reducing the received byte together with the parity bit, then flipping the result if odd parity is configured, so `parityError` goes high whenever the received parity doesn't match what's expected. `byteReady` is only asserted if the stop bit is valid **and** `parityError` is clear. Like `frameError`, `parityError` is cleared when a new start bit is detected.
- **TX**: a new `TX_STATE_PARITY_BIT` state sits between `TX_STATE_WRITE` and `TX_STATE_STOP_BIT`. It drives `uart_tx` with `^dataOut ^ PARITY_ODD`, computing the correct parity bit for whatever byte is being sent, whether from `testMemory` or echoed back via `dataIn`.

> **Note**: `parityError` only suppresses `byteReady` for that byte — it doesn't affect framing detection or recovery, and the receiver returns to `RX_STATE_IDLE` normally to await the next byte.

---

## Testbench

`uart_tb.v` provides simulation-based verification without requiring the board. It overrides `DELAY_FRAMES` to `8` (instead of `234`) so a full byte frame takes only 16 simulation time units, making waveforms easy to inspect. The testbench drives a synthetic byte stream into `uart_rx` and dumps a VCD file.

**Run with Icarus Verilog** (included in oss-cad-suite):

```bash
iverilog -o sim uart_tb.v uart.v && vvp sim
```

This produces `uart.vcd`, which can be opened in VaporView (VS Code extension) to inspect all internal signals including `rxState`, `txState`, `byteReady`, `frameError`, and `dataIn`.

**To test framing error detection**: change the stop bit in the testbench from `1` to `0` and confirm that `frameError` asserts high and `byteReady` does not.

---

## Python test script

`serial_uart.py` uses `pyserial` to send bytes over serial and verify the echo response.

**Install dependency:**
```bash
pip3 install pyserial
```

**Run:**
```bash
python3 serial_uart.py
```

Update the `port` variable in the script to match your UART device. On macOS, list available ports with:
```bash
ls /dev/tty.*
```

> Note: close any open serial monitors (e.g. CoolTerm) before running the script. Serial ports are exclusive — only one process can hold the connection at a time.

---

## Project structure

```
.
├── top.v              # Top-level wrapper (synthesis entry point)
├── uart.v             # UART RX/TX state machine
├── uart_tb.v          # Verilog simulation testbench
├── tangnano9k.cst     # Pin constraints
├── serial_uart.py     # Python echo verification script
└── README.md
```
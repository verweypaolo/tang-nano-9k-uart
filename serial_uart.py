import serial
import time


ser = serial.Serial(
    port='/dev/tty.usbserial-11101',  # your UART port, not the JTAG one
    baudrate=115200,
    timeout=1  # 1 second read timeout
)

ser.write(bytes([0b00000001]))
time.sleep(0.5)

test_bytes = [0x41, 0x42, 0x43]  # 'A', 'B', 'C'

for byte in test_bytes:
    ser.write(bytes([byte]))
    echo = ser.read(1)  # block until 1 byte received or timeout
    
    if len(echo) == 0:
        print(f"Sent: {chr(byte)!r}  Got back: TIMEOUT (nothing received)")
    elif echo[0] == byte:
        print(f"Sent: {chr(byte)!r}  Got back: {chr(echo[0])!r}  ✓")
    else:
        print(f"Sent: {chr(byte)!r}  Got back: {chr(echo[0])!r}  ✗ MISMATCH")
    
    time.sleep(0.1)  # small gap between bytes

ser.close()
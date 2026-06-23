import serial
import time

ser = serial.Serial(
    port='/dev/tty.usbserial-11301',
    baudrate=115200,
    timeout=1,
)

patterns = [
    (~(1 << i)) & 0x3F
    for i in range(6)
]

for pattern in patterns:
    ser.write(bytes([pattern]))
    time.sleep(0.5)

ser.close()
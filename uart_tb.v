`default_nettype none

module test();

reg clk = 0;
reg uart_rx = 1;
wire uart_tx;
wire [5:0] led;
reg btn = 1;

// Override BAUD_DIVISOR to 8 so each bit period = 16 time units (8 cycles x 2 tu/cycle).
// ACC_INCREMENT=3, ACC_MODULUS=8 gives the same fractional ratio as the real 27MHz/115200
// configuration, so the accumulator behaviour is identical, just much faster to simulate.
uart #(
    .ACC_INCREMENT(3),
    .ACC_MODULUS(8),
    .BAUD_DIVISOR(8),
    .PARITY_ODD(0)
) u (
    .clk(clk),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .led(led),
    .btn1(btn)
);

always #1 clk = ~clk;

// Send one complete UART frame (start + 8 data bits + parity + stop).
// Bit order: LSB first. Each bit held for 16 time units (one BAUD_DIVISOR=8 period).
// 'a' = 0b01100001, bits LSB first: 1,0,0,0,0,1,1,0
// three 1s in data -> even parity bit = 1
task send_frame;
    input [7:0] data;
    input       parity_bit;
    input       stop_bit;
    integer i;
    begin
        uart_rx = 0;          // start bit
        #16;
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx = data[i]; // LSB first
            #16;
        end
        uart_rx = parity_bit;
        #16;
        uart_rx = stop_bit;
        #16;
        uart_rx = 1;          // return to idle
    end
endtask

initial begin
    $dumpfile("uart.vcd");
    $dumpvars(0, test);

    $display("=== UART testbench ===");
    $monitor(
        "t=%0t  byteReady=%b  parityError=%b  frameError=%b  dataIn=%b  led=%b  rxAcc=%0d  rxDelay=%0d",
        $time,
        u.byteReady,
        u.parityError,
        u.frameError,
        u.dataIn,
        led,
        u.rxAccumulator,
        u.rxDelayFrames
    );

    // ----------------------------------------------------------------
    // Test 1: correct byte with correct even parity
    // 'a' = 0b01100001, parity=1 (three 1s -> even parity bit = 1), stop=1
    // Expected: byteReady=1, parityError=0, frameError=0, led reflects dataIn
    // ----------------------------------------------------------------
    $display("\n--- Test 1: correct byte, correct parity ---");
    #10;
    send_frame(8'b01100001, 1, 1);
    #40; // wait for state machine to settle

    // ----------------------------------------------------------------
    // Test 2: correct byte with wrong parity bit
    // 'a' = 0b01100001, correct even parity=1, sending 0 instead -> error
    // Expected: parityError=1, byteReady=0
    // ----------------------------------------------------------------
    $display("\n--- Test 2: correct byte, wrong parity bit ---");
    #10;
    send_frame(8'b01100001, 0, 1); // parity should be 1, sending 0
    #40;

    // ----------------------------------------------------------------
    // Test 3: correct byte, correct parity, but stop bit = 0
    // Expected: frameError=1, byteReady=0
    // ----------------------------------------------------------------
    $display("\n--- Test 3: correct byte, correct parity, missing stop bit ---");
    #10;
    send_frame(8'b01100001, 1, 0); // stop bit should be 1, sending 0
    #40;

    // ----------------------------------------------------------------
    // Test 4: three back-to-back correct bytes
    // Watch rxAccumulator and rxDelayFrames in VaporView to verify the
    // accumulator stretches some bit periods to 9 cycles (BAUD_DIVISOR+1)
    // Pattern with ACC_INCREMENT=3, ACC_MODULUS=8:
    //   period 1: acc=3  -> 8 cycles
    //   period 2: acc=6  -> 8 cycles
    //   period 3: acc=9>=8 -> 9 cycles, acc=1
    //   period 4: acc=4  -> 8 cycles
    //   period 5: acc=7  -> 8 cycles
    //   period 6: acc=10>=8 -> 9 cycles, acc=2
    //   period 7: acc=5  -> 8 cycles
    //   period 8: acc=8>=8  -> 9 cycles, acc=0  (back to start)
    // ----------------------------------------------------------------
    $display("\n--- Test 4: three back-to-back correct bytes (watch accumulator) ---");
    #10;
    send_frame(8'b01100001, 1, 1);
    #10; // short idle gap
    send_frame(8'b01100001, 1, 1);
    #10;
    send_frame(8'b01100001, 1, 1);
    #40;

    $display("\n=== done ===");
    #100;
    $finish;
end

endmodule
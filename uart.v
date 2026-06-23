`default_nettype none 

module uart
#(
    parameter DELAY_FRAMES = 234 // 27,000,000 (27Mhz) / 115,200 Baud rate
    // such parameters can be changed by files that use this module! "local param configurable from outside"
)
(
    input clk,
    input uart_rx,
    output uart_tx,
    output reg [5:0] led,
    input btn1
);

localparam HALF_DELAY_WAIT = (DELAY_FRAMES / 2);

reg [3:0] rxState = 0; // track which state of receiver state machine
reg [12:0] rxCounter = 0; // count clock cycles
reg [2:0] rxBitNumber = 0; // track which bit we are reading/have read
reg [7:0] dataIn = 0; // store read-in data bits
reg byteReady = 0; // flag when reading in of data is finished, and dataIn can be used for other things
reg frameError = 0; // flag missing stop bit (warning because never read: read later)

// state machine states
localparam RX_STATE_IDLE = 0;
localparam RX_STATE_START_BIT = 1;
localparam RX_STATE_READ_WAIT = 2;
localparam RX_STATE_READ = 3;
localparam RX_STATE_STOP_BIT = 5;

always @(posedge clk) begin
    case (rxState)
        RX_STATE_IDLE: begin
            if (uart_rx == 0) begin
                rxState <= RX_STATE_START_BIT;
                rxCounter <= 1;
                rxBitNumber <= 0;
                byteReady <= 0; // reset counter, bitnumber, byteready and move to start bit state
                frameError <= 0; // reset possible frameError flag
            end
        end
        RX_STATE_START_BIT: begin
            if (rxCounter == HALF_DELAY_WAIT) begin
                rxState <= RX_STATE_READ_WAIT;
                rxCounter <= 1;
            end else
                rxCounter <= rxCounter + 1; //if we've waited half a frame, start waiting another half frame for reading, else increment clock
        end
        RX_STATE_READ_WAIT: begin
            rxCounter <= rxCounter + 1;
            if ((rxCounter + 1) == DELAY_FRAMES) begin
                rxState <= RX_STATE_READ; // check to equal delay frames because it should start counting at half delay frames (from start bit state)
            end
        end
        RX_STATE_READ: begin
            rxCounter <= 1; // reset counter
            dataIn <= {uart_rx, dataIn[7:1]}; // shift one databit in, concat uart_rx as MSB with top 7 bits in 8 bit dataIn! (shift register)
            rxBitNumber <= rxBitNumber + 1; // track which bit we are reading
            if (rxBitNumber == 3'b111)
                rxState <= RX_STATE_STOP_BIT;  // if bitnumber = 8 move to stop bit stait
            else
                rxState <= RX_STATE_READ_WAIT; // if not, start waiting for next bit (e.g. time the next reading)
        end
        RX_STATE_STOP_BIT: begin 
            rxCounter <= rxCounter + 1;
            if ((rxCounter + 1) == DELAY_FRAMES) begin // read ends in middle of frame, so wait one full frame to land in next middle
                frameError <= (uart_rx != 1); // if stop bit not 1, assert
                byteReady <= (uart_rx == 1); // if stop bit 1 (correct), assert (otherwise byte is corrupt and not ready)
                rxState <= RX_STATE_IDLE; // after full frame: move back to idle
                rxCounter <= 0;
            end
        end
    endcase // special for case!
end

// check if we have some data and light up leds
always @(posedge clk) begin
    if (byteReady) begin
        led <= ~dataIn[5:0]; // negate as common anode
    end
end


// receiving

reg [3:0] txState = 0;
reg [24:0] txCounter = 0;
reg [7:0] dataOut = 0;
reg txPinRegister = 1; // stores current transmission value
reg [2:0] txBitNumber = 0;
reg [3:0] txByteCounter = 0; // track current byte we're sending (there's 12 bytes in the testMemory, so need to track)

assign uart_tx = txPinRegister;

localparam MEMORY_LENGTH = 12;
reg [7:0] testMemory [MEMORY_LENGTH-1:0]; // create 12 separate 8 bit registers!

// set memory
initial begin
    testMemory[0] = "Y";
    testMemory[1] = "o";
    testMemory[2] = "u";
    testMemory[3] = " ";
    testMemory[4] = "a";
    testMemory[5] = "r";
    testMemory[6] = "e";
    testMemory[7] = " ";
    testMemory[8] = "t";
    testMemory[9] = "i";
    testMemory[10] = "n";
    testMemory[11] = "y";
end

localparam TX_STATE_IDLE = 0;
localparam TX_STATE_START_BIT = 1;
localparam TX_STATE_WRITE = 2;
localparam TX_STATE_STOP_BIT = 3;
localparam TX_STATE_DEBOUNCE = 4; // debounce button

always @(posedge clk) begin
    case (txState)
        TX_STATE_IDLE: begin
            if (btn1 == 0) begin
                txState <= TX_STATE_START_BIT;
                txCounter <= 0;
                txByteCounter <= 0;
            end
            else begin
                txPinRegister <= 1; // keep line high if not transmitting
            end
        end
        TX_STATE_START_BIT: begin
            txPinRegister <= 0; // move line low to signal start of transmission (start bit)
            if ((txCounter + 1) == DELAY_FRAMES) begin // switch to transmit after a delay_frames period
                txState <= TX_STATE_WRITE;
                dataOut <= testMemory[txByteCounter]; // set dataOUt to appropriate byte of memory
                txBitNumber <= 0;
                txCounter <= 0;
            end
            else begin
                txCounter <= txCounter + 1;
            end
        end
        TX_STATE_WRITE: begin
            txPinRegister <= dataOut[txBitNumber]; // output appropriate bit of appropriate byte
            if ((txCounter + 1) == DELAY_FRAMES) begin // another delay frames after start bit state, to wait after the start bit signal
                if (txBitNumber == 3'b111) begin
                    txState <= TX_STATE_STOP_BIT;
                end else begin
                    txState <= TX_STATE_WRITE;
                    txBitNumber <= txBitNumber + 1; // write next bit, but only move to this state after delay!
                end
                txCounter <=0;
            end
            else begin
                txCounter <= txCounter + 1;
            end
        end
        TX_STATE_STOP_BIT: begin
            txPinRegister <= 1; // already waited in previous state so can instantly transmit stop bit
            if ((txCounter + 1) == DELAY_FRAMES) begin
                if (txByteCounter == MEMORY_LENGTH - 1) begin
                    txState <= TX_STATE_DEBOUNCE;
                end else begin
                    txByteCounter <= txByteCounter + 1; // next byte
                    txState <= TX_STATE_START_BIT; // new byte means start from start bit again
                end
                txCounter <= 0;
            end else begin
                txCounter <= txCounter + 1;
            end
        end
        TX_STATE_DEBOUNCE: begin // ensure one transmission for each button press, so check again only AFTER 10 ms ish (23 1s)
            if (txCounter == 23'b11111111111111111111111) begin
                if (btn1 == 1) begin
                    txState <= TX_STATE_IDLE;
                end
            end else begin
                txCounter <= txCounter + 1;
            end
        end
    endcase
end

endmodule

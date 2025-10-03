
module tb_cordic_sigmoid;

    // Parameters
    parameter WIDTH = 32;
    parameter FRAC  = 14;
    parameter ITER  = 16;
    parameter LOG_ITER = 4;

    // Testbench signals
    reg clk;
    reg rst_n;
    reg start;
    reg signed [WIDTH-1:0] x_in;
    reg func_select;  // 0 = Sigmoid
    wire busy;
    wire done;
    wire signed [WIDTH:0] result;

    integer i;
    real scale_factor;
    real expected, actual, error;

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation
    cordic_final #(
        .WIDTH(WIDTH),
        .FRAC(FRAC),
        .ITER(ITER),
        .LOG_ITER(LOG_ITER)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .x_in(x_in),
        .func_select(func_select),
        .busy(busy),
        .done(done),
        .result(result)
    );

    // Test vectors
    real test_inputs [0:9];
    integer input_q14 [0:9];

    initial begin
        test_inputs[0] = 0.0;     input_q14[0] = 0;
        test_inputs[1] = 0.25;    input_q14[1] = 4096;
        test_inputs[2] = 0.375;   input_q14[2] = 6144;
        test_inputs[3] = 0.5;     input_q14[3] = 8192;
        test_inputs[4] = 0.75;    input_q14[4] = 12288;
        test_inputs[5] = 1.0;     input_q14[5] = 16384;
        test_inputs[6] = -0.25;   input_q14[6] = -4096;
        test_inputs[7] = -0.5;    input_q14[7] = -8192;
        test_inputs[8] = -0.75;   input_q14[8] = -12288;
        test_inputs[9] = -1.0;    input_q14[9] = -16384;

    end

    // Main test process
    initial begin
        $dumpfile("tb_cordic_sigmoid.vcd");
        $dumpvars(0, tb_cordic_sigmoid);

        scale_factor = 2.0 ** FRAC;

        // Reset
        rst_n = 0;
        start = 0;
        func_select = 0; // SIGMOID
        #20 rst_n = 1;

        $display("\n=== Testing SIGMOID Function ===");
        for (i = 0; i < 10; i = i + 1) begin
            // Apply input
            x_in = input_q14[i];
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for done
            wait(done);

            // Compute expected and compare
            expected = 1.0 / (1.0 + $exp(-test_inputs[i]));
            actual   = $itor(result) / scale_factor;
            error    = (actual - expected);
            if (error < 0) error = -error;

            $display("x=%0.2f, Expected=%0.6f, Got=%0.6f, Error=%0.3e %s",
                     test_inputs[i], expected, actual, error,
                     (error < 0.01) ? "PASS" : "FAIL");

            repeat(2) @(posedge clk);
        end

        $display("\nSIGMOID test completed!");
        $finish;
    end

endmodule

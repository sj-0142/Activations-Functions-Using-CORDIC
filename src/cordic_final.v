//==========================================================================================
// CORE LOGIC:
// sinh(x) -> obtained through a fully pipelined CORDIC algorithm
// tanh(x) = sinh(x)*(1-0.375x^2) [fully pipelined] 
// sigmoid(x) = 0.5*tanh(x/2)+0.5 [fully pipelined] 
//==========================================================================================

(* keep_hierarchy = "yes", use_dsp = "yes" *)
module cordic_final #(
    parameter WIDTH = 32,          
    parameter FRAC = 14,           
    parameter ITER = 16,           
    parameter LOG_ITER = 4,         
    parameter POST_STAGES = 5       
)
(
    input wire                    clk,
    input wire                    rst_n,        
    input wire                    start,        
    input wire signed [WIDTH-1:0] x_in,         
    input wire                    func_select,  
    output reg                    busy,         
    output reg                    done,         
    output reg signed [WIDTH:0] result       
);

    localparam signed [WIDTH-1:0] ONE_Q = (1 << FRAC);         
    localparam signed [WIDTH-1:0] ONE_Q_1 = ONE_Q >> 1;         
    localparam signed [WIDTH-1:0] K_INV_SCALED = 16'sd19784;    

    (* ram_style = "block" *) reg [5:0] shift_lut [0:ITER-1];
    (* ram_style = "block" *) reg signed [WIDTH-1:0] atanh_lut [0:ITER-1];

    reg signed [WIDTH-1:0] x_pipe [0:ITER];
    reg signed [WIDTH-1:0] y_pipe [0:ITER];
    reg signed [WIDTH-1:0] z_pipe [0:ITER];
    reg signed [WIDTH-1:0] k; 
    reg valid_pipe [0:ITER];

    reg signed [WIDTH-1:0] x_input_pipe [0:POST_STAGES-1];
    reg signed [WIDTH-1:0] y_result_pipe [0:POST_STAGES-1];
    reg func_select_pipe [0:POST_STAGES-1];
    reg valid_post_pipe [0:POST_STAGES-1];

    reg signed [2*WIDTH-1:0] x_squared_pipe [0:POST_STAGES-1];
    reg signed [2*WIDTH-1:0] coeff_term_pipe [0:POST_STAGES-1];
    reg signed [WIDTH-1:0] one_minus_approx_pipe [0:POST_STAGES-1];
    reg signed [2*WIDTH-1:0] final_product_pipe [0:POST_STAGES-1];
    reg signed [WIDTH-1:0] extracted_result_pipe [0:POST_STAGES-1];

    reg [1:0] state, next_state;
    reg [LOG_ITER:0] stage_counter;

    localparam [1:0] IDLE = 2'b00;
    localparam [1:0] PROCESS = 2'b01;
    localparam [1:0] OUTPUT = 2'b10;

  
    reg signed [WIDTH-1:0] x_input_stored;  
    
    integer i;

    initial begin        
        shift_lut[0]  = 6'd1;   shift_lut[1]  = 6'd2;   shift_lut[2]  = 6'd3;   shift_lut[3]  = 6'd4;
        shift_lut[4]  = 6'd4;   shift_lut[5]  = 6'd5;   shift_lut[6]  = 6'd6;   shift_lut[7]  = 6'd7;
        shift_lut[8]  = 6'd8;   shift_lut[9]  = 6'd9;   shift_lut[10] = 6'd10;  shift_lut[11] = 6'd11;
        shift_lut[12] = 6'd12;  shift_lut[13] = 6'd13;  shift_lut[14] = 6'd13;  shift_lut[15] = 6'd14;

        atanh_lut[0]  = 16'sd9000;   atanh_lut[1]  = 16'sd4185;   atanh_lut[2]  = 16'sd2059;   atanh_lut[3]  = 16'sd1025;
        atanh_lut[4]  = 16'sd1025;   atanh_lut[5]  = 16'sd512;    atanh_lut[6]  = 16'sd256;    atanh_lut[7]  = 16'sd128;
        atanh_lut[8]  = 16'sd64;     atanh_lut[9]  = 16'sd32;     atanh_lut[10] = 16'sd16;     atanh_lut[11] = 16'sd8;
        atanh_lut[12] = 16'sd4;      atanh_lut[13] = 16'sd2;      atanh_lut[14] = 16'sd2;      atanh_lut[15] = 16'sd1;
        
        for (i = 0; i < ITER; i = i + 1) begin
            x_pipe[i] = 0;
            y_pipe[i] = 0;
            z_pipe[i] = 0;
        end

        for (i = 0; i < POST_STAGES; i = i + 1) begin
            x_input_pipe[i] = 0;
            y_result_pipe[i] = 0;
            func_select_pipe[i] = 0;
            valid_post_pipe[i] = 0;
            x_squared_pipe[i] = 0;
            coeff_term_pipe[i] = 0;
            one_minus_approx_pipe[i] = 0;
            final_product_pipe[i] = 0;
            extracted_result_pipe[i] = 0;
        end          
    end
    
    
    //Fully pipelined CORDIC computation using generate blocks
            // z_positive -> if we need to rotate left or right
            // x_pipe -> cosh output
            // y_pipe -> sinh output
            // z_pipe -> angle left to be rotated
            // x_shifted -> x_k>>i_k [current_shift -> i_k]
            
    genvar stage;
    generate 
        for (stage = 0; stage < ITER; stage = stage + 1) 
        begin : cordic_pipeline
            wire z_positive;
            wire [5:0] current_shift;
            wire signed [WIDTH-1:0] x_shifted;
            wire signed [WIDTH-1:0] y_shifted;
            wire signed [WIDTH-1:0] atanh_val;
            
            assign z_positive = ~z_pipe[stage][WIDTH-1];
            assign current_shift = shift_lut[stage];
            assign x_shifted = x_pipe[stage] >>> current_shift;
            assign y_shifted = y_pipe[stage] >>> current_shift;
            assign atanh_val = atanh_lut[stage];
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    x_pipe[stage+1] <= {WIDTH{1'b0}};
                    y_pipe[stage+1] <= {WIDTH{1'b0}};
                    z_pipe[stage+1] <= {WIDTH{1'b0}};
                    valid_pipe[stage+1] <= 1'b0;
                end else begin

                    (* use_dsp = "yes" *) x_pipe[stage+1] <= z_positive ? (x_pipe[stage] + y_shifted) : (x_pipe[stage] - y_shifted);
                    (* use_dsp = "yes" *) y_pipe[stage+1] <= z_positive ? (y_pipe[stage] + x_shifted) : (y_pipe[stage] - x_shifted);
                    (* use_dsp = "yes" *) z_pipe[stage+1] <= z_positive ? (z_pipe[stage] - atanh_val) : (z_pipe[stage] + atanh_val);
                    valid_pipe[stage+1] <= valid_pipe[stage];
                end
            end
        end
    endgenerate

    // Post-CORDIC pipeline for tanh/sigmoid computation
    // Stage 1: Input to post-pipeline and x_squared calculation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_input_pipe[0] <= {WIDTH{1'b0}};
            y_result_pipe[0] <= {WIDTH{1'b0}};
            func_select_pipe[0] <= 1'b0;
            valid_post_pipe[0] <= 1'b0;
            x_squared_pipe[0] <= {(2*WIDTH){1'b0}};
        end else begin
            x_input_pipe[0] <= x_input_stored;
            y_result_pipe[0] <= y_pipe[ITER];
            func_select_pipe[0] <= func_select;
            valid_post_pipe[0] <= valid_pipe[ITER];
            
            (* use_dsp = "yes" *) x_squared_pipe[0] <= $signed(x_input_stored) * $signed(x_input_stored);
        end
    end

    // Stage 2: Coefficient term calculation -> [0.375x^2]
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_input_pipe[1] <= {WIDTH{1'b0}};
            y_result_pipe[1] <= {WIDTH{1'b0}};
            func_select_pipe[1] <= 1'b0;
            valid_post_pipe[1] <= 1'b0;
            coeff_term_pipe[1] <= {(2*WIDTH){1'b0}};
        end else begin
            x_input_pipe[1] <= x_input_pipe[0];
            y_result_pipe[1] <= y_result_pipe[0];
            func_select_pipe[1] <= func_select_pipe[0];
            valid_post_pipe[1] <= valid_post_pipe[0];
            
            (* use_dsp = "yes" *) coeff_term_pipe[1] <= (x_squared_pipe[0] * 23900) >>> 30;
        end
    end

    // Stage 3: One minus calculation [1-0.375x^2]
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_input_pipe[2] <= {WIDTH{1'b0}};
            y_result_pipe[2] <= {WIDTH{1'b0}};
            func_select_pipe[2] <= 1'b0;
            valid_post_pipe[2] <= 1'b0;
            one_minus_approx_pipe[2] <= {WIDTH{1'b0}};
        end else begin
            x_input_pipe[2] <= x_input_pipe[1];
            y_result_pipe[2] <= y_result_pipe[1];
            func_select_pipe[2] <= func_select_pipe[1];
            valid_post_pipe[2] <= valid_post_pipe[1];
            
            (* use_dsp = "yes" *) one_minus_approx_pipe[2] <= ONE_Q - coeff_term_pipe[1][WIDTH-1:0];
        end
    end

    // Stage 4: Final product calculation [tanh = sinh * (1-0.375x^2)]
    // Final_product_pipe[3] -> tanh
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_input_pipe[3] <= {WIDTH{1'b0}};
            y_result_pipe[3] <= {WIDTH{1'b0}};
            func_select_pipe[3] <= 1'b0;
            valid_post_pipe[3] <= 1'b0;
            final_product_pipe[3] <= {(2*WIDTH){1'b0}};
        end else begin
            x_input_pipe[3] <= x_input_pipe[2];
            y_result_pipe[3] <= y_result_pipe[2];
            func_select_pipe[3] <= func_select_pipe[2];
            valid_post_pipe[3] <= valid_post_pipe[2];
            
            (* use_dsp = "yes" *) final_product_pipe[3] <= $signed(y_result_pipe[2]) * $signed(one_minus_approx_pipe[2]);
        end
    end

    // Stage 5: Reverse Q14 shift
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_input_pipe[4] <= {WIDTH{1'b0}};
            y_result_pipe[4] <= {WIDTH{1'b0}};
            func_select_pipe[4] <= 1'b0;
            valid_post_pipe[4] <= 1'b0;
            extracted_result_pipe[4] <= {WIDTH{1'b0}};
        end else begin
            x_input_pipe[4] <= x_input_pipe[3];
            y_result_pipe[4] <= y_result_pipe[3];
            func_select_pipe[4] <= func_select_pipe[3];
            valid_post_pipe[4] <= valid_post_pipe[3];
            
            (* use_dsp = "yes" *) extracted_result_pipe[4] <= final_product_pipe[3] >>> FRAC;
            
        end
    end
    
    // State machine combinational logic
    always @(*) begin
        case (state)
            IDLE: next_state = start ? PROCESS : IDLE;
            PROCESS: next_state = (stage_counter >= ITER + POST_STAGES + 3) ? OUTPUT : PROCESS; 
            OUTPUT: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end  
    

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            result <= {WIDTH{1'b0}};
            stage_counter <= {(LOG_ITER+1){1'b0}};


            x_pipe[0] <= {WIDTH{1'b0}};
            y_pipe[0] <= {WIDTH{1'b0}};
            z_pipe[0] <= {WIDTH{1'b0}};
            valid_pipe[0] <= 1'b0;

            x_input_stored <= {WIDTH{1'b0}};

        end else begin
            state <= next_state;
            done <= 1'b0;  

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    stage_counter <= {(LOG_ITER+1){1'b0}};
                    if (start) begin
                        x_pipe[0] <= K_INV_SCALED;  
                        y_pipe[0] <= {WIDTH{1'b0}}; 
                        
                        if (func_select) begin // Tanh logic -> [tanh(x) = 1*tanh(x) + 0]
                            z_pipe[0] = x_in; 
                            x_input_stored <= x_in;
                            k = 0;
                        end else begin // Sigmoid logic -> [sigmoid(x) = 0.5*tan(x/2) + 0.5]
                            z_pipe[0] = $signed(x_in) >>> 1; 
                            x_input_stored <= $signed(x_in) >>> 1;
                            k = ONE_Q_1; //0.5 to be added to 0.5*tan(x/2)
                        end

                        valid_pipe[0] <= 1'b1;
                        busy <= 1'b1;
                        stage_counter <= {(LOG_ITER+1){1'b0}};
                    end
                end

                PROCESS: begin
                    stage_counter <= stage_counter + 1'b1;
                end

                OUTPUT: begin
                    busy <= 1'b0;

                    if (valid_post_pipe[POST_STAGES-1]) begin
                        if (func_select_pipe[POST_STAGES-1]) begin
                            // Tanh(x)
                            result <= extracted_result_pipe[POST_STAGES-1];
                        end else begin
                            // Sigmoid(x) = 0.5 * tanh(x/2) + 0.5
                            result <= (extracted_result_pipe[POST_STAGES-1] + ONE_Q) >>> 1;
                        end

                        done <= 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule                      
                            



`timescale 1ns/1ps

module counter 
#(
    parameter WIDTH_P = 32,
    parameter MAX_VAL_P = 128
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [WIDTH_P-1:0] rstn_data_i,
    input logic [0:0] up_i,
    input logic [0:0] down_i,
    input logic [0:0] en_i,
    output logic [WIDTH_P-1:0] count_o
);

    logic [WIDTH_P-1:0] count_l;
    logic [WIDTH_P-1:0] count_w;
    logic [WIDTH_P-1:0] toggle_w;

    // toggle flip counter
    // for sequential counting bit 0 toggles every tick
    assign toggle_w[0] = up_i ^ down_i;

    genvar i;
    generate
        for (i = 0; i < WIDTH_P; i++) begin : gen_carry
            // if carry of wire is high, then toggle
            assign count_w[i] = toggle_w[i] ? ~count_l[i] : count_l[i];
        end
    endgenerate

    genvar j;
    generate
        for (j = 1; j < WIDTH_P; j++) begin : gen_count
            // toggle only if all lower bits are high
            assign toggle_w[j] = up_i ? (toggle_w[j-1] & count_l[j-1]) : down_i ? (toggle_w[j-1] & ~count_l[j-1]) : 1'b0;
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            count_l <= rstn_data_i;
        end else if (en_i) begin
            if (up_i && !down_i) begin
                if (count_l == MAX_VAL_P[WIDTH_P-1:0]) begin
                    count_l <= '0;
                end else begin
                    count_l <= count_w;
                end
            end else if (down_i && !up_i) begin
                if (count_l == '0) begin
                    count_l <= MAX_VAL_P[WIDTH_P-1:0];
                end else begin
                    count_l <= count_w;
                end
            end
        end
    end

    assign count_o = count_l;

endmodule
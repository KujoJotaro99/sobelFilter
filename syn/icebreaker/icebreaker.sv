`timescale 1ns/1ps

module icebreaker
#(
    parameter WIDTH_P = 8,
    parameter LINE_W_P = 640,
    parameter FIFO_DEPTH_P = 256,
    parameter UART_PRESCALE_P = 16'd17
) (
    input logic [0:0] mclk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] uart_rxd_i,
    output logic [0:0] uart_txd_o
);

    logic [0:0] core_clk;

    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .PLLOUT_SELECT("GENCLK"),
        .DIVR(4'b0000),
        .DIVF(7'b0001001),
        .DIVQ(3'b010),
        .FILTER_RANGE(3'b001)
    ) core_pll (
        .PACKAGEPIN(mclk_i),
        .PLLOUTCORE(core_clk),
        .PLLOUTGLOBAL(),
        .EXTFEEDBACK(1'b0),
        .DYNAMICDELAY(8'b00000000),
        .LOCK(),
        .BYPASS(1'b0),
        .RESETB(rstn_i),
        .LATCHINPUTVALUE(1'b0),
        .SDO(),
        .SDI(1'b0),
        .SCLK(1'b0)
    );

    logic [0:0] rstn_sync;

    sync2 #(
        .WIDTH_P(1)
    ) rstn_sync_inst (
        .clk_sync_i(core_clk),
        .rstn_i(1'b1),
        .sync_i(rstn_i),
        .sync_o(rstn_sync)
    );

    logic [7:0] uart_rx_data;
    logic [0:0] uart_rx_valid;
    logic [0:0] uart_rx_ready;

    logic [7:0] uart_tx_data;
    logic [0:0] uart_tx_valid;
    logic [0:0] uart_tx_ready;

    uart #(
        .DATA_WIDTH(8)
    ) uart_inst (
        .clk(core_clk),
        .rst(~rstn_sync),
        .s_axis_tdata(uart_tx_data),
        .s_axis_tvalid(uart_tx_valid),
        .s_axis_tready(uart_tx_ready),
        .m_axis_tdata(uart_rx_data),
        .m_axis_tvalid(uart_rx_valid),
        .m_axis_tready(uart_rx_ready),
        .rxd(uart_rxd_i),
        .txd(uart_txd_o),
        .tx_busy(),
        .rx_busy(),
        .rx_overrun_error(),
        .rx_frame_error(),
        .prescale(UART_PRESCALE_P)
    );

    logic [7:0] rx_fifo_data;
    logic [0:0] rx_fifo_valid;
    logic [0:0] rx_fifo_ready;

    fifo_sync #(
        .WIDTH_P(8),
        .DEPTH_P(FIFO_DEPTH_P)
    ) rx_fifo (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .data_i(uart_rx_data),
        .valid_i(uart_rx_valid),
        .ready_i(rx_fifo_ready),
        .valid_o(rx_fifo_valid),
        .ready_o(uart_rx_ready),
        .data_o(rx_fifo_data)
    );

    logic [23:0] rgb_data;
    logic [0:0] rgb_valid;
    logic [0:0] rgb_ready;

    axis_adapter #(
        .S_DATA_WIDTH(8),
        .M_DATA_WIDTH(24),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) rgb_pack (
        .clk(core_clk),
        .rst(~rstn_sync),
        .s_axis_tdata(rx_fifo_data),
        .s_axis_tkeep(1'b1),
        .s_axis_tvalid(rx_fifo_valid),
        .s_axis_tready(rx_fifo_ready),
        .s_axis_tlast(1'b0),
        .s_axis_tid('0),
        .s_axis_tdest('0),
        .s_axis_tuser('0),
        .m_axis_tdata(rgb_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(rgb_valid),
        .m_axis_tready(rgb_ready),
        .m_axis_tlast(),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

    logic [0:0] mag_valid;
    logic [0:0] mag_ready;
    logic [WIDTH_P-1:0] mag_data;

    sobel #(
        .WIDTH_P(WIDTH_P),
        .LINE_W_P(LINE_W_P)
    ) sobel_inst (
        .clk_i(core_clk),
        .rstn_i(rstn_sync),
        .red_i(rgb_data[7:0]),
        .green_i(rgb_data[15:8]),
        .blue_i(rgb_data[23:16]),
        .valid_i(rgb_valid),
        .ready_o(rgb_ready),
        .mag_o(mag_data),
        .valid_o(mag_valid),
        .ready_i(mag_ready)
    );

    axis_adapter #(
        .S_DATA_WIDTH(24),
        .M_DATA_WIDTH(8),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) rgb_unpack (
        .clk(core_clk),
        .rst(~rstn_sync),
        .s_axis_tdata({3{mag_data[WIDTH_P-1:0]}}),
        .s_axis_tkeep(3'b111),
        .s_axis_tvalid(mag_valid),
        .s_axis_tready(mag_ready),
        .s_axis_tlast(1'b0),
        .s_axis_tid('0),
        .s_axis_tdest('0),
        .s_axis_tuser('0),
        .m_axis_tdata(uart_tx_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(uart_tx_valid),
        .m_axis_tready(uart_tx_ready),
        .m_axis_tlast(),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser()
    );

endmodule

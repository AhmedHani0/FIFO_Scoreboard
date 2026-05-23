// -------------------------------------------------
// Copyright(c) LUBIS EDA GmbH, All rights reserved
// Contact: contact@lubis-eda.com
// -------------------------------------------------

`default_nettype none

module fv_scoreboard #(
    parameter  WIDTH     = 128,
    parameter  DEPTH     = 128,
    localparam WIDTH_LG2 = $clog2(WIDTH),
    localparam DEPTH_LG2 = $clog2(DEPTH)
)(
    input logic                clk,
    input logic                rst,
    input logic                full,
    input logic                empty,
    input logic [WIDTH-1:0]    data_in,
    input logic [WIDTH-1:0]    data_out,
    input logic                push,
    input logic                pop
);

    /////////////////////////////////////
    // Scoreboard logic and properties //
    /////////////////////////////////////

    logic fv_push;
    logic fv_pop;

    assign fv_push = push && !full;
    assign fv_pop  = pop  && !empty;

    property p_data_integrity_adhoc;
        logic [WIDTH-1:0] fv_data;

        @(posedge clk) disable iff (rst)
            (fv_push, fv_data = data_in)
            |-> ##[1:$] (fv_pop && (data_out == fv_data));
    endproperty

    a_data_integrity_adhoc: assert property (p_data_integrity_adhoc);

endmodule

bind lubis_fifo fv_scoreboard #(
    .WIDTH   (WIDTH    ),
    .DEPTH   (DEPTH    )
) fv_scoreboard_i (
    .clk     (clk      ),
    .rst     (rst      ),
    .full    (full     ),
    .empty   (empty    ),
    .data_in (push_data),
    .data_out(pop_data ),
    .push    (push     ),
    .pop     (pop      )
);

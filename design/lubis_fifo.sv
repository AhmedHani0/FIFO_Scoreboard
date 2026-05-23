// -------------------------------------------------
//  Copyright(c) LUBIS EDA GmbH, All rights reserved
//  Contact: contact@lubis-eda.com
// -------------------------------------------------

`default_nettype none

module lubis_fifo
#(
  parameter  WIDTH     = 4 ,
  parameter  DEPTH     = 16,
  localparam DEPTH_LG2 = $clog2(DEPTH)
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             push,
    input  logic [WIDTH-1:0] push_data,
    input  logic             pop,
    output logic [WIDTH-1:0] pop_data,
    output logic             empty,
    output logic             full
);

    default clocking default_clk @(posedge clk); endclocking

    logic [DEPTH_LG2-1:0] write_pointer;
    logic [DEPTH_LG2-1:0] read_pointer;
    logic roll;

    // Head & tail pointer
    logic read_pointer_wrap;
    logic write_pointer_wrap;

    assign read_pointer_wrap  = push && (!full)           && (write_pointer == (DEPTH - 1));
    assign write_pointer_wrap = pop  && !(empty && !push) && (read_pointer  == (DEPTH - 1));

    always_ff @ (posedge clk) begin
        if (rst) begin
            write_pointer <= {DEPTH_LG2{1'b0}};
            read_pointer  <= {DEPTH_LG2{1'b0}};
            roll          <= 1'b0;
        end
        else begin
            if (push && !full) begin
                write_pointer <= DEPTH_LG2'((write_pointer + 1'b1) % DEPTH);
            end
            if (pop && !(empty && !push)) begin
                read_pointer <= DEPTH_LG2'((read_pointer + 1'b1) % DEPTH);
            end
            if (read_pointer_wrap ^ write_pointer_wrap) begin
                roll <= !roll;
            end
        end
    end

    logic [DEPTH-1:0][WIDTH-1:0] mem ;

    always_ff @ (posedge clk or posedge rst) begin
        if(rst)begin
            mem <= '0;
        end else begin
            if (push && !full) begin
                mem[write_pointer] <= push_data;
            end
        end
    end

    // Outputs
    assign pop_data = (push && empty) ? push_data : mem[read_pointer];

    assign empty = !roll ? (write_pointer == read_pointer) : 1'b0;
    assign full  =  roll ? (write_pointer == read_pointer) : 1'b0;

endmodule

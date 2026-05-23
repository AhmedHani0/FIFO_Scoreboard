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
    // Free formal undriven signal.
    // The formal tool may choose it to be 0 or 1 in any cycle.
    // When fv_arbit_window is 1 during a valid push, the scoreboard
    // selects that pushed packet as the packet to track.
    logic fv_arbit_window;
    // 0 -> no packet has been selected yet
    // 1 -> a packet has already been selected and is being tracked
    logic fv_sampled_in;
    // 0 -> the selected packet has not left the FIFO yet
    // 1 -> the selected packet has already left the FIFO
    logic fv_sampled_out;
    // The data value of the selected packet.
    logic [WIDTH-1:0] fv_sampled_data;
    //incremented on push, decremented on pop.
    localparam FV_COUNTER_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);
    logic [FV_COUNTER_WIDTH-1:0] fv_tracking_counter;
    // One-cycle event condition:
    // This is true exactly in the cycle where the scoreboard selects
    // the packet to track.
    logic fv_sample_in_condition;
    // One-cycle event condition:
    // This is true exactly in the cycle where the selected packet
    // is expected to leave the FIFO.
    logic fv_sample_out_condition;
    // Counter update control signals.
    logic fv_counter_increment;
    logic fv_counter_decrement;

    assign fv_push = push && !full;
    assign fv_pop  = pop && (!empty || push);

    // A bypass transfer happens when the FIFO is empty,
    // and a push and pop happen in the same cycle.
    // The pushed packet directly appears at the output.
    assign fv_bypass_transfer =
        empty && fv_push && fv_pop;

    // ------------------------------------------------------------
    // Sampling-in condition
    // ------------------------------------------------------------
    //
    // We sample a packet when:
    // 1. a valid push happens,
    // 2. the formal tool selects this cycle using fv_arbit_window,
    // 3. we have not already selected another packet.
    // ------------------------------------------------------------

    assign fv_sample_in_condition =
        fv_push && fv_arbit_window && !fv_sampled_in;

    // ------------------------------------------------------------
    // Sampling-out condition
    // ------------------------------------------------------------
    //
    // The selected packet is leaving when:
    // 1. a valid pop happens,
    // 2. we already sampled a packet in,
    // 3. it has not already been sampled out,
    // 4. the tracking counter is 1.
    //
    // Counter == 1 means:
    // "The next valid pop is the tracked packet."
    // ------------------------------------------------------------
    assign fv_sample_out_condition =
        fv_pop &&
        fv_sampled_in &&
        !fv_sampled_out &&
        (fv_tracking_counter == FV_COUNTER_WIDTH'(1));

    // Special case:
    // the selected packet is sampled in and sampled out
    // in the same cycle through FIFO bypass.
    assign fv_sample_in_out_condition =
        fv_sample_in_condition && fv_bypass_transfer;

    // ------------------------------------------------------------
    // Tracking counter control
    // ------------------------------------------------------------
    //
    // Increment:
    // Count every valid pushed packet before and including the
    // selected packet.
    //
    // Decrement:
    // Count every valid popped packet until the selected packet has
    // left the FIFO.
    //
    // The decrement is protected with fv_tracking_counter != 0 to
    // avoid underflow.
    // ------------------------------------------------------------
    assign fv_counter_increment =
        fv_push && !fv_sampled_in;

    assign fv_counter_decrement =
        fv_pop && !fv_sampled_out;
    
    //Coverage properties to ensure liveness of the pushing and popping
    cover_sampled_in: cover property (
    @(posedge clk) disable iff (rst)
        fv_sampled_in
    );

    cover_sampled_out: cover property (
    @(posedge clk) disable iff (rst)
        fv_sampled_out
    );

// //This property checks eventual appearance, not exact FIFO order. !
// //It also has another weakness: it only compares values, not packet identity.
//     property p_data_integrity_adhoc;
//         logic [WIDTH-1:0] fv_data;

//         @(posedge clk) disable iff (rst)
//             (fv_push, fv_data = data_in)
//             //This is an unbounded eventual condition. In many formal flows, this is a liveness-style check
//             |-> ##[1:$] (fv_pop && (data_out == fv_data));
//     endproperty

//     a_data_integrity_adhoc: assert property (p_data_integrity_adhoc);

    // ------------------------------------------------------------
    // Sequential scoreboard state update
    // ------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            fv_sampled_in        <= 1'b0;
            fv_sampled_out       <= 1'b0;
            fv_sampled_data      <= '0;
            fv_tracking_counter  <= '0;
        end
        else begin

            if (fv_sample_in_condition) begin
                fv_sampled_in   <= 1'b1;
                fv_sampled_data <= data_in;
            end

            if (fv_sample_in_out_condition || fv_sample_out_condition) begin
                fv_sampled_out <= 1'b1;
            end

            unique case ({fv_counter_increment, fv_counter_decrement})
                2'b10: begin
                    fv_tracking_counter <= fv_tracking_counter + FV_COUNTER_WIDTH'(1);
                end

                2'b01: begin
                    //Normal Caese: decrement the counter if it's not zero.
                    if (fv_tracking_counter != '0) begin
                        fv_tracking_counter <= fv_tracking_counter - FV_COUNTER_WIDTH'(1);
                    end
                    //Bypass case: the tracked packet leaves and another packet enters in the same cycle
                    //so the counter value does not change.
                    else begin
                        fv_tracking_counter <= fv_tracking_counter;
                    end
                end

                2'b11: begin
                    // One packet enters and one packet leaves.
                    // position of the tracked packet does not change.
                    fv_tracking_counter <= fv_tracking_counter;
                end

                default: begin
                    fv_tracking_counter <= fv_tracking_counter;
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Properties
    // ------------------------------------------------------------
    // Data ordering and integrity:
    // If a packet is sampled in, then the same data must eventually
    // be sampled out. This checks both ordering and integrity of Data
    property p_data_ordering_and_integrity_normal;
        @(posedge clk) disable iff (rst)
            fv_sample_out_condition |-> (data_out == fv_sampled_data);
    endproperty

    // Data ordering and integrity in bypass case:
    // If a packet is sampled in and out in the same cycle through bypass,
    // then the output data must be the same as the input data.
    property p_data_ordering_and_integrity_bypass;
        @(posedge clk) disable iff (rst)
        // we use data_in here, not data_out, because in bypass, 
        //the output directly reflects the input. lookt in RTL to see that pop_data is assigned from push_data in the bypass case.
            fv_sample_in_out_condition |-> (data_out == data_in);
    endproperty

    //LIVENESS property:
    //If a packet is pushed in, it will eventually come out.
    property p_data_in_equal_data_out;
        @(posedge clk) disable iff (rst)
            fv_sample_in_condition |->
                strong(##[0:$] (fv_sample_out_condition || fv_sample_in_out_condition));
    endproperty

    
    a_data_ordering_and_integrity_normal:
        assert property (p_data_ordering_and_integrity_normal);
    a_data_ordering_and_integrity_bypass:
        assert property (p_data_ordering_and_integrity_bypass);
    a_data_in_equal_data_out:
        assert property (p_data_in_equal_data_out);

    // ------------------------------------------------------------
    // Assumption 1:
    // Data not in then never at output
    // This is an invariant that guides the formal analysis.
    // ------------------------------------------------------------
    property p_data_not_in_then_never_at_output;
        @(posedge clk) disable iff (rst)
            !fv_sampled_in |-> (!fv_sampled_out && !fv_sample_out_condition);
    endproperty
    m_data_not_in_then_never_at_output:
        assume property (p_data_not_in_then_never_at_output);

    // ------------------------------------------------------------
    // Assumption 2:
    // Tracking counter not zero if data in
    // "There is still at least one valid pop needed until the
    // tracked packet leaves the FIFO."
    // Acts also an invariant
    // ------------------------------------------------------------
    property p_tracking_counter_not_zero_if_data_in;
        @(posedge clk) disable iff (rst)
            (fv_sampled_in && !fv_sampled_out) |-> (fv_tracking_counter != '0);
    endproperty
    m_tracking_counter_not_zero_if_data_in:
        assume property (p_tracking_counter_not_zero_if_data_in);

    // ------------------------------------------------
    // Assumption 3: Fairness Constraint
    // If the scoreboard is tracking a packet that has not left yet,
    // the environment will eventually request a pop.
    property p_environment_eventually_pops_when_tracking;
    @(posedge clk) disable iff (rst)
        (fv_sampled_in && !fv_sampled_out) |->
            strong(##[0:$] fv_pop);
    endproperty

    m_environment_eventually_pops_when_tracking:
        assume property (p_environment_eventually_pops_when_tracking);

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

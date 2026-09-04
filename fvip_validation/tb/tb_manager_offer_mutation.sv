`timescale 1ns/1ps

// Validation-only witnesses for the deterministic Manager AW/W contract.
// Legal cases must reach c_terminal.  Each invalid case differs in exactly
// one offer-level relation and must make c_terminal unreachable, even though
// the DUT-owned READY input remains LOW on the rejected offer.
module tb_manager_offer_mutation #(
  parameter int MUTATION = 0
) (
  input logic clk,
  input logic rstn
);
  localparam int ADDR_W = 8;
  localparam int DATA_W = 16;
  localparam int ID_W = 2;
  localparam int MAX_BURST_LEN = 4;
  localparam int W_BEAT_W = $clog2(MAX_BURST_LEN + 1);

  logic [3:0] phase;
  logic [W_BEAT_W-1:0] current_w_beat;
  logic rstn_at_posedge;
  logic rstn_released = 1'b0;
  (* anyconst *) logic inject_bad;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(ADDR_W), .AXI_DATA_WIDTH(DATA_W),
    .AXI_ID_WIDTH(ID_W), .AXI_USER_WIDTH(1)
  ) axi ();

  always_ff @(posedge clk) rstn_at_posedge <= rstn;
  always_ff @(posedge clk) rstn_released <= rstn_released || rstn;
  // Questa 2023.2 elaborates an undriven anyconst as a time-varying formal
  // input unless the temporal constancy is stated explicitly.  The history
  // mutations below must use the same choice when the bad W beat is captured
  // and when the late AW exposes it.
  s_inject_bad_constant: assume property (
    @(posedge clk) disable iff ($isunknown(rstn)) $stable(inject_bad));
  assume property (@(negedge clk) rstn == rstn_at_posedge);
  assume property (@(posedge clk) $past(rstn) |-> rstn);
  assume property (@(posedge clk) !rstn |=> rstn);
  always_comb assume (!rstn_released || rstn);

  always_ff @(posedge clk) begin
    if (!rstn) begin
      phase <= '0;
      current_w_beat <= '0;
    end else begin
      if (phase != 4'hf)
        phase <= phase + 1'b1;
      if (axi.w_valid && axi.w_ready && axi.w_last)
        current_w_beat <= '0;
      else if (axi.w_valid && axi.w_ready &&
               current_w_beat < MAX_BURST_LEN)
        current_w_beat <= current_w_beat + 1'b1;
    end
  end

  always_comb begin
    axi.aw_valid = 1'b0;
    axi.aw_ready = 1'b0;
    axi.aw_id = '0;
    axi.aw_addr = 8'h00;
    axi.aw_len = 8'd0;
    axi.aw_size = 3'd0;
    axi.aw_burst = 2'b01;
    axi.aw_lock = 1'b0;
    axi.aw_cache = 4'b0010;
    axi.aw_prot = '0;
    axi.aw_qos = '0;
    axi.aw_region = '0;
    axi.aw_atop = '0;
    axi.aw_user = '0;

    axi.w_valid = 1'b0;
    axi.w_ready = 1'b0;
    axi.w_data = '0;
    axi.w_strb = 2'b01;
    axi.w_last = 1'b1;
    axi.w_user = '0;

    axi.b_valid = 1'b0;
    axi.b_ready = 1'b0;
    axi.b_id = '0;
    axi.b_resp = '0;
    axi.b_user = '0;
    axi.ar_valid = 1'b0;
    axi.ar_ready = 1'b0;
    axi.ar_id = '0;
    axi.ar_addr = '0;
    axi.ar_len = '0;
    axi.ar_size = '0;
    axi.ar_burst = 2'b01;
    axi.ar_lock = 1'b0;
    axi.ar_cache = 4'b0010;
    axi.ar_prot = '0;
    axi.ar_qos = '0;
    axi.ar_region = '0;
    axi.ar_user = '0;
    axi.r_valid = 1'b0;
    axi.r_ready = 1'b0;
    axi.r_id = '0;
    axi.r_data = '0;
    axi.r_resp = '0;
    axi.r_last = 1'b0;
    axi.r_user = '0;

    case (MUTATION)
      // Legal live count-parity offer, stalled on both AW and W.
      0: begin
        if (phase >= 3) begin
          axi.aw_valid = 1'b1;
          axi.w_valid = 1'b1;
        end
      end

      // Legal accepted-AW/current-W association.  W is then stalled.
      1: begin
        if (phase == 2) begin
          axi.aw_valid = 1'b1;
          axi.aw_ready = 1'b1;
          axi.aw_len = 8'd1;
        end
        if (phase >= 3) begin
          axi.w_valid = 1'b1;
          axi.w_last = 1'b0;
        end
      end

      // Legal partial W-before-AW: saved beat zero is checked when the late
      // two-beat AW is offered while AWREADY remains LOW.
      2: begin
        if (phase == 2) begin
          axi.w_valid = 1'b1;
          axi.w_ready = 1'b1;
          axi.w_last = 1'b0;
          axi.w_strb = 2'b10;
        end
        if (phase >= 3) begin
          axi.aw_valid = 1'b1;
          axi.aw_addr = 8'h01;
          axi.aw_len = 8'd1;
          axi.w_valid = 1'b1;
          axi.w_strb = 2'b01;
        end
      end

      // Legal completed W-before-AW, validated from w_q[aw_count] before the
      // late AW can handshake.
      3: begin
        if (phase == 2) begin
          axi.w_valid = 1'b1;
          axi.w_ready = 1'b1;
          axi.w_strb = 2'b10;
        end
        if (phase >= 3) begin
          axi.aw_valid = 1'b1;
          axi.aw_addr = 8'h01;
        end
      end

      // Count parity with an illegal current strobe.  WLAST is correct.
      4: begin
        if (phase >= 3) begin
          axi.aw_valid = 1'b1;
          axi.w_valid = 1'b1;
          axi.w_strb = inject_bad ? 2'b10 : 2'b01;
        end
      end

      // Count parity with a legal strobe but missing terminal WLAST.
      5: begin
        if (phase >= 3) begin
          axi.aw_valid = 1'b1;
          axi.w_valid = 1'b1;
          axi.w_last = inject_bad ? 1'b0 : 1'b1;
        end
      end

      // An accepted AW followed by an illegal stalled current strobe.
      6: begin
        if (phase == 2) begin
          axi.aw_valid = 1'b1;
          axi.aw_ready = 1'b1;
        end
        if (phase >= 3) begin
          axi.w_valid = 1'b1;
          axi.w_strb = inject_bad ? 2'b10 : 2'b01;
        end
      end

      // An accepted AW followed by a stalled beat with missing WLAST.
      7: begin
        if (phase == 2) begin
          axi.aw_valid = 1'b1;
          axi.aw_ready = 1'b1;
          axi.aw_len = 8'd1;
        end
        if (phase >= 3) begin
          axi.w_valid = 1'b1;
          axi.w_last = inject_bad ? 1'b1 : 1'b0;
        end
      end

      // A partial W burst has already passed the late AW's terminal beat.
      8: begin
        if (phase == 2) begin
          axi.w_valid = 1'b1;
          axi.w_ready = 1'b1;
          axi.w_last = 1'b0;
        end
        if (phase >= 3) begin
          axi.aw_valid = 1'b1;
          axi.aw_len = inject_bad ? 8'd0 : 8'd1;
        end
      end

      // The late AW exposes an illegal byte lane in the accepted W prefix.
      9: begin
        if (phase == 2) begin
          axi.w_valid = 1'b1;
          axi.w_ready = 1'b1;
          axi.w_last = 1'b0;
          axi.w_strb = inject_bad ? 2'b10 : 2'b01;
        end
        if (phase >= 3) begin
          axi.aw_valid = 1'b1;
          axi.aw_len = 8'd1;
        end
      end

      // A one-beat completed W is offered a late two-beat AW.
      10: begin
        if (phase == 2) begin
          axi.w_valid = 1'b1;
          axi.w_ready = 1'b1;
        end
        if (phase >= 3) begin
          axi.aw_valid = 1'b1;
          axi.aw_len = inject_bad ? 8'd1 : 8'd0;
        end
      end

      // The late AW exposes an illegal strobe in a completed one-beat W.
      11: begin
        if (phase == 2) begin
          axi.w_valid = 1'b1;
          axi.w_ready = 1'b1;
          axi.w_strb = inject_bad ? 2'b10 : 2'b01;
        end
        if (phase >= 3)
          axi.aw_valid = 1'b1;
      end

      default: begin end
    endcase
  end

  axi_fvip_manager_env_contract #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W),
    .MAX_OUTSTANDING(2), .MAX_AW_AHEAD(2), .MAX_W_AHEAD(2),
    .MAX_BURST_LEN(MAX_BURST_LEN)
  ) i_contract (
    .clk(clk), .rstn(rstn), .current_w_beat(current_w_beat), .axi(axi)
  );

  // Every case reaches the pre-mutation state.  The four legal association
  // shapes also reach the terminal state.  Invalid cases retain a legal
  // inject_bad==0 escape trace so the production assumptions stay globally
  // satisfiable; only the corresponding inject_bad==1 terminal is blocked.
  c_setup: cover property (@(posedge clk) disable iff (!rstn) phase == 2);
  generate if (MUTATION < 4) begin : g_legal_offer
    c_terminal: cover property (
      @(posedge clk) disable iff (!rstn) phase == 6);
  end else begin : g_bad_offer
    c_bad_setup: cover property (
      @(posedge clk) disable iff (!rstn) inject_bad && phase == 2);
    c_terminal: cover property (
      @(posedge clk) disable iff (!rstn) inject_bad && phase == 6);
    c_legal_escape: cover property (
      @(posedge clk) disable iff (!rstn) !inject_bad && phase == 6);

    // Assumptions do not fire.  Prove instead that the selected bad offer
    // edge cannot be reached.  Removing or weakening the intended production
    // assumption makes this assertion fire at phase three.
    a_bad_offer_blocked: assert property (
      @(posedge clk) disable iff (!rstn) inject_bad |-> phase != 3);
  end endgenerate
endmodule

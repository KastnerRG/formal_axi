// AXI4 intra-channel rules for one complete interface.
//
// MANAGER_IS_ENV selects assume/assert polarity by signal ownership:
//   1: external Manager, DUT Subordinate (m_axi_fvip)
//   0: DUT Manager, external Subordinate (s_axi_fvip)
//
// Properties follow the rule order in docs/axi4_rule_coverage.csv, which mirrors
// the AXI4 specification.  Cross-channel and transaction rules live in
// the transaction tracker source set.

`define M_RULE(NAME, EXPR)                                \
  if (MANAGER_IS_ENV) begin : g_env_``NAME              \
    NAME: assume property (EXPR);                      \
  end else begin : g_dut_``NAME                         \
    NAME: assert property (EXPR);                       \
  end

`define S_RULE(NAME, EXPR)                                \
  if (MANAGER_IS_ENV) begin : g_dut_``NAME              \
    NAME: assert property (EXPR);                       \
  end else begin : g_env_``NAME                         \
    NAME: assume property (EXPR);                       \
  end

module axi_channel_fvip #(
  parameter int DATA_W = 32,
  parameter int MAX_STALL = 8,
  parameter bit ENABLE_MAX_STALL = 1'b0,
  parameter bit ENABLE_REQUEST_MAX_STALL = ENABLE_MAX_STALL,
  parameter bit ENABLE_RESPONSE_MAX_STALL = ENABLE_MAX_STALL,
  parameter bit ENABLE_EXCLUSIVE = 1'b0,
  parameter bit ENABLE_ATOP = 1'b0,
  parameter int MAX_BURST_LEN = 8,
  parameter bit MANAGER_IS_ENV = 1'b1,
  localparam int W_BEAT_W = (MAX_BURST_LEN < 1) ?
    1 : $clog2(MAX_BURST_LEN + 1)
) (
  input logic clk,
  input logic rstn,
  AXI_BUS.Monitor axi,
  output logic [W_BEAT_W-1:0] w_beat
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  wire w_hsk = axi.w_valid && axi.w_ready;
  wire w_last_hsk = w_hsk && axi.w_last;

  // Keep one explicit overflow state while sizing the counter to the active
  // burst profile.  A fixed AxLEN-sized counter makes an eight-beat proof
  // reason about hundreds of unreachable states.
  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      w_beat <= '0;
    end else begin
      if (w_last_hsk) w_beat <= '0;
      else if (w_hsk && w_beat < MAX_BURST_LEN)
        w_beat <= w_beat + 1'b1;
    end
  end

  generate
    // R001: once VALID is asserted it remains asserted until the handshake.
    `M_RULE(a_aw_valid_stall,
      axi.aw_valid && !axi.aw_ready |=> $stable(axi.aw_valid))
    `M_RULE(a_w_valid_stall,
      axi.w_valid && !axi.w_ready |=> $stable(axi.w_valid))
    `M_RULE(a_ar_valid_stall,
      axi.ar_valid && !axi.ar_ready |=> $stable(axi.ar_valid))
    `S_RULE(a_b_valid_stall,
      axi.b_valid && !axi.b_ready |=> $stable(axi.b_valid))
    `S_RULE(a_r_valid_stall,
      axi.r_valid && !axi.r_ready |=> $stable(axi.r_valid))

    // R002/R003/R017: useful handshake reachability.  A local safety checker
    // cannot prove that VALID is combinationally independent of READY.
    c_aw_valid_before_ready: cover property (axi.aw_valid && !axi.aw_ready);
    c_w_valid_before_ready:  cover property (axi.w_valid  && !axi.w_ready);
    c_ar_valid_before_ready: cover property (axi.ar_valid && !axi.ar_ready);
    c_b_valid_before_ready:  cover property (axi.b_valid  && !axi.b_ready);
    c_r_valid_before_ready:  cover property (axi.r_valid  && !axi.r_ready);

    // R004: VALID is LOW throughout reset.  Reset properties explicitly
    // override the module default disable because reset is their antecedent.
    `M_RULE(a_manager_valid_low_after_reset,
      @(posedge clk) disable iff ($isunknown(rstn))
        !rstn |=> !(axi.aw_valid || axi.w_valid || axi.ar_valid))
    `S_RULE(a_subordinate_valid_low_after_reset,
      @(posedge clk) disable iff ($isunknown(rstn))
        !rstn |=> !(axi.b_valid || axi.r_valid))

    // R005: the first VALID assertion is permitted only after a rising edge
    // at which reset is already deasserted.
    `M_RULE(a_manager_valid_low_with_reset_rise,
      $rose(rstn) |-> !(axi.aw_valid || axi.w_valid || axi.ar_valid))
    `S_RULE(a_subordinate_valid_low_with_reset_rise,
      $rose(rstn) |-> !(axi.b_valid || axi.r_valid))

    // R006-R010: every payload remains stable while its channel is stalled.
    `M_RULE(a_aw_payload_stall_stable,
      axi.aw_valid && !axi.aw_ready |=> $stable({
        axi.aw_id, axi.aw_addr, axi.aw_len, axi.aw_size, axi.aw_burst,
        axi.aw_lock, axi.aw_cache, axi.aw_prot, axi.aw_qos, axi.aw_region,
        axi.aw_atop, axi.aw_user}))
    `M_RULE(a_w_payload_stall_stable,
      axi.w_valid && !axi.w_ready |=>
        $stable({axi.w_data, axi.w_strb, axi.w_last, axi.w_user}))
    `M_RULE(a_ar_payload_stall_stable,
      axi.ar_valid && !axi.ar_ready |=> $stable({
        axi.ar_id, axi.ar_addr, axi.ar_len, axi.ar_size, axi.ar_burst,
        axi.ar_lock, axi.ar_cache, axi.ar_prot, axi.ar_qos, axi.ar_region,
        axi.ar_user}))
    `S_RULE(a_b_payload_stall_stable,
      axi.b_valid && !axi.b_ready |=>
        $stable({axi.b_id, axi.b_resp, axi.b_user}))
    `S_RULE(a_r_payload_stall_stable,
      axi.r_valid && !axi.r_ready |=>
        $stable({axi.r_id, axi.r_data, axi.r_resp, axi.r_last, axi.r_user}))

    // R011: VALID and READY are never unknown.
    `M_RULE(a_manager_control_known,
      !$isunknown({axi.aw_valid, axi.w_valid, axi.ar_valid,
                   axi.b_ready, axi.r_ready}))
    `S_RULE(a_subordinate_control_known,
      !$isunknown({axi.aw_ready, axi.w_ready, axi.ar_ready,
                   axi.b_valid, axi.r_valid}))

    // R012-R016: a valid payload contains no unknown bits.
    `M_RULE(a_aw_payload_known,
      axi.aw_valid |-> !$isunknown({
        axi.aw_id, axi.aw_addr, axi.aw_len, axi.aw_size, axi.aw_burst,
        axi.aw_lock, axi.aw_cache, axi.aw_prot, axi.aw_qos, axi.aw_region,
        axi.aw_atop, axi.aw_user}))
    `M_RULE(a_w_payload_known,
      axi.w_valid |->
        !$isunknown({axi.w_data, axi.w_strb, axi.w_last, axi.w_user}))
    `M_RULE(a_ar_payload_known,
      axi.ar_valid |-> !$isunknown({
        axi.ar_id, axi.ar_addr, axi.ar_len, axi.ar_size, axi.ar_burst,
        axi.ar_lock, axi.ar_cache, axi.ar_prot, axi.ar_qos, axi.ar_region,
        axi.ar_user}))
    `S_RULE(a_b_payload_known,
      axi.b_valid |-> !$isunknown({axi.b_id, axi.b_resp, axi.b_user}))
    `S_RULE(a_r_payload_known,
      axi.r_valid |->
        !$isunknown({axi.r_id, axi.r_data, axi.r_resp, axi.r_last, axi.r_user}))

    // R019: FIXED bursts contain 1-16 transfers.
    `M_RULE(a_aw_fixed_len,
      axi.aw_valid && axi.aw_burst == BURST_FIXED |-> axi.aw_len <= 8'd15)
    `M_RULE(a_ar_fixed_len,
      axi.ar_valid && axi.ar_burst == BURST_FIXED |-> axi.ar_len <= 8'd15)

    // R020: INCR supports 1-256 transfers by construction (8-bit AxLEN).

    // R021: WRAP bursts contain 2, 4, 8, or 16 transfers.
    `M_RULE(a_aw_wrap_len,
      axi.aw_valid && axi.aw_burst == BURST_WRAP |->
        axi.aw_len inside {8'd1, 8'd3, 8'd7, 8'd15})
    `M_RULE(a_ar_wrap_len,
      axi.ar_valid && axi.ar_burst == BURST_WRAP |->
        axi.ar_len inside {8'd1, 8'd3, 8'd7, 8'd15})

    // R022: transfer size does not exceed the data bus width.
    `M_RULE(a_aw_size_max,
      axi.aw_valid |-> (1 << axi.aw_size) <= (DATA_W / 8))
    `M_RULE(a_ar_size_max,
      axi.ar_valid |-> (1 << axi.ar_size) <= (DATA_W / 8))

    // R023: INCR bursts do not cross a 4KB boundary.
    `M_RULE(a_aw_no_4kb_cross,
      axi.aw_valid && axi.aw_burst == BURST_INCR |->
        (axi.aw_addr >> 12) == (end_byte(axi.aw_addr, axi.aw_len, axi.aw_size) >> 12))
    `M_RULE(a_ar_no_4kb_cross,
      axi.ar_valid && axi.ar_burst == BURST_INCR |->
        (axi.ar_addr >> 12) == (end_byte(axi.ar_addr, axi.ar_len, axi.ar_size) >> 12))

    // R024: WRAP start addresses are aligned to the transfer size.
    `M_RULE(a_aw_wrap_aligned,
      axi.aw_valid && axi.aw_burst == BURST_WRAP |->
        axi.aw_addr == aligned_addr(axi.aw_addr, axi.aw_size))
    `M_RULE(a_ar_wrap_aligned,
      axi.ar_valid && axi.ar_burst == BURST_WRAP |->
        axi.ar_addr == aligned_addr(axi.ar_addr, axi.ar_size))

    // R025: AxBURST does not use the reserved encoding.
    `M_RULE(a_aw_burst_not_reserved,
      axi.aw_valid |-> axi.aw_burst != 2'b11)
    `M_RULE(a_ar_burst_not_reserved,
      axi.ar_valid |-> axi.ar_burst != 2'b11)

    c_aw_fixed_burst: cover property (axi.aw_valid && axi.aw_burst == BURST_FIXED);
    c_aw_wrap_burst:  cover property (axi.aw_valid && axi.aw_burst == BURST_WRAP);
    c_ar_fixed_burst: cover property (axi.ar_valid && axi.ar_burst == BURST_FIXED);
    c_ar_wrap_burst:  cover property (axi.ar_valid && axi.ar_burst == BURST_WRAP);

    // R026-R030 are cross-channel burst rules implemented by the txn checker.

    // R031/R032: nonmodifiable AxCACHE encodings have no allocation hints.
    `M_RULE(a_aw_cache_non_mod,
      axi.aw_valid && !axi.aw_cache[1] |-> axi.aw_cache[3:2] == 2'b00)
    `M_RULE(a_ar_cache_non_mod,
      axi.ar_valid && !axi.ar_cache[1] |-> axi.ar_cache[3:2] == 2'b00)

    // R033-R040: optional exclusive-access profile.
    if (ENABLE_EXCLUSIVE) begin : g_exclusive
      `M_RULE(a_aw_excl_addr_aligned, axi.aw_valid && axi.aw_lock |-> (axi.aw_addr & (total_bytes(axi.aw_len, axi.aw_size) - 1)) == '0)
      `M_RULE(a_ar_excl_addr_aligned, axi.ar_valid && axi.ar_lock |-> (axi.ar_addr & (total_bytes(axi.ar_len, axi.ar_size) - 1)) == '0)
      `M_RULE(a_aw_excl_max_bytes, axi.aw_valid && axi.aw_lock |-> total_bytes(axi.aw_len, axi.aw_size) <= 128)
      `M_RULE(a_ar_excl_max_bytes, axi.ar_valid && axi.ar_lock |-> total_bytes(axi.ar_len, axi.ar_size) <= 128)
      `M_RULE(a_aw_excl_len, axi.aw_valid && axi.aw_lock |-> axi.aw_len <= 8'd15)
      `M_RULE(a_ar_excl_len, axi.ar_valid && axi.ar_lock |-> axi.ar_len <= 8'd15)
      `M_RULE(a_aw_excl_bytes_pow2, axi.aw_valid && axi.aw_lock |-> $onehot(total_bytes(axi.aw_len, axi.aw_size)))
      `M_RULE(a_ar_excl_bytes_pow2, axi.ar_valid && axi.ar_lock |-> $onehot(total_bytes(axi.ar_len, axi.ar_size)))
      `M_RULE(a_aw_excl_cache, axi.aw_valid && axi.aw_lock |-> axi.aw_cache[3:2] == 2'b00)
      `M_RULE(a_ar_excl_cache, axi.ar_valid && axi.ar_lock |-> axi.ar_cache[3:2] == 2'b00)
      c_aw_exclusive: cover property (axi.aw_valid && axi.aw_lock);
      c_ar_exclusive: cover property (axi.ar_valid && axi.ar_lock);
    end else begin : g_no_exclusive
      `M_RULE(c_profile_aw_lock_disabled,
        axi.aw_valid |-> !axi.aw_lock)
      `M_RULE(c_profile_ar_lock_disabled,
        axi.ar_valid |-> !axi.ar_lock)
    end

    // R041: EXOKAY is used only when exclusive accesses are enabled.
    if (!ENABLE_EXCLUSIVE) begin : g_no_exokay
      `S_RULE(a_b_no_exokay,
        axi.b_valid |-> axi.b_resp != RESP_EXOKAY)
      `S_RULE(a_r_no_exokay,
        axi.r_valid |-> axi.r_resp != RESP_EXOKAY)
    end

    // Remaining intra-channel profile bounds and optional progress policies.
    `M_RULE(c_profile_aw_burst_len,
      axi.aw_valid |-> axi.aw_len < MAX_BURST_LEN)
    `M_RULE(c_profile_ar_burst_len,
      axi.ar_valid |-> axi.ar_len < MAX_BURST_LEN)
    // Check the offered transfer, not only its handshake.  VALID describes a
    // real pending beat and remains stable under backpressure, so this is the
    // same bounded-packet policy without placing DUT-owned READY in the cone.
    //
    // An environment Manager is constrained deterministically on every
    // packet.  For a DUT Manager, choose an arbitrary packet start and retain
    // one bit until its WLAST handshake.  Because select_packet is free, a
    // proof covers every possible packet while giving induction a local
    // packet boundary.  This selector must never replace the universal
    // environment assumption: choosing no packet would weaken that contract.
    if (MANAGER_IS_ENV) begin : g_env_c_profile_w_packet_len
      c_profile_w_packet_len: assume property (
        axi.w_valid |-> w_beat < MAX_BURST_LEN &&
          (axi.w_last || w_beat + 1'b1 < MAX_BURST_LEN));
    end else begin : g_dut_c_profile_w_packet_len
      (* anyseq *) logic select_packet;
      logic watching_packet;

      s_select_packet_start: assume property (
        select_packet |-> axi.w_valid && w_beat == 0 && !watching_packet);
      c_profile_w_packet_len: assert property (
        (select_packet || watching_packet) && axi.w_valid |->
          w_beat < MAX_BURST_LEN &&
          (axi.w_last || w_beat + 1'b1 < MAX_BURST_LEN));
      c_select_packet: cover property (select_packet);

      always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
          watching_packet <= 1'b0;
        end else begin
          if (select_packet)
            watching_packet <= !w_last_hsk;
          else if (watching_packet && w_last_hsk)
            watching_packet <= 1'b0;
        end
      end
    end
    // R bursts may interleave across IDs, so a single channel-wide beat
    // counter is not meaningful.  Exact per-ID RLAST accounting belongs to
    // the transaction tracker, alongside the corresponding ARLEN.

    if (!ENABLE_ATOP) begin : g_no_atop
      `M_RULE(c_profile_atop_disabled,
        axi.aw_valid |-> axi.aw_atop == '0)
    end

    if (ENABLE_REQUEST_MAX_STALL) begin : g_request_ready_policy
      `S_RULE(a_aw_max_ready_after_valid,
        axi.aw_valid |-> ##[0:MAX_STALL] axi.aw_ready)
      `S_RULE(a_w_max_ready_after_valid,
        axi.w_valid |-> ##[0:MAX_STALL] axi.w_ready)
      `S_RULE(a_ar_max_ready_after_valid,
        axi.ar_valid |-> ##[0:MAX_STALL] axi.ar_ready)
    end
    if (ENABLE_RESPONSE_MAX_STALL) begin : g_response_ready_policy
      `M_RULE(a_b_max_ready_after_valid,
        axi.b_valid |-> ##[0:MAX_STALL] axi.b_ready)
      `M_RULE(a_r_max_ready_after_valid,
        axi.r_valid |-> ##[0:MAX_STALL] axi.r_ready)
    end
  endgenerate
endmodule

`undef M_RULE
`undef S_RULE

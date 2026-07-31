// Default is MASTER, to drive a slave
//  - {valid, data} - driven by fvip (assumed)
//  - {ready} - observed (asserted)

`ifdef AXI_FVIP_SLAVE_B
  `define ASSUME assert
  `define ASSERT assume
  `define AXI_MAX_STALL AXI_MAX_STALL_ENV
`else
  `define ASSUME assume
  `define ASSERT assert
  `define AXI_MAX_STALL AXI_MAX_STALL_DUT
`endif

module `MODNAME_B #(
  parameter int ID_W = 4,
  parameter int USER_W = 1,
  parameter int AXI_MAX_STALL_ENV = 10,
  parameter int AXI_MAX_STALL_DUT = 100
) (
  input logic clk,
  input logic rstn,
  input logic b_valid,
  input logic b_ready,
  input logic [ID_W-1:0] b_id,
  input logic [1:0] b_resp,
  input logic [USER_W-1:0] b_user
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  wire stall = b_valid && !b_ready;

  // B channel: write response handshake and payload checks.
  wire hsk = b_valid && b_ready;

  //___________ READY ___________

  // Formal bounded-stall check for BVALID -> BREADY.

  a_max_ready_after_valid:
    `ASSERT property (max_ready_after_valid(b_valid, b_ready, `AXI_MAX_STALL));

  //___________ VALID ___________

  // R003 - BVALID reset behavior.

  a_valid_low_after:
    `ASSUME property (low_after(rstn, b_valid));
  a_valid_not_with_rise:
    `ASSUME property (not_with_rise(rstn, b_valid));

  // R005 - BVALID/BREADY must be known.

  a_valid_not_unknown:
    `ASSUME property (not_unknown(b_valid));
  a_ready_not_unknown:
    `ASSERT property (not_unknown(b_ready));

  // R001 - BVALID held stable while stalled.

  a_valid_stall:
    `ASSUME property (stable_next_when(stall, b_valid));

  // Non-vacuity cover: BVALID before BREADY.

  c_valid_before_ready:
    cover property (valid_before_ready(b_valid, b_ready));

  //___________ ID ___________

  // R004/R006 - BID stable during stall and known when valid.

  a_id_stall_stable:
    `ASSUME property (stable_next_when(stall, b_id));
  a_id_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(b_valid, b_id));

  //___________ RESP ___________

  // R004/R006 - BRESP stable during stall and known when valid.

  a_resp_stall_stable:
    `ASSUME property (stable_next_when(stall, b_resp));
  a_resp_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(b_valid, b_resp));

  //___________ USER ___________

  // R004/R006 - BUSER stable during stall and known when valid.

  a_user_stall_stable:
    `ASSUME property (stable_next_when(stall, b_user));
  a_user_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(b_valid, b_user));
endmodule

`undef ASSUME
`undef ASSERT
`undef AXI_MAX_STALL

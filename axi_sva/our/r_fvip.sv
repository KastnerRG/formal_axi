// Default is MASTER, to drive a slave
//  - {valid, data} - driven by fvip (assumed)
//  - {ready} - observed (asserted)

`ifdef AXI_FVIP_SLAVE_R
  `define ASSUME assert
  `define ASSERT assume
  `define AXI_MAX_STALL AXI_MAX_STALL_ENV
`else
  `define ASSUME assume
  `define ASSERT assert
  `define AXI_MAX_STALL AXI_MAX_STALL_DUT
`endif

module `MODNAME_R #(
  parameter int DATA_W = 32,
  parameter int ID_W = 4,
  parameter int USER_W = 1,
  parameter int AXI_MAX_STALL_ENV = 10,
  parameter int AXI_MAX_STALL_DUT = 100
) (
  input logic clk,
  input logic rstn,
  input logic r_valid,
  input logic r_ready,
  input logic [ID_W-1:0] r_id,
  input logic [DATA_W-1:0] r_data,
  input logic [1:0] r_resp,
  input logic r_last,
  input logic [USER_W-1:0] r_user
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  wire stall = r_valid && !r_ready;

  // R channel: read data response handshake and payload checks.
  wire hsk = r_valid && r_ready;
  wire hsk_last = hsk && r_last;

  logic unsigned [8:0] i_beat; // one extra bit to detect overflow
  always_ff @(posedge clk)
    if      (!rstn)     i_beat <= '0;
    else if (hsk_last)  i_beat <= '0;
    else if (hsk)       i_beat <= i_beat + 8'd1;

  //___________ READY ___________

  // Formal bounded progress: RVALID must be accepted within AXI_MAX_STALL cycles.

  a_max_ready_after_valid:
    `ASSERT property (max_ready_after_valid(r_valid, r_ready, `AXI_MAX_STALL));

  //___________ VALID ___________

  // R003 - RVALID reset behavior.

  a_valid_low_after:
    `ASSUME property (low_after(rstn, r_valid));
  a_valid_not_with_rise:
    `ASSUME property (not_with_rise(rstn, r_valid));

  // R005 - RVALID/RREADY knownness.

  a_valid_not_unknown:
    `ASSUME property (not_unknown(r_valid));
  a_ready_not_unknown:
    `ASSERT property (not_unknown(r_ready));

  // R001 - RVALID held stable while stalled.

  a_valid_stall:
    `ASSUME property (stable_next_when(stall, r_valid));

  // Non-vacuity cover: RVALID high before RREADY.

  c_valid_before_ready:
    cover property (valid_before_ready(r_valid, r_ready));

  //___________ ID ___________

  // RID payload checks: stable while stalled, known when RVALID.

  a_id_stall_stable:
    `ASSUME property (stable_next_when(stall, r_id));
  a_id_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(r_valid, r_id));

  //___________ DATA ___________

  // RDATA payload checks: stable while stalled, known when RVALID.

  a_data_stall_stable:
    `ASSUME property (stable_next_when(stall, r_data));
  a_data_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(r_valid, r_data));

  //___________ RESP ___________

  // RRESP payload checks: stable while stalled, known when RVALID.

  a_resp_stall_stable:
    `ASSUME property (stable_next_when(stall, r_resp));
  a_resp_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(r_valid, r_resp));

  //___________ LAST ___________

  // RLAST payload checks: stable while stalled, known when RVALID.

  a_last_stall_stable:
    `ASSUME property (stable_next_when(stall, r_last));
  a_last_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(r_valid, r_last));

  // Read packet length bound: maximum 256 R-channel data beats.

  a_packet_len_max:
    `ASSUME property (burst_packet_len_max(hsk_last, i_beat));

  //___________ USER ___________

  // RUSER payload checks: stable while stalled, known when RVALID.

  a_user_stall_stable:
    `ASSUME property (stable_next_when(stall, r_user));
  a_user_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(r_valid, r_user));
endmodule

`undef ASSUME
`undef ASSERT
`undef AXI_MAX_STALL

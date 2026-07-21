// Default is MASTER, to drive a slave
//  - {valid, data} - driven by fvip (assumed)
//  - {ready} - observed (asserted)

`ifdef AXI_FVIP_SLAVE_W
  `define ASSUME assert
  `define ASSERT assume
  `define AXI_MAX_STALL AXI_MAX_STALL_ENV
`else
  `define ASSUME assume
  `define ASSERT assert
  `define AXI_MAX_STALL AXI_MAX_STALL_DUT
`endif

module `MODNAME_W #(
  parameter int DATA_W = 32,
  parameter int USER_W = 1,
  parameter int AXI_MAX_STALL_ENV = 10,
  parameter int AXI_MAX_STALL_DUT = 100
) (
  input logic clk,
  input logic rstn,
  input logic w_valid,
  input logic w_ready,
  input logic [DATA_W-1:0] w_data,
  input logic [DATA_W/8-1:0] w_strb,
  input logic w_last,
  input logic [USER_W-1:0] w_user
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  wire stall = w_valid && !w_ready;

  // W channel formal properties.
  // The W channel carries write data, byte strobes, and WLAST.
  // In default/master mode, WVALID and payload are constrained as environment inputs,
  // while WREADY is checked as the DUT response. The ASSUME/ASSERT macros swap
  // this direction when AXI_FVIP_SLAVE_W is defined.
  wire hsk = w_valid && w_ready;
  wire hsk_last = hsk && w_last;

  logic unsigned [8:0] i_beat;  // one extra bit to detect overflow
  always_ff @(posedge clk)
    if      (!rstn)    i_beat <= '0;
    else if (hsk_last) i_beat <= '0;
    else if (hsk)      i_beat <= i_beat + 8'd1;

  //___________ READY ___________

  // Formal progress/fairness bound, not a pure AXI protocol rule:
  // once WVALID is seen, WREADY must arrive within AXI_MAX_STALL cycles.
  // This avoids unbounded formal traces where the transfer stalls forever.

  a_max_ready_after_valid:
    `ASSERT property (max_ready_after_valid(w_valid, w_ready, `AXI_MAX_STALL));

  //___________ VALID ___________

  // R003 - Reset behavior:
  // WVALID must be LOW during reset and immediately after reset release.

  a_valid_low_after:
    `ASSUME property (low_after(rstn, w_valid));
  a_valid_not_with_rise:
    `ASSUME property (not_with_rise(rstn, w_valid));

  // R005 - Known control signals:
  // WVALID and WREADY must not be X/unknown.

  a_valid_not_unknown:
    `ASSUME property (not_unknown(w_valid));
  a_ready_not_unknown:
    `ASSERT property (not_unknown(w_ready));

  // R001 - VALID stability:
  // Once WVALID is asserted, it must remain stable until WVALID && WREADY.

  a_valid_stall:
    `ASSUME property (stable_next_when(stall, w_valid));

  // Cover for non-vacuity/debug:
  // Shows that the formal environment can create a cycle where WVALID is high
  // before WREADY accepts the transfer.

  c_valid_before_ready:
    cover property (valid_before_ready(w_valid, w_ready));

  //___________ DATA ___________

  // R004 - Payload stability:
  // WDATA must remain stable while WVALID is high and WREADY is low.

  a_data_stall_stable:
    `ASSUME property (stable_next_when(stall, w_data));
  // R006 - Known payload:
  // WDATA must not be X/unknown when WVALID is asserted.

  a_data_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(w_valid, w_data));

  //___________ STRB ___________

  // R004 - Payload stability:
  // WSTRB must remain stable while WVALID is high and WREADY is low.

  a_strb_stall_stable:
    `ASSUME property (stable_next_when(stall, w_strb));
  // R006 - Known payload:
  // WSTRB must not be X/unknown when WVALID is asserted.

  a_strb_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(w_valid, w_strb));

  //___________ LAST ___________

  // R004 - Payload stability:
  // WLAST must remain stable while WVALID is high and WREADY is low.

  a_last_stall_stable:
    `ASSUME property (stable_next_when(stall, w_last));
  // R006 - Known payload:
  // WLAST must not be X/unknown when WVALID is asserted.

  a_last_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(w_valid, w_last));

  // Write packet length bound:
  // A write burst must not exceed the AXI maximum of 256 data transfers.
  // This checks the beat counter when the final WLAST handshake occurs.

  a_packet_len_max:
    `ASSUME property (burst_packet_len_max(hsk_last, i_beat));


  //___________ USER ___________

  // R004 - Payload stability:
  // WUSER must remain stable while WVALID is high and WREADY is low.

  a_user_stall_stable:
    `ASSUME property (stable_next_when(stall, w_user));
  // R006 - Known payload:
  // WUSER must not be X/unknown when WVALID is asserted.

  a_user_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(w_valid, w_user));
endmodule

`undef ASSUME
`undef ASSERT
`undef AXI_MAX_STALL

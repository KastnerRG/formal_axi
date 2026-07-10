// Default is MASTER, to drive a slave
//  - {valid, data} - driven by fvip (assumed)
//  - {ready} - observed (asserted)

`ifdef AXI_FVIP_SLAVE_AW
  `define ASSUME assert
  `define ASSERT assume
  `define AXI_MAX_STALL AXI_MAX_STALL_ENV
`else
  `define ASSUME assume
  `define ASSERT assert
  `define AXI_MAX_STALL AXI_MAX_STALL_DUT
`endif

module `MODNAME_AW #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W = 4,
  parameter int USER_W = 1,
  parameter int AXI_MAX_STALL_ENV = 10,
  parameter int AXI_MAX_STALL_DUT = 100
) (
  input logic clk,
  input logic rstn,
  input logic aw_valid,
  input logic aw_ready,
  input logic [ID_W-1:0] aw_id,
  input logic [ADDR_W-1:0] aw_addr,
  input logic [7:0] aw_len,
  input logic [2:0] aw_size,
  input logic [1:0] aw_burst,
  input logic aw_lock,
  input logic [3:0] aw_cache,
  input logic [2:0] aw_prot,
  input logic [3:0] aw_qos,
  input logic [3:0] aw_region,
  input logic [5:0] aw_atop,
  input logic [USER_W-1:0] aw_user
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  wire stall = aw_valid && !aw_ready;
  wire hsk = aw_valid && aw_ready;

  // AW channel formal properties.
  //
  // This file applies reusable AXI rules from pkg_axi_fvip.sv to the
  // Write Address channel. In AXI, AW* payload signals are driven by the
  // master, while AWREADY is driven by the slave.
  //
  // Rule IDs below refer to the AXI Rules spreadsheet. Spec section references
  // must be manually confirmed against the official AXI specification before
  // finalizing.

  //___________ READY ___________

  // Formal progress/fairness bound, not a pure AXI protocol rule:
  // once AWVALID is seen, AWREADY must arrive within AXI_MAX_STALL cycles.
  // This keeps formal proofs from exploring infinite stalls.

  a_max_ready_after_valid:
    `ASSERT property (max_ready_after_valid(aw_valid, aw_ready, `AXI_MAX_STALL));

  //___________ VALID ___________

  // R003 - Reset behavior:
  // AWVALID must be LOW during reset and immediately after reset release.
  // TODO: confirm exact AXI spec section.

  a_valid_low_after:
    `ASSUME property (low_after(rstn, aw_valid));

  a_valid_not_with_rise:
    `ASSUME property (not_with_rise(rstn, aw_valid));

  // R005 - Known control signals:
  // AWVALID and AWREADY must not be X/Z.
  // TODO: confirm exact AXI spec section.

  a_valid_not_unknown:
    `ASSUME property (not_unknown(aw_valid));
  a_ready_not_unknown:
    `ASSERT property (not_unknown(aw_ready));

  // R001 - VALID stability:
  // Once AWVALID is asserted, it must remain asserted until the AW handshake.
  // Handshake occurs when AWVALID && AWREADY.
  // TODO: confirm exact AXI spec section.

  a_valid_stall:
    `ASSUME property (stable_next_when(stall, aw_valid));

  // Cover for non-vacuity/debug:
  // ensures formal can reach a case where AWVALID is HIGH before AWREADY.

  c_valid_before_ready:
    cover property (valid_before_ready(aw_valid, aw_ready));

  //___________ ID ___________

  // R004 - Payload stability:
  // AW* payload must remain stable while AWVALID is HIGH and AWREADY is LOW.
  // TODO: confirm exact AXI spec section.

  a_id_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_id));

  // R006 - Known payload:
  // AW* payload must not be X/Z when AWVALID is HIGH.
  // TODO: confirm exact AXI spec section.

  a_id_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_id));

  //___________ ADDR ___________

  a_addr_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_addr));
  a_addr_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_addr));

  //___________ LEN ___________

  a_len_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_len));
  a_len_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_len));

  //___________ SIZE ___________

  a_size_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_size));
  a_size_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_size));

  //___________ BURST ___________

  a_burst_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_burst));
  a_burst_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_burst));

  // R011 - Burst size:
  // AWSIZE must not request more bytes per transfer than the data bus supports.
  // TODO: confirm exact AXI spec section.

  a_burst_size_max:
    `ASSUME property (burst_size_max(aw_valid, aw_size, DATA_W));

  // R014 - Burst type encoding:
  // AWBURST must not use reserved encoding 2'b11.
  // TODO: confirm exact AXI spec section / table.

  a_burst_not_reserved:
    `ASSUME property (burst_not_reserved(aw_valid, aw_burst));

  // R008 - FIXED burst length:
  // FIXED bursts are limited to at most 16 transfers, so AWLEN <= 15.
  // TODO: confirm exact AXI spec section.

  a_burst_fixed_len:
    `ASSUME property (burst_fixed_len(aw_valid, aw_burst, aw_len));

  // R010 - WRAP burst length:
  // WRAP bursts must have length 2, 4, 8, or 16 transfers.
  // Since AWLEN encodes transfers-1, legal values are 1, 3, 7, and 15.
  // TODO: confirm exact AXI spec section.

  a_burst_wrap_len:
    `ASSUME property (burst_wrap_len(aw_valid, aw_burst, aw_len));

  // R012 - 4KB boundary:
  // INCR bursts must not cross a 4KB address boundary.
  // TODO: confirm exact AXI spec section.

  a_burst_no_4kb_cross:
    `ASSUME property (burst_no_4kb_cross(aw_valid, aw_burst, aw_addr, aw_len, aw_size));

  // R013 - WRAP alignment:
  // WRAP burst start address must be aligned to the transfer size.
  // TODO: confirm exact AXI spec section.

  a_burst_wrap_aligned:
    `ASSUME property (burst_wrap_addr_aligned(aw_valid, aw_burst, aw_addr, aw_size));

  //___________ LOCK ___________

  a_lock_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_lock));
  a_lock_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_lock));

  // Exclusive access constraints:
  // Exclusive accesses have restrictions on burst length, total byte count,
  // address alignment, maximum bytes, and cache attributes.
  // TODO: map to spreadsheet rule IDs and confirm AXI spec section.

  a_excl_len:
    `ASSUME property (excl_len(aw_valid, aw_lock, aw_len));
  a_excl_bytes_pow2:
    `ASSUME property (excl_bytes_pow2(aw_valid, aw_lock, aw_len, aw_size));
  a_excl_max_bytes:
    `ASSUME property (excl_max_bytes(aw_valid, aw_lock, aw_len, aw_size));
  a_excl_addr_aligned:
    `ASSUME property (excl_addr_aligned(aw_valid, aw_lock, aw_addr, aw_len, aw_size));
  a_excl_cache:
    `ASSUME property (excl_cache(aw_valid, aw_lock, aw_cache));

  //___________ CACHE ___________

  a_cache_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_cache));
  a_cache_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_cache));

  // Cache attribute constraint:
  // When AxCACHE indicates a non-modifiable transaction, reserved/invalid
  // cache encodings must not be used.
  // TODO: map to spreadsheet rule ID and confirm AXI spec section.

  a_cache_non_mod:
    `ASSUME property (cache_non_mod(aw_valid, aw_cache));

  //___________ PROT ___________

  a_prot_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_prot));
  a_prot_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_prot));

  //___________ QOS ___________

  a_qos_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_qos));
  a_qos_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_qos));

  //___________ REGION ___________

  a_region_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_region));
  a_region_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_region));

  //___________ ATOP ___________

  a_atop_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_atop));
  a_atop_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_atop));

  //___________ USER ___________

  a_user_stall_stable:
    `ASSUME property (stable_next_when(stall, aw_user));
  a_user_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(aw_valid, aw_user));
endmodule

`undef ASSUME
`undef ASSERT
`undef AXI_MAX_STALL

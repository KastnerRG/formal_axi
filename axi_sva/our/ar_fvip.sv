// Default is MASTER, to drive a slave
//  - {valid, data} - driven by fvip (assumed)
//  - {ready} - observed (asserted)

`ifdef AXI_FVIP_SLAVE_AR
  `define ASSUME assert
  `define ASSERT assume
  `define AXI_MAX_STALL AXI_MAX_STALL_ENV
`else
  `define ASSUME assume
  `define ASSERT assert
  `define AXI_MAX_STALL AXI_MAX_STALL_DUT
`endif

module `MODNAME_AR #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W = 4,
  parameter int USER_W = 1,
  parameter int AXI_MAX_STALL_ENV = 10,
  parameter int AXI_MAX_STALL_DUT = 100
) (
  input logic clk,
  input logic rstn,
  input logic ar_valid,
  input logic ar_ready,
  input logic [ID_W-1:0] ar_id,
  input logic [ADDR_W-1:0] ar_addr,
  input logic [7:0] ar_len,
  input logic [2:0] ar_size,
  input logic [1:0] ar_burst,
  input logic ar_lock,
  input logic [3:0] ar_cache,
  input logic [2:0] ar_prot,
  input logic [3:0] ar_qos,
  input logic [3:0] ar_region,
  input logic [USER_W-1:0] ar_user
);
  import pkg_axi_fvip::*;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  wire stall = ar_valid && !ar_ready;
  wire hsk = ar_valid && ar_ready;

  // AR channel formal properties.
  //
  // This file applies reusable AXI rules from pkg_axi_fvip.sv to the
  // Read Address channel. In AXI, AR* payload signals are driven by the
  // master, while ARREADY is driven by the slave.
  //
  // Rule IDs below refer to the AXI Rules spreadsheet. Spec section references
  // must be manually confirmed against the official AXI specification before
  // finalizing.

  //___________ READY ___________

  // Formal progress bound:
  // once ARVALID is seen, ARREADY must arrive within AXI_MAX_STALL cycles.
  // This keeps formal proofs from exploring infinite stalls.

  // Formal progress/fairness bound, not a pure AXI protocol rule:
  // once ARVALID is seen, ARREADY must arrive within AXI_MAX_STALL cycles.
  // This keeps formal proofs from exploring infinite stalls.

  a_max_ready_after_valid:
    `ASSERT property (max_ready_after_valid(ar_valid, ar_ready, `AXI_MAX_STALL));

  //___________ VALID ___________

  // R003 - Reset behavior:
  // ARVALID must be LOW during reset and immediately after reset release.
  // TODO: confirm exact AXI spec section.

  a_valid_low_after:
    `ASSUME property (low_after(rstn, ar_valid));
  a_valid_not_with_rise:
    `ASSUME property (not_with_rise(rstn, ar_valid));

  // R005 - Known control signals:
  // ARVALID and ARREADY must not be X/Z.
  // TODO: confirm exact AXI spec section.

  a_valid_not_unknown:
    `ASSUME property (not_unknown(ar_valid));
  a_ready_not_unknown:
    `ASSERT property (not_unknown(ar_ready));

  // R001 - VALID stability:
  // Once ARVALID is asserted, it must remain asserted until the AR handshake.
  // Handshake occurs when ARVALID && ARREADY.
  // TODO: confirm exact AXI spec section.

  a_valid_stall:
    `ASSUME property (stable_next_when(stall, ar_valid));

  // Cover for non-vacuity/debug:
  // ensures formal can reach a case where ARVALID is HIGH before ARREADY.

  c_valid_before_ready:
    cover property (valid_before_ready(ar_valid, ar_ready));

  //___________ ID ___________

  // R004 - Payload stability:
  // AR* payload must remain stable while ARVALID is HIGH and ARREADY is LOW.
  // TODO: confirm exact AXI spec section.

  a_id_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_id));

  // R006 - Known payload:
  // AR* payload must not be X/Z when ARVALID is HIGH.
  // TODO: confirm exact AXI spec section.

  a_id_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_id));

  //___________ ADDR ___________

  a_addr_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_addr));
  a_addr_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_addr));

  //___________ LEN ___________

  a_len_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_len));
  a_len_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_len));

  //___________ SIZE ___________

  a_size_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_size));
  a_size_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_size));

  //___________ BURST ___________

  a_burst_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_burst));
  a_burst_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_burst));

  // R011 - Burst size:
  // ARSIZE must not request more bytes per transfer than the data bus supports.
  // TODO: confirm exact AXI spec section.

  a_burst_size_max:
    `ASSUME property (burst_size_max(ar_valid, ar_size, DATA_W));

  // R014 - Burst type encoding:
  // ARBURST must not use reserved encoding 2'b11.
  // TODO: confirm exact AXI spec section / table.

  a_burst_not_reserved:
    `ASSUME property (burst_not_reserved(ar_valid, ar_burst));

  // R008 - FIXED burst length:
  // FIXED bursts are limited to at most 16 transfers, so ARLEN <= 15.
  // TODO: confirm exact AXI spec section.

  a_burst_fixed_len:
    `ASSUME property (burst_fixed_len(ar_valid, ar_burst, ar_len));

  // R010 - WRAP burst length:
  // WRAP bursts must have length 2, 4, 8, or 16 transfers.
  // Since ARLEN encodes transfers-1, legal values are 1, 3, 7, and 15.
  // TODO: confirm exact AXI spec section.

  a_burst_wrap_len:
    `ASSUME property (burst_wrap_len(ar_valid, ar_burst, ar_len));

  // R012 - 4KB boundary:
  // INCR bursts must not cross a 4KB address boundary.
  // TODO: confirm exact AXI spec section.

  a_burst_no_4kb_cross:
    `ASSUME property (burst_no_4kb_cross(ar_valid, ar_burst, ar_addr, ar_len, ar_size));



  // R013 - WRAP alignment:
  // WRAP burst start address must be aligned to the transfer size.
  // TODO: confirm exact AXI spec section.

  a_burst_wrap_aligned:
    `ASSUME property (burst_wrap_addr_aligned(ar_valid, ar_burst, ar_addr, ar_size));

  //___________ LOCK ___________

  a_lock_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_lock));
  a_lock_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_lock));
  // Exclusive access constraints:
  // Exclusive accesses have restrictions on burst length, total byte count,
  // address alignment, maximum bytes, and cache attributes.
  // TODO: map to spreadsheet rule IDs and confirm AXI spec section.

  a_excl_len:
    `ASSUME property (excl_len(ar_valid, ar_lock, ar_len));
  a_excl_bytes_pow2:
    `ASSUME property (excl_bytes_pow2(ar_valid, ar_lock, ar_len, ar_size));
  a_excl_max_bytes:
    `ASSUME property (excl_max_bytes(ar_valid, ar_lock, ar_len, ar_size));
  a_excl_addr_aligned:
    `ASSUME property (excl_addr_aligned(ar_valid, ar_lock, ar_addr, ar_len, ar_size));
  a_excl_cache:
    `ASSUME property (excl_cache(ar_valid, ar_lock, ar_cache));

  //___________ CACHE ___________

  a_cache_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_cache));
  a_cache_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_cache));
  // Cache attribute constraint:
  // When AxCACHE indicates a non-modifiable transaction, reserved/invalid
  // cache encodings must not be used.
  // TODO: map to spreadsheet rule ID and confirm AXI spec section.

  a_cache_non_mod:
    `ASSUME property (cache_non_mod(ar_valid, ar_cache));

  //___________ PROT ___________

  a_prot_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_prot));
  a_prot_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_prot));

  //___________ QOS ___________

  a_qos_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_qos));
  a_qos_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_qos));

  //___________ REGION ___________

  a_region_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_region));
  a_region_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_region));

  //___________ USER ___________

  a_user_stall_stable:
    `ASSUME property (stable_next_when(stall, ar_user));
  a_user_not_unknown_when_valid:
    `ASSUME property (not_unknown_when(ar_valid, ar_user));
endmodule

`undef ASSUME
`undef ASSERT
`undef AXI_MAX_STALL

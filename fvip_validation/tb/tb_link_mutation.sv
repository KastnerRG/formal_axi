`timescale 1ns/1ps

// Deliberately bad DUT-owned sources validate both endpoint polarities.
module tb_link_mutation(input logic clk, input logic rstn);
  localparam int ADDR_W = 32;
  localparam int DATA_W = 32;
  localparam int ID_W = 4;
  localparam int USER_W = 1;

  logic [2:0] phase;
  always_ff @(posedge clk)
    if (!rstn) phase <= '0;
    else if (phase != 7) phase <= phase + 1'b1;

  wire active = phase >= 1 && phase <= 3;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(ADDR_W), .AXI_DATA_WIDTH(DATA_W),
    .AXI_ID_WIDTH(ID_W), .AXI_USER_WIDTH(USER_W)
  ) manager_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(ADDR_W), .AXI_DATA_WIDTH(DATA_W),
    .AXI_ID_WIDTH(ID_W), .AXI_USER_WIDTH(USER_W)
  ) subordinate_axi ();

  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_BURST_LEN(8)
  ) manager_view ();
  axi_fvip_txn_view_if #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_BURST_LEN(8)
  ) subordinate_view ();

  // DUT Manager: AW payload changes while the environment holds AWREADY low.
  always_comb begin
    manager_axi.aw_valid = active;
    manager_axi.aw_id = 4'h1;
    manager_axi.aw_addr = {29'b0, phase};
    manager_axi.aw_len = 8'd0;
    manager_axi.aw_size = 3'd2;
    manager_axi.aw_burst = 2'b01;
    manager_axi.aw_lock = 1'b0;
    manager_axi.aw_cache = 4'b0010;
    manager_axi.aw_prot = '0;
    manager_axi.aw_qos = '0;
    manager_axi.aw_region = '0;
    manager_axi.aw_atop = '0;
    manager_axi.aw_user = '0;
    manager_axi.aw_ready = phase == 2;
    manager_axi.w_valid = 1'b0;
    manager_axi.w_data = '0;
    manager_axi.w_strb = '0;
    manager_axi.w_last = 1'b0;
    manager_axi.w_user = '0;
    manager_axi.w_ready = 1'b1;
    manager_axi.b_valid = 1'b0;
    manager_axi.b_id = '0;
    manager_axi.b_resp = '0;
    manager_axi.b_user = '0;
    manager_axi.b_ready = 1'b1;
    manager_axi.ar_valid = 1'b0;
    manager_axi.ar_id = '0;
    manager_axi.ar_addr = '0;
    manager_axi.ar_len = '0;
    manager_axi.ar_size = '0;
    manager_axi.ar_burst = 2'b01;
    manager_axi.ar_lock = 1'b0;
    manager_axi.ar_cache = 4'b0010;
    manager_axi.ar_prot = '0;
    manager_axi.ar_qos = '0;
    manager_axi.ar_region = '0;
    manager_axi.ar_user = '0;
    manager_axi.ar_ready = 1'b1;
    manager_axi.r_valid = active;
    manager_axi.r_id = 4'h1;
    manager_axi.r_data = '0;
    manager_axi.r_resp = '0;
    manager_axi.r_last = 1'b1;
    manager_axi.r_user = '0;
    manager_axi.r_ready = 1'b0;
  end

  // DUT Subordinate: BRESP changes while the environment holds BREADY low.
  always_comb begin
    subordinate_axi.aw_valid = active;
    subordinate_axi.aw_id = 4'h1;
    subordinate_axi.aw_addr = '0;
    subordinate_axi.aw_len = '0;
    subordinate_axi.aw_size = 3'd2;
    subordinate_axi.aw_burst = 2'b01;
    subordinate_axi.aw_lock = 1'b0;
    subordinate_axi.aw_cache = 4'b0010;
    subordinate_axi.aw_prot = '0;
    subordinate_axi.aw_qos = '0;
    subordinate_axi.aw_region = '0;
    subordinate_axi.aw_atop = '0;
    subordinate_axi.aw_user = '0;
    subordinate_axi.aw_ready = 1'b0;
    subordinate_axi.w_valid = 1'b0;
    subordinate_axi.w_data = '0;
    subordinate_axi.w_strb = '0;
    subordinate_axi.w_last = 1'b0;
    subordinate_axi.w_user = '0;
    subordinate_axi.w_ready = 1'b1;
    subordinate_axi.b_valid = active;
    subordinate_axi.b_id = 4'h1;
    subordinate_axi.b_resp = phase[0] ? 2'b10 : 2'b00;
    subordinate_axi.b_user = '0;
    subordinate_axi.b_ready = phase == 2;
    subordinate_axi.ar_valid = 1'b0;
    subordinate_axi.ar_id = '0;
    subordinate_axi.ar_addr = '0;
    subordinate_axi.ar_len = '0;
    subordinate_axi.ar_size = '0;
    subordinate_axi.ar_burst = 2'b01;
    subordinate_axi.ar_lock = 1'b0;
    subordinate_axi.ar_cache = 4'b0010;
    subordinate_axi.ar_prot = '0;
    subordinate_axi.ar_qos = '0;
    subordinate_axi.ar_region = '0;
    subordinate_axi.ar_user = '0;
    subordinate_axi.ar_ready = 1'b1;
    subordinate_axi.r_valid = 1'b0;
    subordinate_axi.r_id = '0;
    subordinate_axi.r_data = '0;
    subordinate_axi.r_resp = '0;
    subordinate_axi.r_last = 1'b0;
    subordinate_axi.r_user = '0;
    subordinate_axi.r_ready = 1'b1;
  end

  s_axi_fvip #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_STALL(1), .ENABLE_MAX_STALL(1'b1),
    .ENABLE_TRANSACTION(1'b0)
  ) bad_manager (
    .clk(clk), .rstn(rstn), .axi(manager_axi), .view(manager_view)
  );

  m_axi_fvip #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .USER_W(USER_W),
    .MAX_STALL(1), .ENABLE_MAX_STALL(1'b1),
    .ENABLE_TRANSACTION(1'b0)
  ) bad_subordinate (
    .clk(clk), .rstn(rstn), .axi(subordinate_axi),
    .view(subordinate_view)
  );

  cover property (@(posedge clk) phase == 3);
endmodule

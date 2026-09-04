// FIFO functionality only.  It consumes endpoint public views, so it cannot
// accidentally assume protocol legality or depend on checker internals.
module fv_axi_fifo_role_fvip #(
  parameter int DEPTH = 2,
  parameter bit FALL_THROUGH = 1'b0,
  parameter bit ENABLE_PROGRESS = 1'b0,
  parameter int MAX_DELAY = 100
) (
  input logic clk,
  input logic rstn,
  axi_fvip_txn_view_if.Consumer s_view,
  axi_fvip_txn_view_if.Consumer m_view
);
  wire s_aw_hsk = s_view.live_aw_valid && s_view.live_aw_ready;
  wire m_aw_hsk = m_view.live_aw_valid && m_view.live_aw_ready;
  wire s_w_hsk  = s_view.live_w_valid  && s_view.live_w_ready;
  wire m_w_hsk  = m_view.live_w_valid  && m_view.live_w_ready;
  wire m_b_hsk  = m_view.live_b_valid  && m_view.live_b_ready;
  wire s_b_hsk  = s_view.live_b_valid  && s_view.live_b_ready;
  wire s_ar_hsk = s_view.live_ar_valid && s_view.live_ar_ready;
  wire m_ar_hsk = m_view.live_ar_valid && m_view.live_ar_ready;
  wire m_r_hsk  = m_view.live_r_valid  && m_view.live_r_ready;
  wire s_r_hsk  = s_view.live_r_valid  && s_view.live_r_ready;

`define FIFO_ROLE_CHECK(CH, SIN, SHSK, MOUT, MHSK) \
  begin : g_``CH``_conservation \
    fv_fifo_tracker #( \
      .WIDTH($bits(SIN)), .MAX_OCCUPANCY(DEPTH), \
      .ALLOW_BYPASS(FALL_THROUGH), .ENABLE_PROGRESS(ENABLE_PROGRESS), \
      .MAX_DELAY(MAX_DELAY) \
    ) i_tracker ( \
      .clk(clk), .rstn(rstn), .s_data(SIN), .s_hsk(SHSK), \
      .m_data(MOUT), .m_hsk(MHSK) \
    ); \
  end

  // Each tracker proves forward appearance/order/payload with one selected
  // occurrence and inverse conservation with continuous occupancy.
  generate
    `FIFO_ROLE_CHECK(aw, s_view.live_aw, s_aw_hsk, m_view.live_aw, m_aw_hsk)
    `FIFO_ROLE_CHECK(w,  s_view.live_w,  s_w_hsk,  m_view.live_w,  m_w_hsk)
    `FIFO_ROLE_CHECK(b,  m_view.live_b,  m_b_hsk,  s_view.live_b,  s_b_hsk)
    `FIFO_ROLE_CHECK(ar, s_view.live_ar, s_ar_hsk, m_view.live_ar, m_ar_hsk)
    `FIFO_ROLE_CHECK(r,  m_view.live_r,  m_r_hsk,  s_view.live_r,  s_r_hsk)
  endgenerate
`undef FIFO_ROLE_CHECK
endmodule

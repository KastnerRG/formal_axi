// Cross-channel AXI transaction aggregate. The three selected-occurrence
// trackers are split into focused source files and connected here.
module `MODNAME_TXN #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W = 4,
  parameter int MAX_READ_OUTSTANDING = 4,
  parameter int MAX_WRITE_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 4,
  parameter int MAX_W_AHEAD = 4,
  parameter int MAX_BURST_LEN = 8,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16,
  parameter bit ENABLE_WRITE_DATA_PROGRESS = 1'b0,
  parameter int MAX_WRITE_DATA_DELAY = 16,
  localparam int W_BEAT_W = (MAX_BURST_LEN < 1) ?
    1 : $clog2(MAX_BURST_LEN + 1)
) (
  input logic clk,
  input logic rstn,
  input logic [W_BEAT_W-1:0] w_beat,
  AXI_BUS.Monitor axi
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int RD_COUNT_W = (MAX_READ_OUTSTANDING < 2) ?
    1 : $clog2(MAX_READ_OUTSTANDING+1);
  localparam int WR_COUNT_W = (MAX_WRITE_OUTSTANDING < 2) ?
    1 : $clog2(MAX_WRITE_OUTSTANDING+1);
  localparam int PAIR_MAX =
    (MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD;
  localparam int PAIR_SKEW_W = $clog2(PAIR_MAX + 1) + 1;

  wire aw_hsk = axi.aw_valid && axi.aw_ready;
  wire w_hsk = axi.w_valid && axi.w_ready;
  wire b_hsk = axi.b_valid && axi.b_ready;
  wire ar_hsk = axi.ar_valid && axi.ar_ready;
  wire r_hsk = axi.r_valid && axi.r_ready;
  wire w_complete = w_hsk && axi.w_last;
  wire r_complete = r_hsk && axi.r_last;

  // MAX_*_OUTSTANDING are global profile limits.  These scalar counters apply
  // to every transaction, including when this FVIP is constraining a formal
  // environment; selected-occurrence assumptions would not provide that
  // universal constraint.
  logic [RD_COUNT_W-1:0] rd_outstanding;
  logic [WR_COUNT_W-1:0] wr_outstanding;
  logic signed [PAIR_SKEW_W-1:0] write_skew;
  // Read and write assertions are each universally quantified over this ID;
  // they do not need independent copies of the same arbitrary domain.
  (* anyconst *) logic [ID_W-1:0] watch_id;

  // Questa 2023.2 does not reliably treat an undriven anyconst as stable in
  // the compiled formal model, so state the shared constant-domain contract.
  s_watch_id_constant: assume property (@(posedge clk)
    disable iff ($isunknown(rstn)) $stable(watch_id));

`ifdef MASTER
  // The external Manager must not offer a transfer for which its lifecycle
  // budget has no room.  Offer-level assumptions cannot suppress DUT-owned
  // READY and deliberately do not rely on a simultaneous DUT response.
  x_read_outstanding_bound: assume property (
    axi.ar_valid |-> rd_outstanding < MAX_READ_OUTSTANDING);
  x_write_outstanding_bound: assume property (
    axi.aw_valid |-> wr_outstanding < MAX_WRITE_OUTSTANDING);
`else
  x_read_outstanding_bound: assert property (
    ar_hsk |-> rd_outstanding < MAX_READ_OUTSTANDING || r_complete);
  x_write_outstanding_bound: assert property (
    aw_hsk |-> wr_outstanding < MAX_WRITE_OUTSTANDING || b_hsk);

`endif

  // A response can be offered only when some accepted write was already
  // data-complete before this sampled edge.  Positive AW/completed-W skew is
  // exactly the number of still-unpaired writes.  Deliberately do not deduct
  // a concurrent WLAST handshake: BVALID may follow that acceptance, but may
  // not anticipate it in the same cycle.  This selector-free accounting fact
  // reuses the two existing global observers and adds no proof state.
  wire [PAIR_SKEW_W-1:0] unpaired_writes = write_skew > 0 ?
    $unsigned(write_skew) : '0;
  x_b_has_global_completed_write: `TXN_DEST property (
    axi.b_valid |-> wr_outstanding > unpaired_writes);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      rd_outstanding <= '0;
      wr_outstanding <= '0;
    end else begin
      case ({ar_hsk, r_complete})
        2'b10: if (rd_outstanding < MAX_READ_OUTSTANDING)
          rd_outstanding <= rd_outstanding + 1'b1;
        2'b01: if (rd_outstanding != 0)
          rd_outstanding <= rd_outstanding - 1'b1;
        // An RLAST with no older request is already a protocol failure, but
        // it must not cancel a newly accepted AR in the observer state.
        2'b11: if (rd_outstanding == 0)
          rd_outstanding <= 1;
        default: rd_outstanding <= rd_outstanding;
      endcase
      case ({aw_hsk, b_hsk})
        2'b10: if (wr_outstanding < MAX_WRITE_OUTSTANDING)
          wr_outstanding <= wr_outstanding + 1'b1;
        2'b01: if (wr_outstanding != 0)
          wr_outstanding <= wr_outstanding - 1'b1;
        // Likewise retain a newly accepted AW if an orphan B appears in the
        // same cycle.  The no-orphan assertion still reports the violation.
        2'b11: if (wr_outstanding == 0)
          wr_outstanding <= 1;
        default: wr_outstanding <= wr_outstanding;
      endcase
    end
  end

  `MODNAME_READ_TRACKER #(
    .ID_W(ID_W),
    .MAX_OUTSTANDING(MAX_READ_OUTSTANDING),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS),
    .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY)
  ) i_rd_tracker (
    .clk(clk), .rstn(rstn), .watch_id(watch_id),
    .ar_hsk(ar_hsk), .ar_id(axi.ar_id), .ar_len(axi.ar_len),
    .r_valid(axi.r_valid), .r_hsk(r_hsk), .r_id(axi.r_id), .r_last(axi.r_last)
  );

  `MODNAME_PAIR_TRACKER #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W),
    .MAX_A_AHEAD(MAX_AW_AHEAD),
    .MAX_B_AHEAD(MAX_W_AHEAD),
    .CONFIG_MAX_A_AHEAD(MAX_AW_AHEAD),
    .CONFIG_MAX_B_AHEAD(MAX_W_AHEAD),
    .MAX_BURST_LEN(MAX_BURST_LEN),
    .ENABLE_WRITE_DATA_PROGRESS(ENABLE_WRITE_DATA_PROGRESS),
    .MAX_WRITE_DATA_DELAY(MAX_WRITE_DATA_DELAY)
  ) i_aw_w_tracker (
    .clk(clk), .rstn(rstn),
    .aw_valid(axi.aw_valid), .aw_hsk(aw_hsk),
    .aw_addr(axi.aw_addr), .aw_len(axi.aw_len),
    .aw_size(axi.aw_size), .aw_burst(axi.aw_burst), .w_valid(axi.w_valid),
    .w_hsk(w_hsk), .w_strb(axi.w_strb), .w_last(axi.w_last),
    .current_w_beat(w_beat),
    .skew(write_skew)
  );

  `MODNAME_WRITE_TRACKER #(
    .ID_W(ID_W),
    .MAX_OUTSTANDING(MAX_WRITE_OUTSTANDING),
    .MAX_AW_AHEAD(MAX_AW_AHEAD),
    .MAX_W_AHEAD(MAX_W_AHEAD),
    .ENABLE_RESPONSE_PROGRESS(ENABLE_RESPONSE_PROGRESS),
    .MAX_RESPONSE_DELAY(MAX_RESPONSE_DELAY)
  ) i_wr_b_tracker (
    .clk(clk), .rstn(rstn), .watch_id(watch_id),
    .aw_hsk(aw_hsk), .aw_id(axi.aw_id), .w_complete(w_complete),
    .skew(write_skew),
    .b_valid(axi.b_valid), .b_hsk(b_hsk), .b_id(axi.b_id)
  );

  c_read_interleave: cover property (r_hsk && !axi.r_last ##[1:8] r_hsk && axi.r_id != $past(axi.r_id));
endmodule

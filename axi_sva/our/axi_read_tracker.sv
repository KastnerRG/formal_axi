// Constant-state AXI4 normal-transaction tracking.
//
// Every checker selects one arbitrary occurrence and tracks only its bounded
// relative rank.  State grows with ID/burst widths and the logarithm of the
// configured bounds, never with the number of outstanding transactions.

module `MODNAME_READ_TRACKER #(
  parameter int ID_W = 4,
  parameter int MAX_OUTSTANDING = 4,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16
) (
  input logic clk,
  input logic rstn,
  input logic ar_hsk,
  input logic [ID_W-1:0] ar_id,
  input logic [7:0] ar_len,
  input logic r_valid,
  input logic r_hsk,
  input logic [ID_W-1:0] r_id,
  input logic r_last
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int COUNT_W = (MAX_OUTSTANDING < 2) ? 1 : $clog2(MAX_OUTSTANDING+1);
  localparam int AGE_W = (MAX_RESPONSE_DELAY < 2) ?
    1 : $clog2(MAX_RESPONSE_DELAY+1);

  (* anyconst *) logic [ID_W-1:0] watch_id;
  (* anyseq *) logic select_now;
  logic selected, pending, completed;
  logic [COUNT_W-1:0] outstanding, rank;
  logic [7:0] watched_len, watched_beat;
  logic [AGE_W-1:0] rsp_age;

  wire ar_watch = ar_hsk && ar_id == watch_id;
  wire r_watch = r_valid && r_id == watch_id;
  wire r_watch_hsk = r_hsk && r_id == watch_id;
  wire r_watch_last_hsk = r_watch_hsk && r_last;
  wire rsp_visible = pending && rank == 0 && r_watch;

  // Questa 2023.2 does not reliably treat an undriven anyconst as stable in
  // the compiled formal model, so state the constant-domain contract.
  s_watch_id_constant: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    $stable(watch_id));
  s_select_request: assume property (select_now |-> ar_watch && !selected);
  s_select_once: assume property (selected |-> !select_now);

  x_r_has_ar: `TXN_DEST property (r_watch |-> outstanding != 0);
  x_r_last_exact: `TXN_DEST property (pending && rank == 0 && r_watch |->
      r_last == (watched_beat == watched_len));

  // MAX_RESPONSE_DELAY bounds availability of each required response beat.
  // Once a selected beat is visible, MAX_STALL separately bounds acceptance.
  generate if (ENABLE_RESPONSE_PROGRESS) begin : g_response_progress
    x_read_response_progress: `TXN_DEST property (
      pending |-> rsp_visible || rsp_age < MAX_RESPONSE_DELAY);
  end endgenerate

  c_read_request: cover property (ar_hsk);
  c_read_response: cover property (r_hsk && r_last);
  c_read_max_occupancy: cover property (outstanding == MAX_OUTSTANDING);
  c_select: cover property (select_now);
  c_select_with_rank: cover property (select_now && outstanding != 0);
  c_complete: cover property (completed);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      outstanding <= '0;
      selected <= 1'b0;
      pending <= 1'b0;
      completed <= 1'b0;
      rank <= '0;
      watched_len <= '0;
      watched_beat <= '0;
      rsp_age <= '0;
    end else begin
      case ({ar_watch, r_watch_last_hsk})
        2'b10: outstanding <= outstanding + 1'b1;
        2'b01: if (outstanding != 0)
          outstanding <= outstanding - 1'b1;
        default: outstanding <= outstanding;
      endcase

      if (select_now) begin
        selected <= 1'b1;
        pending <= 1'b1;
        watched_len <= ar_len;
        watched_beat <= '0;
        rsp_age <= '0;
        // A same-cycle RLAST belongs to an older request.  Remove it from the
        // number of transactions ahead of the newly selected AR.
        rank <= outstanding - (r_watch_last_hsk ? 1'b1 : 1'b0);
      end else if (pending && r_watch_hsk) begin
        if (rank != 0) begin
          if (r_last)
            rank <= rank - 1'b1;
        end else if (r_last) begin
          pending <= 1'b0;
          completed <= 1'b1;
        end else begin
          watched_beat <= watched_beat + 1'b1;
        end
      end

      if (pending) begin
        if (rsp_visible)
          rsp_age <= '0;
        else if (rsp_age < MAX_RESPONSE_DELAY)
          rsp_age <= rsp_age + 1'b1;
      end
    end
  end
endmodule


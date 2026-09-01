// Selected AW occurrence tracked through its W pairing and ordered B response.
// An arbitrary-ID scalar count rejects phantom/duplicate/wrong-ID B without a
// queue of every outstanding write.
module `MODNAME_WRITE_TRACKER #(
  parameter int ID_W = 4,
  parameter int MAX_OUTSTANDING = 4,
  parameter int MAX_AW_AHEAD = 8,
  parameter int MAX_W_AHEAD = 8,
  parameter bit ENABLE_RESPONSE_PROGRESS = 1'b0,
  parameter int MAX_RESPONSE_DELAY = 16
) (
  input logic clk,
  input logic rstn,
  input logic aw_hsk,
  input logic [ID_W-1:0] aw_id,
  input logic w_complete,
  input logic b_valid,
  input logic b_hsk,
  input logic [ID_W-1:0] b_id
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rstn);

  localparam int WRITE_CAPACITY = MAX_OUTSTANDING + MAX_AW_AHEAD;
  localparam int COUNT_W = (WRITE_CAPACITY < 2) ? 1 : $clog2(WRITE_CAPACITY+1);
  localparam int PAIR_MAX = (MAX_AW_AHEAD > MAX_W_AHEAD) ? MAX_AW_AHEAD : MAX_W_AHEAD;
  localparam int PAIR_W = (PAIR_MAX < 2) ? 1 : $clog2(PAIR_MAX+1);
  localparam int SKEW_W = PAIR_W + 1;
  localparam int AGE_W = (MAX_RESPONSE_DELAY < 2) ?
    1 : $clog2(MAX_RESPONSE_DELAY+1);

  (* anyconst *) logic [ID_W-1:0] watch_id;
  (* anyseq *) logic select_now;
  logic selected, pending, completed;
  logic [COUNT_W-1:0] outstanding, b_rank;
  logic [PAIR_W-1:0] w_rank;
  logic w_pending, wr_data_complete;
  logic signed [SKEW_W-1:0] skew;
  logic [AGE_W-1:0] rsp_age;

  wire aw_watch = aw_hsk && aw_id == watch_id;
  wire b_watch = b_valid && b_id == watch_id;
  wire b_watch_hsk = b_hsk && b_id == watch_id;
  wire rsp_visible = pending && wr_data_complete && b_rank == 0 && b_watch;

  s_watch_id_constant: assume property (@(posedge clk) disable iff ($isunknown(rstn))
    $stable(watch_id));
  s_select_request: assume property (select_now |-> aw_watch && !selected);
  s_select_once: assume property (selected |-> !select_now);

  x_no_orphan_response: `TXN_DEST property (b_watch |-> outstanding != 0);
  x_b_has_completed_write: `TXN_DEST property (
    pending && b_rank == 0 && b_watch |->
      wr_data_complete || (w_pending && w_complete && w_rank == 0));

  generate if (ENABLE_RESPONSE_PROGRESS) begin : g_response_progress
    x_write_response_progress: `TXN_DEST property (
      pending && wr_data_complete |-> rsp_visible || rsp_age < MAX_RESPONSE_DELAY);
  end endgenerate

  c_select: cover property (select_now);
  c_select_with_rank: cover property (select_now && outstanding != 0);
  c_complete: cover property (completed);
  c_b_response: cover property (b_hsk);

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      outstanding <= '0;
      selected <= 1'b0;
      pending <= 1'b0;
      completed <= 1'b0;
      b_rank <= '0;
      w_rank <= '0;
      w_pending <= 1'b0;
      wr_data_complete <= 1'b0;
      skew <= '0;
      rsp_age <= '0;
    end else begin
      case ({aw_hsk, w_complete})
        2'b10: skew <= skew + 1;
        2'b01: skew <= skew - 1;
        default: skew <= skew;
      endcase

      case ({aw_watch, b_watch_hsk})
        2'b10: outstanding <= outstanding + 1'b1;
        2'b01: if (outstanding != 0)
          outstanding <= outstanding - 1'b1;
        default: outstanding <= outstanding;
      endcase

      if (select_now) begin
        selected <= 1'b1;
        pending <= 1'b1;
        b_rank <= outstanding - (b_watch_hsk ? 1'b1 : 1'b0);
        if (skew < 0 || (w_complete && skew == 0)) begin
          wr_data_complete <= 1'b1;
          rsp_age <= '0;
        end else begin
          w_pending <= 1'b1;
          w_rank <= skew - (w_complete ? 1'b1 : 1'b0);
        end
      end else begin
        if (w_pending && w_complete) begin
          if (w_rank == 0) begin
            w_pending <= 1'b0;
            wr_data_complete <= 1'b1;
            rsp_age <= '0;
          end else begin
            w_rank <= w_rank - 1'b1;
          end
        end

        if (pending && b_watch_hsk) begin
          if (b_rank == 0) begin
            pending <= 1'b0;
            completed <= 1'b1;
          end else begin
            b_rank <= b_rank - 1'b1;
          end
        end
      end


      if (pending && wr_data_complete) begin
        if (rsp_visible)
          rsp_age <= '0;
        else if (rsp_age < MAX_RESPONSE_DELAY)
          rsp_age <= rsp_age + 1'b1;
      end
    end
  end
endmodule


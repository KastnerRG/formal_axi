`timescale 1ns/1ps

// Exhaustive mutation model shared by the bounded reference and smart tracker.
// MUTATION: 0 good, 1 phantom, 2 drop, 3 duplicate, 4 corrupt, 5 reorder,
// 6 deadlock.
module tb_fifo_mutation #(
  parameter int MUTATION = 0
) (
  input logic clk,
  input logic rstn
);
  localparam int WIDTH = 8;
  localparam int DEPTH = 2;

  (* anyseq *) logic [WIDTH-1:0] s_data;
  (* anyseq *) logic s_valid;
  logic s_ready, m_valid, m_ready;
  logic [WIDTH-1:0] m_data;
  logic [WIDTH-1:0] queue [0:1];
  logic [1:0] count;
  logic [1:0] ready_phase;
  logic duplicated;

  // Periodic backpressure makes the two-entry reorder case reachable while
  // retaining a finite liveness bound for the progress mutation.
  assign m_ready = ready_phase[1];
  assign s_ready = count < DEPTH;

  always_comb begin
    m_valid = count != 0;
    m_data = queue[0];
    case (MUTATION)
      1: begin m_valid = 1'b1; m_data = 'h5a; end
      4: m_data = queue[0] ^ 8'h01;
      5: if (count == 2) m_data = queue[1];
      6: m_valid = 1'b0;
      default: begin end
    endcase
  end

  wire push = s_valid && s_ready;
  wire pop = m_valid && m_ready;
  wire effective_pop = pop && !(MUTATION == 3 && !duplicated);
  wire effective_push = push && MUTATION != 2;

  always_ff @(posedge clk) begin
    if (!rstn) begin
      count <= '0;
      ready_phase <= '0;
      duplicated <= 1'b0;
    end else begin
      ready_phase <= ready_phase + 1'b1;
      case ({effective_push, effective_pop})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: count <= count;
      endcase
      if (effective_pop && count != 0)
        queue[0] <= queue[1];
      if (effective_push)
        queue[count - ((effective_pop && count != 0) ? 1'b1 : 1'b0)] <= s_data;
      if (MUTATION == 3 && pop && count != 0 && !duplicated)
        duplicated <= 1'b1;
    end
  end

  wire s_hsk = s_valid && s_ready;
  wire m_hsk = m_valid && m_ready;
  fv_fifo_oracle #(
    .WIDTH(WIDTH), .DEPTH(DEPTH), .ENABLE_PROGRESS(1'b1), .MAX_DELAY(6)
  ) i_oracle (.*);
  fv_fifo_tracker #(
    .WIDTH(WIDTH), .MAX_OCCUPANCY(DEPTH), .ENABLE_PROGRESS(1'b1), .MAX_DELAY(6)
  ) i_tracker (.*);

  cover property (@(posedge clk) disable iff (!rstn)
    s_hsk ##[1:8] m_hsk);
  cover property (@(posedge clk) disable iff (!rstn)
    s_hsk ##1 s_hsk ##[1:8] m_hsk);
endmodule

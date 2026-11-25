// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Posted forwarder for one switch hop. The upstream completer (CQ) presents
// 64-bit descriptor beats in the low 64 bits, including when the user bus
// is 128 or 256 bits wide. Beat 1 carries the request type at [14:11], the
// requester id at [47:32], and the tag at [55:48].
//
// A MemWr is rewritten into the requester (RQ) descriptor the downstream
// port consumes: tag at [39:32], requester id at [55:40]. Config, IO, and
// reads are dropped through tlast. At 128 bits the descriptor is one beat
// {rq_b1, b0} and the dword follows. At 256 bits the dword rides in the
// same beat, above the 16-byte descriptor.

module rivet_sw_posted_fwd #(
  parameter int unsigned DATA_W = 64,
  parameter int unsigned KEEP_W = DATA_W / 32,
  parameter int unsigned USER_W = 88
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic [DATA_W-1:0]    s_tdata_i,
  input  logic [KEEP_W-1:0]    s_tkeep_i,
  input  logic                 s_tlast_i,
  input  logic                 s_tvalid_i,
  output logic                 s_tready_o,
  input  logic [USER_W-1:0]    s_tuser_i,

  output logic [DATA_W-1:0]    m_tdata_o,
  output logic [KEEP_W-1:0]    m_tkeep_o,
  output logic                 m_tlast_o,
  output logic                 m_tvalid_o,
  input  logic                 m_tready_i,
  output logic [USER_W-1:0]    m_tuser_o
);

  localparam logic [3:0] MEMWR = 4'b0001;
  localparam int unsigned QN = 4;

  typedef enum logic [1:0] {
    ST_B0   = 2'd0,
    ST_B1   = 2'd1,
    ST_MORE = 2'd2,
    ST_DROP = 2'd3
  } st_e;

  st_e                    st_q;
  logic                   wide_q;
  logic [63:0]            b0_q, b1_q;
  logic [USER_W-1:0]      user_q;
  logic [DATA_W-1:0]      q_d [0:QN-1];
  logic [KEEP_W-1:0]      q_k [0:QN-1];
  logic                   q_l [0:QN-1];
  logic [USER_W-1:0]      q_u [0:QN-1];
  logic [1:0]             q_w_q, q_r_q;
  logic [2:0]             q_n_q;

  assign s_tready_o = (q_n_q < 3'd2);
  assign m_tvalid_o = (q_n_q != 3'd0);
  assign m_tdata_o  = q_d[q_r_q];
  assign m_tkeep_o  = q_k[q_r_q];
  assign m_tlast_o  = q_l[q_r_q];
  assign m_tuser_o  = q_u[q_r_q];

  function automatic logic [63:0] to_rq(input logic [63:0] cq);
    logic [10:0] len;
    logic [3:0]  typ;
    logic [15:0] req;
    logic [7:0]  tag;
    len = cq[10:0];
    typ = cq[14:11];
    req = cq[47:32];
    tag = cq[55:48];
    return {8'h00, req, tag, 17'h0, typ, len};
  endfunction

  function automatic logic [DATA_W-1:0] zext64(input logic [63:0] v);
    logic [DATA_W-1:0] r;
    r = '0;
    r[63:0] = v;
    return r;
  endfunction

  wire take = s_tvalid_i && s_tready_o;
  wire pop  = m_tvalid_o && m_tready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q   <= ST_B0;
      wide_q <= 1'b0;
      b0_q   <= '0;
      b1_q   <= '0;
      user_q <= '0;
      q_w_q  <= '0;
      q_r_q  <= '0;
      q_n_q  <= '0;
    end else begin
      logic [2:0] n;
      logic [1:0] w;
      n = q_n_q;
      w = q_w_q;
      if (pop) begin
        q_r_q <= q_r_q + 2'd1;
        n = n - 3'd1;
      end
      if (take && (st_q == ST_B0)) begin
        b0_q   <= s_tdata_i[63:0];
        user_q <= s_tuser_i;
        wide_q <= 1'b0;
        st_q   <= s_tlast_i ? ST_B0 : ST_B1;
      end else if (take && (st_q == ST_B1)) begin
        if (s_tdata_i[14:11] == MEMWR) begin
          b1_q <= to_rq(s_tdata_i[63:0]);
          if ((DATA_W == 64) && !s_tlast_i) begin
            q_d[w] <= zext64(b0_q);
            q_k[w] <= KEEP_W'(2'b11);
            q_l[w] <= 1'b0;
            q_u[w] <= user_q;
            w = w + 2'd1;
            n = n + 3'd1;
            q_d[w] <= zext64(to_rq(s_tdata_i[63:0]));
            q_k[w] <= KEEP_W'(2'b11);
            q_l[w] <= 1'b0;
            q_u[w] <= user_q;
            w = w + 2'd1;
            n = n + 3'd1;
            st_q <= ST_MORE;
          end else if (s_tlast_i) begin
            st_q <= ST_B0;
          end else begin
            wide_q <= 1'b1;
            st_q   <= ST_MORE;
          end
        end else begin
          st_q <= s_tlast_i ? ST_B0 : ST_DROP;
        end
      end else if (take && (st_q == ST_MORE) && wide_q) begin
        logic [255:0] wide;
        logic [7:0]   k8;
        wide = '0;
        k8   = '0;
        wide[63:0]   = b0_q;
        wide[127:64] = b1_q;
        if (DATA_W == 128) begin
          q_d[w] <= wide[DATA_W-1:0];
          q_k[w] <= KEEP_W'(4'hF);
          q_l[w] <= 1'b0;
          q_u[w] <= user_q;
          w = w + 2'd1;
          n = n + 3'd1;
          wide = '0;
          wide[31:0] = s_tdata_i[31:0];
          q_d[w] <= wide[DATA_W-1:0];
          q_k[w] <= KEEP_W'(4'h1);
          q_l[w] <= s_tlast_i;
          q_u[w] <= '0;
          w = w + 2'd1;
          n = n + 3'd1;
        end else begin
          wide[159:128] = s_tdata_i[31:0];
          k8[4:0] = 5'b1_1111;
          q_d[w] <= wide[DATA_W-1:0];
          q_k[w] <= k8[KEEP_W-1:0];
          q_l[w] <= s_tlast_i;
          q_u[w] <= user_q;
          w = w + 2'd1;
          n = n + 3'd1;
        end
        wide_q <= 1'b0;
        st_q   <= s_tlast_i ? ST_B0 : ST_MORE;
      end else if (take && (st_q == ST_MORE)) begin
        q_d[w] <= zext64(s_tdata_i[63:0]);
        q_k[w] <= KEEP_W'(2'b11);
        q_l[w] <= s_tlast_i;
        q_u[w] <= '0;
        w = w + 2'd1;
        n = n + 3'd1;
        if (s_tlast_i)
          st_q <= ST_B0;
      end else if (take && (st_q == ST_DROP)) begin
        if (s_tlast_i)
          st_q <= ST_B0;
      end
      q_w_q <= w;
      q_n_q <= n;
    end
  end

endmodule

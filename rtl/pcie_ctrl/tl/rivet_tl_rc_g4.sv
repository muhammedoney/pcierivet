// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack a 32-byte Cpl/CplD stream into the 256-bit Requester Completion
// port. Descriptor beats stay in tdata[63:0] so the scoreboard still
// reads the tag from beat 2. Payload bytes past the 12-byte header are
// kept and packed into 32-byte user beats.

module rivet_tl_rc_g4 #(
  parameter int unsigned DATA_W = 256
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic [255:0] rx_tdata_i,
  input  logic [31:0]  rx_tkeep_i,
  input  logic         rx_tlast_i,
  input  logic         rx_tvalid_i,
  input  logic         rx_abort_i,
  output logic         rx_tready_o,

  output logic [DATA_W-1:0]     m_axis_rc_tdata,
  output logic [DATA_W/32-1:0]  m_axis_rc_tkeep,
  output logic                  m_axis_rc_tlast,
  output logic                  m_axis_rc_tvalid,
  input  logic                  m_axis_rc_tready,
  output logic [74:0]           m_axis_rc_tuser,

  output logic        rx_accept_o,
  output logic [7:0]  rx_hdr0_o,
  output logic [9:0]  rx_len_dw_o,
  output logic        tag_free_o
);

  import rivet_pkg::*;

  typedef enum logic [2:0] {
    ST_IDLE  = 3'd0,
    ST_DESC0 = 3'd1,
    ST_DESC1 = 3'd2,
    ST_PAY   = 3'd3,
    ST_TAIL  = 3'd4,
    ST_DROP  = 3'd5
  } st_e;

  st_e          st_q;
  logic [7:0]   hdr0_q;
  logic [9:0]   len_q;
  logic [15:0]  req_id_q;
  logic [7:0]   tag_q;
  logic [6:0]   lower_addr_q;
  logic [11:0]  byte_cnt_q;
  logic [2:0]   status_q;
  logic [255:0] res_q;
  logic [5:0]   res_n_q;
  logic         has_data_q;
  logic         has_more_q;
  logic [255:0] pay_d;
  logic [7:0]   pay_k;
  logic         pay_last;
  logic         pay_emit;

  assign rx_tready_o = (st_q == ST_IDLE) || (st_q == ST_DROP) ||
                       ((st_q == ST_PAY) && has_more_q && m_axis_rc_tready);

  assign m_axis_rc_tvalid = (st_q == ST_DESC0) || (st_q == ST_DESC1) ||
                            ((st_q == ST_PAY) && !has_more_q) ||
                            ((st_q == ST_PAY) && has_more_q && rx_tvalid_i && pay_emit) ||
                            (st_q == ST_TAIL);
  assign m_axis_rc_tlast  = pay_last ||
                            (st_q == ST_DESC1 && !has_data_q);
  assign m_axis_rc_tuser  = {42'h0, (st_q == ST_DESC0), 32'h0000_000F};

  function automatic logic [5:0] keep_nbytes(input logic [31:0] k);
    logic [5:0] n;
    n = '0;
    for (int unsigned i = 0; i < 32; i++)
      if (k[i])
        n = n + 6'd1;
    return n;
  endfunction

  function automatic logic [7:0] dw_keep(input logic [5:0] n);
    logic [7:0] k;
    logic [5:0] ndw;
    k   = '0;
    ndw = (n + 6'd3) >> 2;
    for (int unsigned i = 0; i < 8; i++)
      if (6'(i) < ndw)
        k[i] = 1'b1;
    return k;
  endfunction

  always_comb begin
    logic [5:0]   nb;
    logic [6:0]   sum;
    logic [511:0] wide;
    pay_d    = '0;
    pay_k    = '0;
    pay_last = 1'b0;
    pay_emit = 1'b0;
    nb       = keep_nbytes(rx_tkeep_i);
    wide     = '0;
    sum      = '0;
    if (st_q == ST_PAY) begin
      for (int unsigned i = 0; i < 32; i++)
        if (6'(i) < res_n_q)
          wide[8*i +: 8] = res_q[8*i +: 8];
      if (has_more_q && rx_tvalid_i) begin
        for (int unsigned i = 0; i < 32; i++)
          if (6'(i) < nb)
            wide[8*(32'(res_n_q) + i) +: 8] = rx_tdata_i[8*i +: 8];
        sum = {1'b0, res_n_q} + {1'b0, nb};
      end else begin
        sum = {1'b0, res_n_q};
      end
      if (sum >= 7'd32) begin
        pay_d    = wide[255:0];
        pay_k    = 8'hFF;
        pay_last = rx_tlast_i && (sum == 7'd32);
        pay_emit = 1'b1;
      end else if (!has_more_q || (rx_tvalid_i && rx_tlast_i)) begin
        pay_d    = wide[255:0];
        pay_k    = dw_keep(sum[5:0]);
        pay_last = 1'b1;
        pay_emit = 1'b1;
      end
    end else if (st_q == ST_TAIL) begin
      pay_d    = res_q;
      pay_k    = dw_keep(res_n_q);
      pay_last = 1'b1;
    end
  end

  always_comb begin
    m_axis_rc_tdata = '0;
    m_axis_rc_tkeep = '0;
    unique case (st_q)
      ST_DESC0: begin
        m_axis_rc_tdata[6:0]   = lower_addr_q;
        m_axis_rc_tdata[27:16] = byte_cnt_q;
        m_axis_rc_tdata[42:32] = {1'b0, len_q};
        m_axis_rc_tdata[45:43] = status_q;
        m_axis_rc_tkeep        = 8'h03;
      end
      ST_DESC1: begin
        m_axis_rc_tdata[7:0]   = tag_q;
        m_axis_rc_tdata[31:16] = req_id_q;
        m_axis_rc_tkeep        = 8'h03;
      end
      ST_PAY, ST_TAIL: begin
        m_axis_rc_tdata = DATA_W'(pay_d);
        m_axis_rc_tkeep = pay_k;
      end
      default: ;
    endcase
  end

  assign rx_hdr0_o   = hdr0_q;
  assign rx_len_dw_o = (hdr0_q == RIVET_TLP_B0_CPLD) ?
                       ((len_q == 10'd0) ? 10'd1 : len_q) : 10'd0;
  assign rx_accept_o = (st_q == ST_DESC0) && m_axis_rc_tvalid && m_axis_rc_tready;
  assign tag_free_o  = rx_accept_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q         <= ST_IDLE;
      hdr0_q       <= '0;
      len_q        <= '0;
      req_id_q     <= '0;
      tag_q        <= '0;
      lower_addr_q <= '0;
      byte_cnt_q   <= '0;
      status_q     <= '0;
      res_q        <= '0;
      res_n_q      <= '0;
      has_data_q   <= 1'b0;
      has_more_q   <= 1'b0;
    end else if (rx_abort_i) begin
      st_q       <= ST_IDLE;
      has_data_q <= 1'b0;
      has_more_q <= 1'b0;
      res_n_q    <= '0;
    end else begin
      unique case (st_q)
        ST_IDLE: begin
          if (rx_tvalid_i && rx_tready_o) begin
            logic [5:0] nb;
            logic [5:0] pn;
            hdr0_q       <= rx_tdata_i[7:0];
            len_q        <= rivet_tlp_len_dw(rx_tdata_i[23:16], rx_tdata_i[31:24]);
            status_q     <= rx_tdata_i[55:53];
            byte_cnt_q   <= {rx_tdata_i[51:48], rx_tdata_i[63:56]};
            req_id_q     <= {rx_tdata_i[79:72], rx_tdata_i[71:64]};
            tag_q        <= rx_tdata_i[87:80];
            lower_addr_q <= rx_tdata_i[94:88];
            nb = keep_nbytes(rx_tkeep_i);
            pn = (nb > 6'd12) ? (nb - 6'd12) : 6'd0;
            res_q <= '0;
            for (int unsigned i = 0; i < 20; i++)
              if (6'(i) < pn)
                res_q[8*i +: 8] <= rx_tdata_i[8*(i + 12) +: 8];
            res_n_q <= pn;
            if ((rx_tdata_i[7:0] == RIVET_TLP_B0_CPL) ||
                (rx_tdata_i[7:0] == RIVET_TLP_B0_CPLD)) begin
              has_data_q <= (rx_tdata_i[7:0] == RIVET_TLP_B0_CPLD);
              has_more_q <= (rx_tdata_i[7:0] == RIVET_TLP_B0_CPLD) && !rx_tlast_i;
              st_q       <= ST_DESC0;
            end else if (!rx_tlast_i) begin
              st_q <= ST_DROP;
            end
          end
        end
        ST_DESC0: begin
          if (m_axis_rc_tvalid && m_axis_rc_tready)
            st_q <= ST_DESC1;
        end
        ST_DESC1: begin
          if (m_axis_rc_tvalid && m_axis_rc_tready) begin
            if (has_data_q)
              st_q <= ST_PAY;
            else
              st_q <= ST_IDLE;
          end
        end
        ST_PAY: begin
          if (!has_more_q) begin
            if (m_axis_rc_tvalid && m_axis_rc_tready) begin
              res_n_q    <= '0;
              has_data_q <= 1'b0;
              st_q       <= ST_IDLE;
            end
          end else if (rx_tvalid_i && rx_tready_o) begin
            logic [5:0]   nb;
            logic [6:0]   sum;
            logic [511:0] wide;
            nb   = keep_nbytes(rx_tkeep_i);
            wide = '0;
            for (int unsigned i = 0; i < 32; i++)
              if (6'(i) < res_n_q)
                wide[8*i +: 8] = res_q[8*i +: 8];
            for (int unsigned i = 0; i < 32; i++)
              if (6'(i) < nb)
                wide[8*(32'(res_n_q) + i) +: 8] = rx_tdata_i[8*i +: 8];
            sum = {1'b0, res_n_q} + {1'b0, nb};
            if (sum >= 7'd32) begin
              res_q   <= wide[511:256];
              res_n_q <= 6'(sum - 7'd32);
              if (rx_tlast_i && (sum == 7'd32)) begin
                has_more_q <= 1'b0;
                st_q       <= ST_IDLE;
              end else if (rx_tlast_i) begin
                has_more_q <= 1'b0;
                st_q       <= ST_TAIL;
              end
            end else if (rx_tlast_i) begin
              res_n_q    <= '0;
              has_more_q <= 1'b0;
              has_data_q <= 1'b0;
              st_q       <= ST_IDLE;
            end else begin
              res_q   <= wide[255:0];
              res_n_q <= sum[5:0];
            end
          end
        end
        ST_TAIL: begin
          if (m_axis_rc_tvalid && m_axis_rc_tready) begin
            res_n_q    <= '0;
            has_data_q <= 1'b0;
            st_q       <= ST_IDLE;
          end
        end
        ST_DROP: begin
          if (rx_tvalid_i && rx_tready_o && rx_tlast_i)
            st_q <= ST_IDLE;
        end
        default: st_q <= ST_IDLE;
      endcase
    end
  end

endmodule : rivet_tl_rc_g4

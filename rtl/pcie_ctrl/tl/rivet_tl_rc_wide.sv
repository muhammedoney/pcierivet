// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// Pack a 16-byte Cpl/CplD stream into the 128-bit Requester Completion port.
// The first beat is the 12-byte header plus the first data dword. Two
// descriptor beats follow, in the low 64 bits, then one 16-byte payload
// beat per cycle.

module rivet_tl_rc_wide #(
  parameter int unsigned DATA_W = 128
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [127:0] rx_tdata_i,
  input  logic [15:0]  rx_tkeep_i,
  input  logic         rx_tlast_i,
  input  logic         rx_tvalid_i,
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
    ST_DATA  = 3'd3,
    ST_MORE  = 3'd4,
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
  logic [31:0]  data_q;
  logic         has_data_q;
  logic         has_more_q;

  assign rx_tready_o = (st_q == ST_IDLE) || (st_q == ST_DROP) ||
                       ((st_q == ST_MORE) && m_axis_rc_tready);

  assign m_axis_rc_tvalid = (st_q == ST_DESC0) || (st_q == ST_DESC1) ||
                            (st_q == ST_DATA && has_data_q) ||
                            ((st_q == ST_MORE) && rx_tvalid_i);
  assign m_axis_rc_tkeep  = (st_q == ST_MORE)
                            ? {|rx_tkeep_i[15:12], |rx_tkeep_i[11:8],
                               |rx_tkeep_i[7:4],   |rx_tkeep_i[3:0]}
                            : ((st_q == ST_DATA) ? 4'b0001 : 4'b0011);
  assign m_axis_rc_tlast  = (st_q == ST_DESC1 && !has_data_q) ||
                            (st_q == ST_DATA && has_data_q && !has_more_q) ||
                            (st_q == ST_MORE && rx_tlast_i);
  assign m_axis_rc_tuser  = {42'h0, (st_q == ST_DESC0), 32'h0000_000F};

  always_comb begin
    m_axis_rc_tdata = '0;
    unique case (st_q)
      ST_DESC0: begin
        m_axis_rc_tdata[6:0]   = lower_addr_q;
        m_axis_rc_tdata[27:16] = byte_cnt_q;
        m_axis_rc_tdata[42:32] = {1'b0, len_q};
        m_axis_rc_tdata[45:43] = status_q;
      end
      ST_DESC1: begin
        m_axis_rc_tdata[7:0]   = tag_q;
        m_axis_rc_tdata[31:16] = req_id_q;
      end
      ST_DATA: m_axis_rc_tdata = {{(DATA_W-32){1'b0}}, data_q};
      ST_MORE: m_axis_rc_tdata = DATA_W'(rx_tdata_i);
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
      data_q       <= '0;
      has_data_q   <= 1'b0;
      has_more_q   <= 1'b0;
    end else begin
      unique case (st_q)
        ST_IDLE: begin
          if (rx_tvalid_i && rx_tready_o) begin
            hdr0_q       <= rx_tdata_i[7:0];
            len_q        <= rivet_tlp_len_dw(rx_tdata_i[23:16], rx_tdata_i[31:24]);
            status_q     <= rx_tdata_i[55:53];
            byte_cnt_q   <= {rx_tdata_i[51:48], rx_tdata_i[63:56]};
            req_id_q     <= {rx_tdata_i[79:72], rx_tdata_i[71:64]};
            tag_q        <= rx_tdata_i[87:80];
            lower_addr_q <= rx_tdata_i[94:88];
            data_q       <= rx_tdata_i[127:96];
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
              st_q <= ST_DATA;
            else
              st_q <= ST_IDLE;
          end
        end
        ST_DATA: begin
          if (m_axis_rc_tvalid && m_axis_rc_tready) begin
            has_data_q <= 1'b0;
            if (has_more_q)
              st_q <= ST_MORE;
            else
              st_q <= ST_IDLE;
          end
        end
        ST_MORE: begin
          if (rx_tvalid_i && rx_tready_o && rx_tlast_i) begin
            has_more_q <= 1'b0;
            st_q <= ST_IDLE;
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

endmodule : rivet_tl_rc_wide

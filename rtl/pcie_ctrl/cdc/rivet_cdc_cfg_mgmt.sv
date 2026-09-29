// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// cfg_mgmt CDC: user_clk PG213 pulses ↔ pclk cfg_space via common_cells
// cc_cdc_2phase (req + rsp).

module rivet_cdc_cfg_mgmt (
  input  logic        user_clk_i,
  input  logic        user_rst_ni,
  input  logic        pclk_i,
  input  logic        preset_ni,

  // User (PG213 Table 26)
  input  logic [9:0]  cfg_mgmt_addr_i,
  input  logic [7:0]  cfg_mgmt_function_number_i,
  input  logic        cfg_mgmt_write_i,
  input  logic [31:0] cfg_mgmt_write_data_i,
  input  logic [3:0]  cfg_mgmt_byte_enable_i,
  input  logic        cfg_mgmt_read_i,
  output logic [31:0] cfg_mgmt_read_data_o,
  output logic        cfg_mgmt_read_write_done_o,
  input  logic        cfg_mgmt_debug_access_i,

  // Config space (pclk)
  output logic [9:0]  space_addr_o,
  output logic [7:0]  space_function_number_o,
  output logic        space_write_o,
  output logic [31:0] space_write_data_o,
  output logic [3:0]  space_byte_enable_o,
  output logic        space_read_o,
  input  logic [31:0] space_read_data_i,
  input  logic        space_read_write_done_i,
  output logic        space_debug_access_o
);

  typedef struct packed {
    logic [9:0]  addr;
    logic [7:0]  fn;
    logic        write;
    logic [31:0] wdata;
    logic [3:0]  be;
    logic        debug;
  } req_t;

  typedef struct packed {
    logic [31:0] rdata;
  } rsp_t;

  // ---- user → pclk request ----
  req_t  u_req_data, p_req_data;
  logic  u_req_valid, u_req_ready;
  logic  p_req_valid, p_req_ready;

  typedef enum logic [1:0] { U_IDLE, U_REQ, U_WAIT } u_st_e;
  u_st_e u_st_q;
  req_t  u_lat_q;

  assign u_req_data = u_lat_q;

  always_ff @(posedge user_clk_i or negedge user_rst_ni) begin
    if (!user_rst_ni) begin
      u_st_q  <= U_IDLE;
      u_lat_q <= '0;
    end else begin
      unique case (u_st_q)
        U_IDLE: begin
          if (cfg_mgmt_read_i || cfg_mgmt_write_i) begin
            u_lat_q.addr  <= cfg_mgmt_addr_i;
            u_lat_q.fn    <= cfg_mgmt_function_number_i;
            u_lat_q.write <= cfg_mgmt_write_i;
            u_lat_q.wdata <= cfg_mgmt_write_data_i;
            u_lat_q.be    <= cfg_mgmt_byte_enable_i;
            u_lat_q.debug <= cfg_mgmt_debug_access_i;
            u_st_q        <= U_REQ;
          end
        end
        U_REQ: begin
          if (u_req_valid && u_req_ready)
            u_st_q <= U_WAIT;
        end
        U_WAIT: begin
          if (cfg_mgmt_read_write_done_o)
            u_st_q <= U_IDLE;
        end
        default: u_st_q <= U_IDLE;
      endcase
    end
  end

  assign u_req_valid = (u_st_q == U_REQ);

  cc_cdc_2phase #(.data_t(req_t)) u_req_cdc (
    .src_rst_ni (user_rst_ni),
    .src_clk_i  (user_clk_i),
    .src_data_i (u_req_data),
    .src_valid_i(u_req_valid),
    .src_ready_o(u_req_ready),
    .dst_rst_ni (preset_ni),
    .dst_clk_i  (pclk_i),
    .dst_data_o (p_req_data),
    .dst_valid_o(p_req_valid),
    .dst_ready_i(p_req_ready)
  );

  // ---- pclk space access ----
  typedef enum logic [1:0] { P_IDLE, P_PULSE, P_WAIT, P_RSP } p_st_e;
  p_st_e p_st_q;
  req_t  p_lat_q;
  rsp_t  p_rsp_data;
  logic  p_rsp_valid, p_rsp_ready;

  assign space_addr_o            = p_lat_q.addr;
  assign space_function_number_o = p_lat_q.fn;
  assign space_write_data_o      = p_lat_q.wdata;
  assign space_byte_enable_o     = p_lat_q.be;
  assign space_debug_access_o    = p_lat_q.debug;
  assign space_write_o           = (p_st_q == P_PULSE) && p_lat_q.write;
  assign space_read_o            = (p_st_q == P_PULSE) && !p_lat_q.write;
  assign p_req_ready             = (p_st_q == P_IDLE);
  assign p_rsp_data.rdata        = space_read_data_i;
  assign p_rsp_valid             = (p_st_q == P_RSP);

  always_ff @(posedge pclk_i or negedge preset_ni) begin
    if (!preset_ni) begin
      p_st_q  <= P_IDLE;
      p_lat_q <= '0;
    end else begin
      unique case (p_st_q)
        P_IDLE: begin
          if (p_req_valid && p_req_ready) begin
            p_lat_q <= p_req_data;
            p_st_q  <= P_PULSE;
          end
        end
        P_PULSE: p_st_q <= P_WAIT;
        P_WAIT: begin
          if (space_read_write_done_i)
            p_st_q <= P_RSP;
        end
        P_RSP: begin
          if (p_rsp_valid && p_rsp_ready)
            p_st_q <= P_IDLE;
        end
        default: p_st_q <= P_IDLE;
      endcase
    end
  end

  // ---- pclk → user response ----
  rsp_t  u_rsp_data;
  logic  u_rsp_valid, u_rsp_ready;

  cc_cdc_2phase #(.data_t(rsp_t)) u_rsp_cdc (
    .src_rst_ni (preset_ni),
    .src_clk_i  (pclk_i),
    .src_data_i (p_rsp_data),
    .src_valid_i(p_rsp_valid),
    .src_ready_o(p_rsp_ready),
    .dst_rst_ni (user_rst_ni),
    .dst_clk_i  (user_clk_i),
    .dst_data_o (u_rsp_data),
    .dst_valid_o(u_rsp_valid),
    .dst_ready_i(u_rsp_ready)
  );

  assign u_rsp_ready = (u_st_q == U_WAIT);
  assign cfg_mgmt_read_data_o       = u_rsp_data.rdata;
  assign cfg_mgmt_read_write_done_o = u_rsp_valid && u_rsp_ready;

endmodule : rivet_cdc_cfg_mgmt

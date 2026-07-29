// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
//
// LTSSM timeout counter. One instance serves the whole state machine because
// LTSSM states are mutually exclusive: the state machine reloads the counter
// with the limit of the state it is entering.

module rivet_mac_timer #(
  parameter int unsigned WIDTH = 32
) (
  input  logic             pclk_i,
  input  logic             rst_ni,

  input  logic             load_i,   // restart with limit_i
  input  logic [WIDTH-1:0] limit_i,  // cycles to count before expiry

  output logic             expired_o
);

  logic [WIDTH-1:0] count_q;
  logic             expired_q;

  always_ff @(posedge pclk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_q   <= '0;
      expired_q <= 1'b0;
    end else if (load_i) begin
      count_q   <= limit_i;
      expired_q <= (limit_i == '0);
    end else if (count_q != '0) begin
      count_q   <= count_q - 1'b1;
      expired_q <= (count_q == {{(WIDTH-1){1'b0}}, 1'b1});
    end
  end

  assign expired_o = expired_q;

endmodule : rivet_mac_timer

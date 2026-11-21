# Rivet performance note

Rivet is a soft PCIe endpoint. The controller is `rivet_pcie_ctrl`. The numbers below are only figures a tool actually printed.

## What was measured

The VMK180 (XCVM1802, PG345 GTY) Gen2 x4 implementation closed timing. The routed report in `fpga/vmk180/impl.log` is:

- WNS +0.143 ns (property 0.142599 ns)
- TNS 0
- WHS +0.019 ns (property 0.018743 ns)
- THS 0

That is setup and hold slack on the FPGA. It is not a data-rate measurement.

## What was not measured

Four Questa tests sample the user ports that already exist (AXI-ST CQ/CC/RQ/RC and `pcie_tfc_nph_av` / `pcie_tfc_npd_av`):

- `perf_rq_memwr_gen2_x4` — 64 posted 1DW writes, payload bytes and cycles stalled on `tready`
- `perf_rq_rc_lat_gen2_x4` — eight memory reads, `user_clk` cycles from RQ accept to RC CplD, including the PIPE peer
- `perf_cq_cc_gen2_x4` — eight inbound reads answered on CC, 4 payload bytes each
- `perf_credit_stall_gen2_x4` — share of cycles an RQ beat is waiting while non-posted header credit is 0

`vlog` of the suite completed on 21 Nov 2026. `vsim` then exited with "Unable to checkout a license". No payload throughput, latency, or credit-stall percentage is published from that run.

The PG213 and PG239 benches now count accepted beats on the endpoint application. Those simulations were not run in this pass, so they contribute no beat counts either.

## Line rate, for scale only

Gen2 x4 after 8b/10b is 16 Gbit/s per direction, 2.000 GB/s of symbol data. Useful TLP payload is lower once headers, LCRC, and DLLPs are removed. A percentage of that 2.000 GB/s is a measurement only after a test prints `mb_s` and `pct_gen2x4`.

In the UVM bench `user_clk` is 8 ns. A 64-bit beat every cycle is 1.000 GB/s on that bus. The PIPE clock in the same bench is 4 ns.

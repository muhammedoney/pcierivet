# QuestaSim UVM compile order (relative to repo root)
# Soft controller RTL (includes CDC submodules)
-f rtl/filelist_core.f

rtl/interfaces/rivet_pipe_if.sv
rtl/interfaces/rivet_link_status_if.sv
rtl/interfaces/rivet_axi_st_if.sv
rtl/interfaces/rivet_cfg_mgmt_if.sv
rtl/interfaces/rivet_companion_if.sv
rtl/interfaces/rivet_interrupt_if.sv
tb/uvm/rivet_uvm_pkg.sv
tb/uvm/rivet_tb_top.sv

// Copyright 2026 Rivet contributors
// SPDX-License-Identifier: Apache-2.0
// Downstream master tries preset 0, then preset 1, then applies one
// coefficient and a margin message. Compile with RIVET_TB_MODE=1.

class smoke_eq_search_gen3_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_eq_search_gen3_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 3;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_gen3", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_upstream", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen3_l0_vseq vseq;
    rivet_link_status_vif st;
    phase.raise_objection(this);
    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", st))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")
    st.eq_search = 1'b1;
    vseq = rivet_gen3_l0_vseq::type_id::create("gen3_l0_vseq");
    vseq.start(env.vsqr);
    if (!st.eq_saw_preset0 || !st.eq_saw_preset1)
      `uvm_error(get_type_name(),
        $sformatf("preset search preset0=%0b preset1=%0b",
                  st.eq_saw_preset0, st.eq_saw_preset1))
    else
      `uvm_info(get_type_name(), "Preset 0 then preset 1 at 8 GT/s", UVM_LOW)
    st.margin_msg = 8'h15;
    st.coeff_value = 6'h15;
    st.coeff_go = 1'b1;
    repeat (8) @(posedge st.pclk);
    st.coeff_go = 1'b0;
    repeat (4) @(posedge st.pclk);
    if (st.txmargin !== 3'd5)
      `uvm_error(get_type_name(), $sformatf("txmargin=%0d, wanted 5", st.txmargin))
    if ((st.txeq_coeff0 !== 6'h15) || (st.txeq_ctrl0 !== 2'b10))
      `uvm_error(get_type_name(),
        $sformatf("coeff=0x%02h ctrl=%0b", st.txeq_coeff0, st.txeq_ctrl0))
    else
      `uvm_info(get_type_name(), "Coefficient 0x15 and margin 5 applied", UVM_LOW)
    st.margin_msg = 8'h00;
    st.eq_search = 1'b0;
    phase.drop_objection(this);
  endtask
endclass : smoke_eq_search_gen3_x4

class smoke_eq_search_gen4_x4 extends rivet_base_test;
  `uvm_component_utils(smoke_eq_search_gen4_x4)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    lanes = 4;
    gen   = 4;
    uvm_config_db#(int unsigned)::set(this, "*", "lanes", lanes);
    uvm_config_db#(int unsigned)::set(this, "*", "gen", gen);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.pipe_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "ltssm_peer_enable", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_gen4", 1'b1);
    uvm_config_db#(bit)::set(this, "env.ltssm_peer", "peer_upstream", 1'b1);
    uvm_config_db#(bit)::set(this, "env.scoreboard", "ltssm_l0_mode", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    rivet_gen4_l0_vseq vseq;
    rivet_link_status_vif st;
    phase.raise_objection(this);
    if (!uvm_config_db#(rivet_link_status_vif)::get(null, "uvm_test_top", "status_vif", st))
      `uvm_fatal(get_type_name(), "rivet_link_status_if not set")
    st.eq_search = 1'b1;
    vseq = rivet_gen4_l0_vseq::type_id::create("gen4_l0_vseq");
    vseq.start(env.vsqr);
    if (!st.eq_saw_preset0 || !st.eq_saw_preset1)
      `uvm_error(get_type_name(),
        $sformatf("preset search preset0=%0b preset1=%0b",
                  st.eq_saw_preset0, st.eq_saw_preset1))
    else
      `uvm_info(get_type_name(), "Preset 0 then preset 1 during Gen4 training", UVM_LOW)
    st.margin_msg = 8'h15;
    st.coeff_value = 6'h2A;
    st.coeff_go = 1'b1;
    repeat (8) @(posedge st.pclk);
    st.coeff_go = 1'b0;
    repeat (4) @(posedge st.pclk);
    if (st.txmargin !== 3'd5)
      `uvm_error(get_type_name(), $sformatf("txmargin=%0d, wanted 5", st.txmargin))
    if ((st.txeq_coeff0 !== 6'h2A) || (st.txeq_ctrl0 !== 2'b10))
      `uvm_error(get_type_name(),
        $sformatf("coeff=0x%02h ctrl=%0b", st.txeq_coeff0, st.txeq_ctrl0))
    else
      `uvm_info(get_type_name(), "Coefficient 0x2A and margin 5 applied", UVM_LOW)
    st.margin_msg = 8'h00;
    st.eq_search = 1'b0;
    phase.drop_objection(this);
  endtask
endclass : smoke_eq_search_gen4_x4

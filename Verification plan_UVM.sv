// -------------------------------------------------------------------------
// 1. Transaction: 
// -------------------------------------------------------------------------
class my_transaction #(parameter WIDTH = 8) extends uvm_sequence_item;
  `uvm_object_param_utils(my_transaction#(WIDTH))

  rand bit [WIDTH-1:0] data;
  rand int delay;

  constraint c_delay { delay inside {[1:10]}; }
  constraint c_data { data inside {[h'00 : h'FF]; }

  function new (string name = "my_transaction");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    my_transaction#(WIDTH) rhs_;
    if (!$cast(rhs_, rhs)) begin
      `uvm_error("do_copy", "Cast failed")
      return;
    end
    
    super.do_copy(rhs); 
    this.data = rhs_.data;
    this.delay = rhs_.delay;
  endfunction
endclass

// -------------------------------------------------------------------------
// Sequence
// -------------------------------------------------------------------------
class my_base_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(my_base_sequence)

  function new (string name = "my_base_sequence");
  super.new(name); 
  endfunction

endclass 

class my_normal_seq extends my_base_sequence;
`uvm_object_utils(my_normal_seq)
    
  virtual task body();
    if (starting_phase != null) starting_phase.raise_objection(this);
    repeat(10) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize()) `uvm_fatal("SEQ", "Randomization failed!")
      finish_item(req);
    end
    if (starting_phase != null) starting_phase.drop_objection(this);
  endtask
endclass

class my_stress_seq extends my_base_sequence;
  `uvm_object_utils(my_stress_seq)

virtual task body();
    `uvm_info("SEQ", "Starting STRESS sequence: zero delays", UVM_LOW)
    if (starting_phase != null) starting_phase.raise_objection(this);
    repeat(50) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { delay == 0; }) begin
        `uvm_fatal("SEQ", "Randomization failed!")
      if(statring_phase != null) statring_phase.raise_objection(this);
      end
      finish_item(req);
    end
  endtask
endclass

class my_corner_data_seq extends my_base_sequence;
  `uvm_object_utils(my_corner_data_seq)

  virtual task body();
    `uvm_info("SEQ", "Starting CORNER DATA sequence", UVM_LOW)
    repeat(20) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { data inside {8'h00, 8'h01, 8'hFE, 8'hFF}; }) begin
        `uvm_fatal("SEQ", "Randomization failed!")
      end
      finish_item(req);
    end
  endtask
endclass                     
                     
class my_toggle_seq extends my_base_sequence;
  `uvm_object_utils(my_toggle_seq)

  virtual task body();
    bit [7:0] current_val = 8'h55; 
    repeat(10) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { data == current_val; }) begin
        `uvm_fatal("SEQ", "Randomization failed!")
      end
      finish_item(req);
      current_val = ~current_val;
    end
  endtask
endclass

class my_idle_seq extends my_base_sequence;
  `uvm_object_utils(my_idle_seq)

  virtual task body();
    repeat(5) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { delay inside {[50:100]}; }) begin
        `uvm_fatal("SEQ", "Randomization failed!")
      end
      finish_item(req);
    end
  endtask
endclass 

// -------------------------------------------------------------------------
// Qualcomm Specifc Sequence: Early Request De-assertion (Power-Gate Glitch)
// -------------------------------------------------------------------------
class my_early_deassert_seq extends my_base_sequence;
  `uvm_object_utils(my_early_deassert_seq)

  function new(string name = "my_early_deassert_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ_QUALCOMM", "Starting EARLY DE-ASSERTION sequence (Glitcher)", UVM_LOW)
    
    repeat(30) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      
      if (!req.randomize() with { delay == 0; }) begin
        `uvm_fatal("SEQ", "Randomization failed!")
      end
      
      finish_item(req);
    end
  endtask
endclass

// -------------------------------------------------------------------------
// Sequencer
// -------------------------------------------------------------------------                     

class my_sequencer extends uvm_sequencer #(my_transaction);
  `uvm_component_utils(my_sequencer)
  function new(string name, uvm_component parent); 
  super.new(name, parent); 
  endfunction
endclass
                     
// -------------------------------------------------------------------------
// 3. Driver: 
// -------------------------------------------------------------------------
class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)
  
  virtual my_interface.DRIVER_MP vif;
  uvm_analysis_port #(my_transaction) drv_ap; 

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual my_interface)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Could not get vif from config_db")
    drv_ap = uvm_analysis_port #(my_transaction)::type_id::create("drv_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.drv_cb.reset_n <= 0;
    vif.drv_cb.req     <= 0;
    vif.drv_cb.data    <= 0;
    repeat(5) @(vif.drv_cb);
    vif.drv_cb.reset_n <= 1;

    forever begin
      seq_item_port.get_next_item(req);
      drv_ap.write(req); 
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task drive_item(my_transaction tr);
    
   virtual task drive_item(my_transaction tr);
    // Before driving, check if the system is currently power-gated
    if (!vif.pwr_stable || vif.iso_en) begin
      `uvm_info("DRV_POWER", "Block is power-gated. Driving X-states to simulate leakage.", UVM_HIGH)
      vif.drv_cb.req  <= 'x;
      vif.drv_cb.data <= 'x;
      @(vif.drv_cb);
      return;
    end
  
    // Normal Driving Logic
    vif.drv_cb.req  <= 1;
    vif.drv_cb.data <= tr.data;
  
    if (tr.delay == 0) begin
      vif.drv_cb.req <= 0;
      `uvm_info("DRV_QUALCOMM", "Glitch Injected: REQ dropped early!", UVM_HIGH)
    end 
    else begin
      fork
        begin: wait_for_ack
          wait(vif.drv_cb.ack === 1);
        end
        begin: timeout_watchdog
          // If power drops during transaction, stop waiting to prevent driver hang
          fork
            repeat(100) @(vif.drv_cb);
            @ (negedge vif.pwr_stable); 
          join_any
          disable fork;
          if (!vif.pwr_stable) `uvm_info("DRV_POWER", "Transaction aborted due to Power Down", UVM_LOW)
          else `uvm_error("DRV_TIMEOUT", "DUT failed to respond with ACK within 100 cycles!")
        end
      join_any
      disable fork; 
  
      repeat(tr.delay) @(vif.drv_cb);
      vif.drv_cb.req  <= 0;
    end
    @(vif.drv_cb);
  endtask
endclass

// -------------------------------------------------------------------------
// 4. Monitor: 
// -------------------------------------------------------------------------
class my_monitor extends uvm_monitor;
  `uvm_component_utils(my_monitor)
  virtual my_interface vif;
  uvm_analysis_port #(my_transaction) mon_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual my_interface)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "Could not get vif from config_db")
      mon_ap = uvm_analysis_port #(my_transaction)::type_id::create("mon_ap", this);
  endfunction

virtual task run_phase(uvm_phase phase);
  forever @(posedge vif.clk or negedge vif.reset_n) begin
    if (vif.reset_n == 0) begin
      `uvm_info("MON", "Reset detected, clearing monitor state", UVM_HIGH)
    end  
    // Monitor must check for valid power states before sampling protocol lines
    else if (!vif.pwr_stable || vif.iso_en) begin
      `uvm_info("MON_POWER", "Block is not active, skipping protocol sampling", UVM_HIGH)
    end
    else if (vif.req === 1'b1 && vif.ack === 1'b1) begin // Using === to handle possible X's safely
      tr = my_transaction::type_id::create("tr");
      tr.data = vif.data;
      mon_ap.write(tr);
      `uvm_info("MON", $sformatf("Sampled Data: %0h", tr.data), UVM_MEDIUM)
    end
  end
endtask
endclass
      
// -------------------------------------------------------------------------
// 5. Checker
// -------------------------------------------------------------------------
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_act)

class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)

  uvm_analysis_imp_exp #(my_transaction, my_scoreboard) exp_imp;
  uvm_analysis_imp_act #(my_transaction, my_scoreboard) act_imp;
  my_transaction exp_queue[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase (uvm_phase phase)
    super.build_phase (phase)
    exp_imp = new("exp_imp", this);
    act_imp = new("act_imp", this);
  endfunction

  function void write_exp(my_transaction tr);
    exp_queue.push_back(tr);
  endfunction

  function void write_act(my_transaction tr);
    if(exp_queue.size() > 0) begin
      my_transaction exp = exp_queue.pop_front();
      if(tr.data == exp.data)
        `uvm_info("SB", $sformatf("MATCH! Data: %0h", tr.data), UVM_LOW)
      else
        `uvm_error("SB", $sformatf("MISMATCH! Exp: %0h, Got: %0h", exp.data, tr.data))
    end else begin
        `uvm_error("SB", "Received unexpected data (Queue empty)")
    end
  endfunction
endclass

// -------------------------------------------------------------------------
// 6. Agent & Env
// -------------------------------------------------------------------------
class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)
  my_driver drv;
  my_monitor mon;
  my_sequencer seqr;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    mon = my_monitor::type_id::create("mon", this);
    if(get_is_active() == UVM_ACTIVE) begin
      drv = my_driver::type_id::create("drv", this);
      seqr = my_sequencer::type_id::create("seqr", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    if(get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass

class my_env extends uvm_env;
  `uvm_component_utils(my_env)
  my_agent agent;
  my_scoreboard sb;
  my_coverage_collector cov;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    agent = my_agent::type_id::create("agent", this);
    sb = my_scoreboard::type_id::create("sb", this);
    cov = my_coverage_collector::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    agent.drv.drv_ap.connect(sb.exp_imp); 
    agent.mon.mon_ap.connect(sb.act_imp);
    agent.mon.mon_ap.connect(cov.analysis_export);
  endfunction
endclass

// -------------------------------------------------------------------------
// 7. Test 
// -------------------------------------------------------------------------
class my_base_test extends uvm_test;
  `uvm_component_utils(my_test)
  my_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    env = my_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_base_sequence seq = my_base_sequence::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.agent.seqr);
    #100ns;
    phase.drop_objection(this);
  endtask
endclass

// -------------------------------------------------------------------------
// 1. Stress Test 
// -------------------------------------------------------------------------
class my_stress_test extends my_base_test;
  `uvm_component_utils(my_stress_test)

  function new (string name, uvm_component parent); 
  super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    set_type_override_by_type(my_base_sequence::get_type(), my_stress_seq::get_type());
    super.build_phase(phase); 
  endfunction
endclass

// -------------------------------------------------------------------------
// 2. Toggle Test 
// -------------------------------------------------------------------------
class my_toggle_test extends my_base_test;
  `uvm_component_utils(my_toggle_test)

  function new (string name, uvm_component parent);
    super.new (name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    set_type_override_by_type(my_base_sequence::get_type(), my_toggle_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass

// -------------------------------------------------------------------------
// 3. Corner Data Test
// -------------------------------------------------------------------------
class my_corner_test extends my_base_test;
  `uvm_component_utils(my_corner_test)

  function new (string name, uvm_component parent);
    super.new (name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    set_type_override_by_type(my_base_sequence::get_type(), my_corner_data_seq::get_type());
    super.build_phase(phase);
  endfunction
endclass

// -------------------------------------------------------------------------
// 7. Qualcomm Qualcomm Glitch Test Integration
// -------------------------------------------------------------------------
class my_qualcomm_glitch_test extends my_base_test;
  `uvm_component_utils(my_qualcomm_glitch_test)
  function new (string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    set_type_override_by_type(my_base_sequence::get_type(), my_early_deassert_seq::get_type());
    super.build_phase(phase); 
  endfunction
endclass
      
// -------------------------------------------------------------------------
// 8. Coverage Collector
// -------------------------------------------------------------------------
class my_coverage_collector extends uvm_subscriber #(my_transaction);
  `uvm_component_utils(my_coverage_collector)

  my_transaction tr;
  real coverage_score;

  covergroup data_cg;
    option.per_instance = 1;
    option.comment = "Coverage for Data and Delay";

    cp_data: coverpoint tr.data {
      bins low    = {[0:h'3F]};
      bins mid    = {[h'40:h'BF]};
      bins high   = {[h'C0:h'FF]};
    }

    cp_delay: coverpoint tr.delay {
      bins short  = {[1:3]};
      bins medium = {[4:7]};
      bins long   = {[8:10]};
    }

    cross_data_delay: cross cp_data, cp_delay;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    data_cg = new();
  endfunction

  virtual function void write(my_transaction t);
    this.tr = t;
    data_cg.sample();
    coverage_score = data_cg.get_inst_coverage();
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("Final Coverage Score: %0.2f%%", coverage_score), UVM_LOW)
  endfunction
endclass
